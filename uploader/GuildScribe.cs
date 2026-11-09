// GuildScribe.exe : installe l'add-on et envoie ses données au site de la guilde.
//
//  - Lancé depuis le dossier du kit (à côté de kit.json) : installation.
//  - Lancé par le raccourci "WoW Forever + GuildScribe" (--play) : lance le jeu,
//    reste dans la zone de notification, envoie le fichier de l'add-on à chaque
//    fois que WoW l'écrit (/reload, déconnexion), puis se ferme après le jeu.
//  - --once : un seul envoi (tests). --uninstall : retire les raccourcis.
//
// Compilé avec le compilateur C# fourni avec Windows (voir kit/Build-MemberKit.ps1).
// Aucun service, aucun démarrage caché, aucune tâche planifiée.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("GuildScribe")]
[assembly: AssemblyProduct("GuildScribe")]
[assembly: AssemblyDescription("Envoie les données de l'add-on WoW GuildScribe au site de la guilde")]
[assembly: AssemblyCompany("GuildScribe")]
[assembly: AssemblyVersion("0.2.0.0")]
[assembly: AssemblyFileVersion("0.2.0.0")]

namespace GuildScribe
{
    static class Paths
    {
        public static readonly string DataDir = Environment.GetEnvironmentVariable("GUILDSCRIBE_DATA") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "GuildScribe");
        public static readonly string Config = Path.Combine(DataDir, "config.json");
        public static readonly string State = Path.Combine(DataDir, "state.json");
        public static readonly string LogFile = Path.Combine(DataDir, "uploader.log");
        public static readonly string AppDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GuildScribe", "app");
        public static readonly string AppExe = Path.Combine(AppDir, "GuildScribe.exe");
        public static readonly string DesktopLink = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "WoW Forever + GuildScribe.lnk");
        public static readonly string MenuLink = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "GuildScribe.lnk");
    }

    static class Log
    {
        static readonly object Gate = new object();
        public static void Write(string msg)
        {
            lock (Gate)
            {
                try
                {
                    Directory.CreateDirectory(Paths.DataDir);
                    File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + "\r\n", Encoding.UTF8);
                    var info = new FileInfo(Paths.LogFile);
                    if (info.Length > 512 * 1024)
                    {
                        var lines = File.ReadAllLines(Paths.LogFile, Encoding.UTF8);
                        var keep = new string[Math.Min(500, lines.Length)];
                        Array.Copy(lines, lines.Length - keep.Length, keep, 0, keep.Length);
                        File.WriteAllLines(Paths.LogFile, keep, Encoding.UTF8);
                    }
                }
                catch { }
            }
        }
    }

    // ------------------------------------------------------------------ JSON

    static class Json
    {
        public static Dictionary<string, object> ReadFile(string path)
        {
            if (!File.Exists(path)) return new Dictionary<string, object>();
            try
            {
                var text = File.ReadAllText(path, Encoding.UTF8).TrimStart('\uFEFF');
                var ser = new JavaScriptSerializer();
                ser.MaxJsonLength = int.MaxValue;
                var d = ser.DeserializeObject(text) as Dictionary<string, object>;
                return d ?? new Dictionary<string, object>();
            }
            catch { return new Dictionary<string, object>(); }
        }

        public static void WriteFile(string path, object value)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, Write(value), new UTF8Encoding(false));
        }

        public static string Write(object value)
        {
            var sb = new StringBuilder();
            WriteValue(sb, value, 0);
            return sb.ToString();
        }

        static void WriteValue(StringBuilder sb, object v, int depth)
        {
            if (depth > 60 || v == null) { sb.Append("null"); return; }
            if (v is string) { WriteString(sb, (string)v); return; }
            if (v is bool) { sb.Append((bool)v ? "true" : "false"); return; }
            if (v is double || v is float)
            {
                double d = Convert.ToDouble(v, CultureInfo.InvariantCulture);
                if (double.IsNaN(d) || double.IsInfinity(d)) sb.Append("null");
                else sb.Append(d.ToString("R", CultureInfo.InvariantCulture));
                return;
            }
            if (v is long || v is int || v is decimal || v is short || v is byte)
            {
                sb.Append(Convert.ToString(v, CultureInfo.InvariantCulture));
                return;
            }
            var dict = v as IDictionary;
            if (dict != null)
            {
                sb.Append('{');
                bool first = true;
                foreach (DictionaryEntry e in dict)
                {
                    if (!first) sb.Append(',');
                    first = false;
                    WriteString(sb, Convert.ToString(e.Key, CultureInfo.InvariantCulture));
                    sb.Append(':');
                    WriteValue(sb, e.Value, depth + 1);
                }
                sb.Append('}');
                return;
            }
            var list = v as IEnumerable;
            if (list != null)
            {
                sb.Append('[');
                bool first = true;
                foreach (var x in list)
                {
                    if (!first) sb.Append(',');
                    first = false;
                    WriteValue(sb, x, depth + 1);
                }
                sb.Append(']');
                return;
            }
            WriteString(sb, v.ToString());
        }

        static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        public static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null;
        }
    }

    // ------------------------------------------------------- Fichier Lua (SavedVariables)

    class LuaReader
    {
        readonly byte[] src;
        int pos;

        LuaReader(byte[] bytes) { src = bytes; }

        public static Dictionary<string, object> ParseFile(string path)
        {
            var r = new LuaReader(File.ReadAllBytes(path));
            var root = new Dictionary<string, object>();
            while (true)
            {
                r.SkipWs();
                if (r.pos >= r.src.Length) break;
                string name = r.ReadIdent();
                if (name == null) throw r.Error("nom de variable attendu");
                r.Expect('=');
                root[name] = r.ReadValue(0);
            }
            return root;
        }

        Exception Error(string msg) { return new FormatException("GuildScribe.lua : " + msg + " (position " + pos + ")"); }

        int Peek() { return pos < src.Length ? src[pos] : -1; }

        void SkipWs()
        {
            while (pos < src.Length)
            {
                byte c = src[pos];
                if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { pos++; continue; }
                if (c == '-' && pos + 1 < src.Length && src[pos + 1] == '-')
                {
                    while (pos < src.Length && src[pos] != '\n') pos++;
                    continue;
                }
                break;
            }
        }

        void Expect(char ch)
        {
            SkipWs();
            if (Peek() != ch) throw Error("'" + ch + "' attendu");
            pos++;
        }

        static bool IsIdentStart(int c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
        static bool IsIdentChar(int c) { return IsIdentStart(c) || (c >= '0' && c <= '9'); }

        // Identifiant suivi de "=" (mais pas "==") ; sinon ne consomme rien.
        string ReadIdent()
        {
            int start = pos;
            if (!IsIdentStart(Peek())) return null;
            while (IsIdentChar(Peek())) pos++;
            string name = Encoding.ASCII.GetString(src, start, pos - start);
            int save = pos;
            SkipWs();
            if (Peek() == '=' && (pos + 1 >= src.Length || src[pos + 1] != '='))
            {
                pos = save;
                return name;
            }
            pos = start;
            return null;
        }

        object ReadValue(int depth)
        {
            if (depth > 60) throw Error("trop imbriqué");
            SkipWs();
            int c = Peek();
            if (c == '{') return ReadTable(depth);
            if (c == '"' || c == '\'') return ReadString();
            if (Match("true")) return true;
            if (Match("false")) return false;
            if (Match("nil")) return null;
            int start = pos;
            while (pos < src.Length && "-+.eE0123456789".IndexOf((char)src[pos]) >= 0) pos++;
            string num = Encoding.ASCII.GetString(src, start, pos - start);
            long l;
            if (long.TryParse(num, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out l)) return l;
            double d;
            if (double.TryParse(num, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
            if (num == "-nan" || num == "nan" || num == "inf" || num == "-inf") return null;
            throw Error("valeur inattendue");
        }

        bool Match(string word)
        {
            if (pos + word.Length > src.Length) return false;
            for (int i = 0; i < word.Length; i++) if (src[pos + i] != word[i]) return false;
            if (pos + word.Length < src.Length && IsIdentChar(src[pos + word.Length])) return false;
            pos += word.Length;
            return true;
        }

        string ReadString()
        {
            byte quote = src[pos++];
            var bytes = new List<byte>();
            while (true)
            {
                if (pos >= src.Length) throw Error("chaîne non terminée");
                byte c = src[pos];
                if (c == quote) { pos++; break; }
                if (c == '\\')
                {
                    pos++;
                    byte n = src[pos];
                    if (n >= '0' && n <= '9')
                    {
                        int v = 0, k = 0;
                        while (k < 3 && pos < src.Length && src[pos] >= '0' && src[pos] <= '9') { v = v * 10 + (src[pos] - '0'); pos++; k++; }
                        bytes.Add((byte)v);
                        continue;
                    }
                    if (n == 'n') bytes.Add((byte)'\n');
                    else if (n == 't') bytes.Add((byte)'\t');
                    else if (n == 'r') bytes.Add((byte)'\r');
                    else bytes.Add(n);
                    pos++;
                }
                else
                {
                    bytes.Add(c);
                    pos++;
                }
            }
            return Encoding.UTF8.GetString(bytes.ToArray());
        }

        object ReadTable(int depth)
        {
            Expect('{');
            var d = new Dictionary<string, object>();
            var intKeys = new Dictionary<long, object>();
            bool allInt = true;
            long n = 1;
            while (true)
            {
                SkipWs();
                if (Peek() == '}') { pos++; break; }
                if (Peek() == '[')
                {
                    pos++;
                    object k = ReadValue(depth + 1);
                    Expect(']');
                    Expect('=');
                    object v = ReadValue(depth + 1);
                    if (k is long) intKeys[(long)k] = v; else allInt = false;
                    d[Convert.ToString(k, CultureInfo.InvariantCulture)] = v;
                }
                else
                {
                    string name = ReadIdent();
                    if (name != null)
                    {
                        Expect('=');
                        d[name] = ReadValue(depth + 1);
                        allInt = false;
                    }
                    else
                    {
                        object v = ReadValue(depth + 1);
                        intKeys[n] = v;
                        d[n.ToString(CultureInfo.InvariantCulture)] = v;
                        n++;
                    }
                }
                SkipWs();
                if (Peek() == ',' || Peek() == ';') pos++;
            }
            // Table 1..n sans trou -> tableau JSON.
            if (d.Count > 0 && allInt)
            {
                var arr = new List<object>();
                for (long i = 1; i <= d.Count; i++)
                {
                    object v;
                    if (!intKeys.TryGetValue(i, out v)) return d;
                    arr.Add(v);
                }
                return arr;
            }
            return d;
        }
    }

    // ------------------------------------------------------------------ WoW

    static class Wow
    {
        static IEnumerable<string> Roots()
        {
            var roots = new List<string>();
            foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            {
                try
                {
                    using (var k = Registry.LocalMachine.OpenSubKey(key))
                    {
                        var p = k == null ? null : k.GetValue("InstallPath") as string;
                        if (!string.IsNullOrEmpty(p))
                        {
                            p = p.TrimEnd('\\');
                            roots.Add(p);
                            var parent = Path.GetDirectoryName(p);
                            if (parent != null) roots.Add(parent);
                        }
                    }
                }
                catch { }
            }
            foreach (var pf in new[] { Environment.GetEnvironmentVariable("ProgramFiles(x86)"), Environment.GetEnvironmentVariable("ProgramFiles") })
                if (!string.IsNullOrEmpty(pf)) roots.Add(Path.Combine(pf, "World of Warcraft"));
            foreach (var drive in DriveInfo.GetDrives())
            {
                try { if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue; } catch { continue; }
                foreach (var rel in new[] { "World of Warcraft", @"Games\World of Warcraft", @"Jeux\World of Warcraft", @"Battle.net\World of Warcraft", @"Program Files (x86)\World of Warcraft" })
                    roots.Add(Path.Combine(drive.RootDirectory.FullName, rel));
            }
            return roots;
        }

        // Renvoie le dossier _forever_ s'il est trouvé.
        public static string ResolveForever(string dir)
        {
            if (string.IsNullOrEmpty(dir)) return null;
            try
            {
                dir = dir.TrimEnd('\\');
                if (string.Equals(Path.GetFileName(dir), "_forever_", StringComparison.OrdinalIgnoreCase) && Directory.Exists(dir)) return dir;
                var sub = Path.Combine(dir, "_forever_");
                if (Directory.Exists(sub)) return sub;
            }
            catch { }
            return null;
        }

        public static string FindForever()
        {
            foreach (var r in Roots())
            {
                var f = ResolveForever(r);
                if (f != null) return f;
            }
            return null;
        }

        public static List<string> FindSavedFiles(string foreverDir)
        {
            var dirs = new List<string>();
            if (!string.IsNullOrEmpty(foreverDir)) dirs.Add(foreverDir);
            foreach (var r in Roots())
            {
                try
                {
                    if (Directory.Exists(r))
                        foreach (var d in Directory.GetDirectories(r, "_*_")) dirs.Add(d);
                }
                catch { }
            }
            var files = new List<string>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var d in dirs)
            {
                try
                {
                    var acc = Path.Combine(d, "WTF", "Account");
                    if (!Directory.Exists(acc)) continue;
                    foreach (var a in Directory.GetDirectories(acc))
                    {
                        var f = Path.Combine(a, "SavedVariables", "GuildScribe.lua");
                        if (File.Exists(f) && seen.Add(Path.GetFullPath(f))) files.Add(f);
                    }
                }
                catch { }
            }
            return files;
        }

        public static bool IsRunning()
        {
            foreach (var name in new[] { "Wow", "WowClassic", "WowB", "WowT" })
            {
                var procs = Process.GetProcessesByName(name);
                bool any = procs.Length > 0;
                foreach (var p in procs) p.Dispose();
                if (any) return true;
            }
            return false;
        }
    }

    // ---------------------------------------------------------------- Envoi

    static class Uploader
    {
        static readonly object Gate = new object();

        public static Dictionary<string, object> Config() { return Json.ReadFile(Paths.Config); }

        // Envoie les fichiers modifiés depuis le dernier envoi. Renvoie un résumé, ou null s'il n'y avait rien.
        public static string CheckAndSend(bool force)
        {
            lock (Gate)
            {
                var cfg = Config();
                if (Json.Str(cfg, "supabaseUrl") == null || Json.Str(cfg, "uploadToken") == null)
                    throw new InvalidOperationException("configuration absente : relance l'installation.");
                var state = Json.ReadFile(Paths.State);
                var done = new List<string>();
                foreach (var file in Wow.FindSavedFiles(Json.Str(cfg, "wowDir")))
                {
                    var info = new FileInfo(file);
                    long stamp = info.LastWriteTimeUtc.Ticks;
                    object prev;
                    if (!force && state.TryGetValue(file, out prev) && prev != null && Convert.ToInt64(prev, CultureInfo.InvariantCulture) == stamp) continue;
                    // Attend que WoW ait fini d'écrire.
                    if ((DateTime.UtcNow - info.LastWriteTimeUtc).TotalSeconds < 3) continue;
                    done.Add(Send(cfg, file));
                    state[file] = stamp;
                    Json.WriteFile(Paths.State, state);
                }
                return done.Count > 0 ? string.Join(" ; ", done.ToArray()) : null;
            }
        }

        static string Send(Dictionary<string, object> cfg, string file)
        {
            var root = LuaReader.ParseFile(file);
            object db;
            if (!root.TryGetValue("GuildScribeDB", out db) || db == null) return "rien dans " + file;

            var body = new Dictionary<string, object>();
            body["p_token"] = Json.Str(cfg, "uploadToken");
            body["p_payload"] = db;
            var bytes = new UTF8Encoding(false).GetBytes(Json.Write(body));

            var url = Json.Str(cfg, "supabaseUrl").TrimEnd('/') + "/rest/v1/rpc/ingest_guild";
            var key = Json.Str(cfg, "anonKey") ?? "";
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.Method = "POST";
            req.ContentType = "application/json; charset=utf-8";
            req.UserAgent = "GuildScribe/0.3";
            req.Timeout = 60000;
            req.Headers["apikey"] = key;
            // Anciennes clés (JWT "eyJ...") : aussi en Bearer. Nouvelles clés sb_publishable_ : apikey seul.
            if (key.StartsWith("eyJ")) req.Headers["Authorization"] = "Bearer " + key;
            req.ContentLength = bytes.Length;
            using (var s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);

            string text;
            try
            {
                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    text = r.ReadToEnd();
            }
            catch (WebException ex)
            {
                string detail = ex.Message;
                if (ex.Response != null)
                    using (var r = new StreamReader(ex.Response.GetResponseStream(), Encoding.UTF8)) detail = r.ReadToEnd();
                throw new Exception("le site a refusé l'envoi : " + detail);
            }
            var res = new JavaScriptSerializer().DeserializeObject(text) as Dictionary<string, object>;
            var account = Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(file)));
            var summary = string.Format("{0} : {1} guilde(s), {2} membre(s)", account, Json.Str(res, "guilds") ?? "?", Json.Str(res, "members") ?? "?");
            Log.Write("Envoyé " + summary);
            return summary;
        }
    }

    // --------------------------------------------------------- Installation

    static class Installer
    {
        public const string Title = "GuildScribe";

        public static void Run(string kitDir)
        {
            bool installed = File.Exists(Paths.AppExe) && File.Exists(Paths.Config);
            if (installed)
            {
                var answer = MessageBox.Show(
                    "GuildScribe est déjà installé.\n\nOui : mettre à jour\nNon : désinstaller\nAnnuler : ne rien faire",
                    Title, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (answer == DialogResult.Cancel) return;
                if (answer == DialogResult.No) { Uninstall(true); return; }
            }

            var kit = Json.ReadFile(Path.Combine(kitDir, "kit.json"));
            var cfg = Uploader.Config();

            // 1. WoW Forever
            string forever = Wow.ResolveForever(Json.Str(cfg, "wowDir")) ?? Wow.FindForever();
            if (forever == null)
            {
                MessageBox.Show("WoW Forever n'a pas été trouvé automatiquement.\nChoisis le dossier World of Warcraft (ou son sous-dossier _forever_).", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                using (var dlg = new FolderBrowserDialog())
                {
                    dlg.Description = "Dossier World of Warcraft (ou _forever_)";
                    if (dlg.ShowDialog() == DialogResult.OK) forever = Wow.ResolveForever(dlg.SelectedPath);
                }
                if (forever == null) { MessageBox.Show("Aucun dossier _forever_ trouvé. Installation annulée.", Title, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            }

            // 2. Ferme une version de GuildScribe déjà ouverte (pour pouvoir la remplacer).
            Tray.SignalQuit();
            Thread.Sleep(1500);

            // 3. Add-on
            var addonSrc = Path.Combine(kitDir, "GuildScribe");
            var addonDst = Path.Combine(forever, "Interface", "AddOns", "GuildScribe");
            try
            {
                if (Directory.Exists(addonSrc)) CopyDir(addonSrc, addonDst);
            }
            catch (UnauthorizedAccessException)
            {
                MessageBox.Show("Impossible de copier l'add-on dans :\n" + addonDst + "\n\nFerme WoW, puis relance GuildScribe.exe avec clic droit > Exécuter en tant qu'administrateur.", Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // 4. Programme
            Directory.CreateDirectory(Paths.AppDir);
            var self = Assembly.GetExecutingAssembly().Location;
            if (!string.Equals(Path.GetFullPath(self), Path.GetFullPath(Paths.AppExe), StringComparison.OrdinalIgnoreCase))
                File.Copy(self, Paths.AppExe, true);

            // 5. Configuration : un jeton déjà présent (officier) est conservé.
            foreach (var k in new[] { "supabaseUrl", "anonKey", "siteUrl" })
                if (Json.Str(kit, k) != null) cfg[k] = kit[k];
            if (Json.Str(cfg, "uploadToken") == null || Json.Str(kit, "forceToken") == "True")
                if (Json.Str(kit, "uploadToken") != null) cfg["uploadToken"] = kit["uploadToken"];
            cfg["wowDir"] = forever;
            Json.WriteFile(Paths.Config, cfg);

            // 6. Raccourcis
            var wowExe = Path.Combine(forever, "Wow.exe");
            Shortcut(Paths.DesktopLink, Paths.AppExe, "--play", "Lance WoW Forever et envoie les infos de guilde au site", File.Exists(wowExe) ? wowExe : Paths.AppExe);
            Shortcut(Paths.MenuLink, Paths.AppExe, "", "GuildScribe (sans lancer le jeu)", Paths.AppExe);

            Log.Write("Installé (" + forever + ")");
            var go = MessageBox.Show(
                "C'est installé !\n\n" +
                "• Add-on copié dans " + addonDst + "\n" +
                "• Raccourci « WoW Forever + GuildScribe » sur le bureau\n\n" +
                "Lance toujours le jeu avec ce raccourci : GuildScribe envoie tes infos au site " +
                "à chaque /reload ou déconnexion, puis se ferme tout seul après le jeu.\n\n" +
                "Lancer WoW maintenant ?", Title, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (go == DialogResult.Yes) Process.Start(new ProcessStartInfo(Paths.AppExe, "--play") { UseShellExecute = false });
        }

        public static void Uninstall(bool interactive)
        {
            Tray.SignalQuit();
            foreach (var f in new[] { Paths.DesktopLink, Paths.MenuLink })
                try { if (File.Exists(f)) File.Delete(f); } catch { }
            // Anciennes versions (uploader PowerShell) : démarrage automatique.
            try { File.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "GuildScribe Uploader.lnk")); } catch { }
            try { using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true)) if (k != null) k.DeleteValue("GuildScribe Uploader", false); } catch { }
            Thread.Sleep(1500);
            var self = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            if (!string.Equals(self, Path.GetFullPath(Paths.AppExe), StringComparison.OrdinalIgnoreCase))
                try { if (File.Exists(Paths.AppExe)) File.Delete(Paths.AppExe); } catch { }
            Log.Write("Désinstallé");
            if (interactive)
                MessageBox.Show("GuildScribe est désinstallé.\nL'add-on reste dans WoW : supprime le dossier Interface\\AddOns\\GuildScribe si tu n'en veux plus.", Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        static void CopyDir(string src, string dst)
        {
            Directory.CreateDirectory(dst);
            foreach (var f in Directory.GetFiles(src)) File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), true);
            foreach (var d in Directory.GetDirectories(src)) CopyDir(d, Path.Combine(dst, Path.GetFileName(d)));
        }

        static void Shortcut(string lnk, string target, string args, string description, string icon)
        {
            try
            {
                var type = Type.GetTypeFromProgID("WScript.Shell");
                object shell = Activator.CreateInstance(type);
                object sc = type.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                var st = sc.GetType();
                st.InvokeMember("TargetPath", BindingFlags.SetProperty, null, sc, new object[] { target });
                st.InvokeMember("Arguments", BindingFlags.SetProperty, null, sc, new object[] { args });
                st.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, sc, new object[] { Path.GetDirectoryName(target) });
                st.InvokeMember("Description", BindingFlags.SetProperty, null, sc, new object[] { description });
                st.InvokeMember("IconLocation", BindingFlags.SetProperty, null, sc, new object[] { icon + ",0" });
                st.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, null);
            }
            catch (Exception ex)
            {
                Log.Write("Raccourci impossible (" + lnk + ") : " + ex.Message);
            }
        }
    }

    // ------------------------------------------------- Zone de notification

    class Tray : ApplicationContext
    {
        const string QuitEvent = @"Local\GuildScribeQuit";

        public static void SignalQuit()
        {
            try
            {
                EventWaitHandle h;
                if (EventWaitHandle.TryOpenExisting(QuitEvent, out h)) { h.Set(); h.Dispose(); }
            }
            catch { }
        }

        readonly NotifyIcon icon;
        readonly System.Windows.Forms.Timer timer;
        readonly SynchronizationContext ui;
        readonly DateTime started = DateTime.UtcNow;
        readonly bool play;
        bool busy, wowSeen;
        DateTime wowGoneAt = DateTime.MinValue;
        int lastCount;

        public Tray(bool play)
        {
            this.play = play;
            ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

            var menu = new ContextMenuStrip();
            menu.Items.Add("Envoyer maintenant", null, delegate { Check(true); });
            var site = Json.Str(Uploader.Config(), "siteUrl");
            if (site != null) menu.Items.Add("Ouvrir le site de la guilde", null, delegate { Open(site); });
            menu.Items.Add("Voir le journal", null, delegate { Open(Paths.LogFile); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quitter GuildScribe", null, delegate { Quit(); });

            icon = new NotifyIcon();
            icon.Icon = LoadIcon();
            icon.Text = "GuildScribe : en attente de WoW";
            icon.ContextMenuStrip = menu;
            icon.Visible = true;
            icon.DoubleClick += delegate { Check(true); };

            var quit = new EventWaitHandle(false, EventResetMode.AutoReset, QuitEvent);
            ThreadPool.RegisterWaitForSingleObject(quit, delegate { ui.Post(delegate { Quit(); }, null); }, null, -1, true);

            Log.Write("GuildScribe démarré" + (play ? " (avec le jeu)" : ""));
            if (play) LaunchWow();

            timer = new System.Windows.Forms.Timer();
            timer.Interval = 20000;
            timer.Tick += delegate { Tick(); };
            timer.Start();
            Check(false);
        }

        static Icon LoadIcon()
        {
            try
            {
                var wow = Path.Combine(Json.Str(Uploader.Config(), "wowDir") ?? "", "Wow.exe");
                if (File.Exists(wow)) return Icon.ExtractAssociatedIcon(wow);
            }
            catch { }
            return SystemIcons.Information;
        }

        void LaunchWow()
        {
            if (Wow.IsRunning()) return;
            var dir = Json.Str(Uploader.Config(), "wowDir");
            var exe = dir == null ? null : Path.Combine(dir, "Wow.exe");
            if (exe == null || !File.Exists(exe))
            {
                icon.ShowBalloonTip(8000, "GuildScribe", "Wow.exe introuvable : lance le jeu depuis Battle.net, GuildScribe attend.", ToolTipIcon.Warning);
                return;
            }
            try { Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = dir, UseShellExecute = true }); }
            catch (Exception ex)
            {
                Log.Write("Lancement de WoW impossible : " + ex.Message);
                icon.ShowBalloonTip(8000, "GuildScribe", "Impossible de lancer WoW : lance-le depuis Battle.net, GuildScribe attend.", ToolTipIcon.Warning);
            }
        }

        void Tick()
        {
            bool running = Wow.IsRunning();
            if (running) { wowSeen = true; wowGoneAt = DateTime.MinValue; }
            else if (wowSeen && wowGoneAt == DateTime.MinValue) wowGoneAt = DateTime.UtcNow;
            icon.Text = running ? "GuildScribe : WoW en cours" : "GuildScribe : en attente de WoW";

            Check(false);

            // Jeu fermé depuis 40 s (le fichier est écrit à la fermeture) : dernier envoi puis on quitte.
            if (wowGoneAt != DateTime.MinValue && (DateTime.UtcNow - wowGoneAt).TotalSeconds > 40 && !busy)
            {
                Log.Write("WoW fermé : GuildScribe se ferme.");
                Quit();
                return;
            }
            // Jeu jamais lancé : on n'attend pas indéfiniment.
            if (!wowSeen && (DateTime.UtcNow - started).TotalMinutes > (play ? 20 : 60))
            {
                Log.Write("WoW n'a pas été lancé : GuildScribe se ferme.");
                Quit();
            }
        }

        void Check(bool force)
        {
            if (busy) return;
            busy = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                string msg = null, err = null;
                try { msg = Uploader.CheckAndSend(force); }
                catch (Exception ex) { err = ex.Message; Log.Write("Erreur d'envoi : " + err); }
                ui.Post(delegate
                {
                    busy = false;
                    if (msg != null) { lastCount++; icon.ShowBalloonTip(4000, "GuildScribe", "Envoyé au site : " + msg, ToolTipIcon.Info); }
                    else if (err != null) icon.ShowBalloonTip(8000, "GuildScribe : erreur", err, ToolTipIcon.Warning);
                    else if (force) icon.ShowBalloonTip(3000, "GuildScribe", "Rien de nouveau à envoyer (fais /reload en jeu).", ToolTipIcon.Info);
                }, null);
            });
        }

        static void Open(string target)
        {
            try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
        }

        void Quit()
        {
            if (timer != null) timer.Stop();
            icon.Visible = false;
            icon.Dispose();
            ExitThread();
        }
    }

    // ------------------------------------------------------------- Entrée

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
            var argList = new List<string>(args);
            var exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

            // --dump <GuildScribe.lua> <sortie.json> : conversion locale, sans rien envoyer.
            int di = argList.IndexOf("--dump");
            if (di >= 0 && argList.Count > di + 2)
            {
                File.WriteAllText(argList[di + 2], Json.Write(LuaReader.ParseFile(argList[di + 1])), new UTF8Encoding(false));
                return 0;
            }

            if (argList.Contains("--once"))
            {
                try
                {
                    var r = Uploader.CheckAndSend(argList.Contains("--force"));
                    Log.Write(r == null ? "Rien de nouveau à envoyer." : "Test d'envoi réussi.");
                    return 0;
                }
                catch (Exception ex) { Log.Write("Erreur d'envoi : " + ex.Message); return 1; }
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (argList.Contains("--uninstall")) { Installer.Uninstall(true); return 0; }

            bool fromKit = File.Exists(Path.Combine(exeDir, "kit.json"));
            if (argList.Contains("--install") || (fromKit && !argList.Contains("--play")))
            {
                try { Installer.Run(exeDir); }
                catch (Exception ex) { MessageBox.Show("Erreur pendant l'installation :\n" + ex.Message, Installer.Title, MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
                return 0;
            }

            bool created;
            using (var single = new Mutex(true, @"Local\GuildScribeUploader", out created))
            {
                if (!created)
                {
                    // Déjà ouvert : on lance juste le jeu si demandé.
                    if (argList.Contains("--play") && !Wow.IsRunning())
                    {
                        var dir = Json.Str(Uploader.Config(), "wowDir");
                        var exe = dir == null ? null : Path.Combine(dir, "Wow.exe");
                        if (exe != null && File.Exists(exe)) Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = dir, UseShellExecute = true });
                    }
                    return 0;
                }
                if (!File.Exists(Paths.Config))
                {
                    MessageBox.Show("GuildScribe n'est pas encore configuré : décompresse le zip du kit, puis lance GuildScribe.exe depuis le dossier décompressé.", Installer.Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return 1;
                }
                Application.Run(new Tray(argList.Contains("--play")));
            }
            return 0;
        }
    }
}
