/* GuildScribe – site de la guilde (sans build, sans framework). */
(function () {
  "use strict";

  const CFG = window.GS_CONFIG || {};
  const DEMO = !CFG.supabaseUrl || !CFG.anonKey || new URLSearchParams(location.search).has("demo");
  const ITEM_URL = CFG.itemUrl || "https://www.wowhead.com/classic/item=";

  const CLASSES = {
    WARRIOR: ["Guerrier", "#C69B6D"], PALADIN: ["Paladin", "#F48CBA"], HUNTER: ["Chasseur", "#AAD372"],
    ROGUE: ["Voleur", "#FFF468"], PRIEST: ["Prêtre", "#FFFFFF"], SHAMAN: ["Chaman", "#0070DD"],
    MAGE: ["Mage", "#3FC7EB"], WARLOCK: ["Démoniste", "#8788EE"], DRUID: ["Druide", "#FF7C0A"],
    DEATHKNIGHT: ["Chevalier de la mort", "#C41E3A"], MONK: ["Moine", "#00FF98"],
    DEMONHUNTER: ["Chasseur de démons", "#A330C9"], EVOKER: ["Évocateur", "#33937F"],
  };
  const RACES = {
    Human: "Humain", Dwarf: "Nain", NightElf: "Elfe de la nuit", Gnome: "Gnome",
    Orc: "Orc", Scourge: "Mort-vivant", Undead: "Mort-vivant", Tauren: "Tauren", Troll: "Troll",
  };

  const S = {
    sb: null, session: null, role: null, userName: "",
    guilds: [], guildKey: null, members: [], notes: {},
    sort: { key: "rank_index", asc: true }, tab: "roster",
  };

  const $ = (sel) => document.querySelector(sel);
  const esc = (v) => String(v == null ? "" : v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const show = (el, on = true) => el.classList.toggle("hidden", !on);
  const shortName = (n) => String(n || "").split("-")[0];
  const asList = (v) => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []);

  function className(m) { return (CLASSES[m.class] || [m.class_localized || m.class || "?"])[0]; }
  function classColor(c) { return (CLASSES[c] || [null, "#b0b0b0"])[1]; }

  function ago(ts) {
    if (!ts) return "—";
    const d = (Date.now() - new Date(ts).getTime()) / 1000;
    if (d < 3600) return "à l'instant";
    if (d < 86400) return `il y a ${Math.floor(d / 3600)} h`;
    const days = Math.floor(d / 86400);
    if (days < 60) return `il y a ${days} j`;
    return `il y a ${Math.floor(days / 30)} mois`;
  }
  const fmtDate = (ts) => (ts ? new Date(ts).toLocaleString("fr-FR", { dateStyle: "medium", timeStyle: "short" }) : "—");

  const SPELL_URL = ITEM_URL.replace(/item=$/, "spell=");
  const SLOT_NAMES = ["Munitions", "Tête", "Cou", "Épaules", "Chemise", "Torse", "Taille", "Jambes", "Pieds", "Poignets",
    "Mains", "Doigt 1", "Doigt 2", "Bijou 1", "Bijou 2", "Dos", "Main droite", "Main gauche", "À distance", "Tabard"];
  const QUALITY = ["#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000", "#e6cc80", "#00ccff"];
  const STANDING = ["", "Haï", "Hostile", "Inamical", "Neutre", "Amical", "Honoré", "Révéré", "Exalté"];

  // La fiche add-on existe en deux formats : 0.1 (champs à plat) et 0.2+ (sections).
  const prof = (m) => m.profile || {};
  const core = (m) => prof(m).core || prof(m);
  function professions(m) {
    const out = new Map();
    for (const p of asList(m.guild_professions)) {
      if (p && p.name) out.set(p.name, { name: p.name, skill: p.skill || 0, max: p.max || null });
    }
    const pr = prof(m).professions;
    for (const p of asList(pr && pr.list ? pr.list : pr)) {
      if (p && p.name) out.set(p.name, { name: p.name, skill: p.skill || 0, max: p.max || null });
    }
    return [...out.values()];
  }
  function gearItems(m) {
    const g = prof(m).gear;
    if (g && g.items) return asList(g.items).filter((x) => x && x.id);
    return asList(g).map((id, i) => ({ slot: i + 1, id })).filter((x) => x.id);
  }
  function recipesByProf(m) {
    const r = prof(m).recipes;
    return r && r.profs && typeof r.profs === "object" ? r.profs : {};
  }
  function specOf(m) {
    const c = core(m);
    if (c.spec) return c.spec;
    const tabs = asList(prof(m).talents && prof(m).talents.tabs);
    if (!tabs.length || !tabs.some((t) => t.p)) return null;
    const best = tabs.reduce((a, b) => ((b.p || 0) > (a.p || 0) ? b : a));
    return best.n ? `${best.n} (${tabs.map((t) => t.p || 0).join("/")})` : null;
  }
  const ilvl = (m) => core(m).ilvl || null;
  const hasAddon = (m) => !!(prof(m).core || prof(m).level);
  const itemLink = (x, label) => {
    const href = x.i || x.id ? ITEM_URL + (x.i || x.id) : x.sp ? SPELL_URL + x.sp : null;
    const color = x.q != null ? ` style="color:${QUALITY[x.q] || "inherit"}"` : "";
    const text = esc(label || x.n || (x.i || x.id ? "objet #" + (x.i || x.id) : "sort #" + x.sp));
    return href ? `<a href="${esc(href)}" target="_blank" rel="noopener"${color}>${text}</a>` : `<span${color}>${text}</span>`;
  };

  /* ---------------------------------------------------------------- Auth */

  async function boot() {
    if (DEMO) {
      const d = window.GS_DEMO();
      S.guilds = d.guilds; S.members = d.members; S.notes = d.notes;
      S.role = "officer"; S.userName = "Mode démo";
      return startApp();
    }

    // Retour de Discord ? (le jeton Discord n'est utile qu'à ce moment-là)
    const fromOAuth = location.hash.includes("access_token") || new URLSearchParams(location.search).has("code");
    S.sb = window.supabase.createClient(CFG.supabaseUrl, CFG.anonKey);
    $("#btn-login").onclick = () => S.sb.auth.signInWithOAuth({
      provider: "discord",
      options: { scopes: "identify guilds.members.read", redirectTo: location.origin + location.pathname },
    });

    const { data } = await S.sb.auth.getSession();
    S.session = data.session;
    if (!S.session) return showLogin();

    // Juste après la connexion Discord : on vérifie l'appartenance au serveur.
    if (fromOAuth && S.session.provider_token) {
      history.replaceState(null, "", location.pathname);
      const r = await fetch("/api/claim", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${S.session.access_token}` },
        body: JSON.stringify({ providerToken: S.session.provider_token }),
      });
      const body = await r.json().catch(() => ({}));
      if (!r.ok) {
        await S.sb.auth.signOut();
        return showLogin(body.error || "Accès refusé.");
      }
    }

    const { data: acc } = await S.sb.from("site_access").select("role, discord_name, checked_at").maybeSingle();
    const fresh = acc && Date.now() - new Date(acc.checked_at).getTime() < 30 * 86400e3;
    if (!fresh) {
      await S.sb.auth.signOut();
      return showLogin("Ton accès a expiré : reconnecte-toi avec Discord.");
    }
    S.role = acc.role; S.userName = acc.discord_name;
    await loadData();
    startApp();
  }

  function showLogin(err) {
    show($("#loading"), false);
    show($("#login"));
    const e = $("#login-error");
    e.textContent = err || "";
    show(e, !!err);
  }

  async function loadData() {
    const [g, m] = await Promise.all([
      S.sb.from("guilds").select("*").order("updated_at", { ascending: false }),
      S.sb.from("members").select("*").limit(5000),
    ]);
    if (g.error) throw g.error;
    if (m.error) throw m.error;
    S.guilds = g.data; S.members = m.data; S.notes = {};
    if (S.role === "officer") {
      const n = await S.sb.from("member_officer_notes").select("guild_key, name, note");
      for (const r of n.data || []) S.notes[r.guild_key + "|" + r.name] = r.note;
    }
  }

  /* ----------------------------------------------------------------- App */

  function startApp() {
    show($("#loading"), false);
    show($("#login"), false);
    show($("#app"));

    $("#user-name").textContent = S.userName;
    $("#user-role").textContent = S.role === "officer" ? "Officier" : "Membre";
    $("#btn-logout").onclick = async () => { if (S.sb) await S.sb.auth.signOut(); location.reload(); };

    const picker = $("#guild-picker");
    picker.innerHTML = S.guilds.map((g) => `<option value="${esc(g.key)}">${esc(g.name)} – ${esc(g.realm)}</option>`).join("");
    show(picker, S.guilds.length > 1);
    picker.onchange = () => selectGuild(picker.value);

    document.querySelectorAll(".tab").forEach((b) => (b.onclick = () => setTab(b.dataset.tab)));
    document.querySelectorAll("th[data-sort]").forEach((th) => (th.onclick = () => {
      const k = th.dataset.sort;
      S.sort = { key: k, asc: S.sort.key === k ? !S.sort.asc : k !== "level" && k !== "ilvl" && k !== "last_online" };
      renderRoster();
    }));
    ["#f-search", "#f-class", "#f-rank", "#f-prof", "#f-online", "#f-addon", "#f-left"].forEach((s) =>
      $(s).addEventListener("input", renderRoster));
    $("#f-days").onchange = renderInactive;
    $("#f-recipe").addEventListener("input", renderRecipes);
    $("#f-bank").addEventListener("input", renderBank);
    document.querySelectorAll("[data-close]").forEach((el) => (el.onclick = closeDrawer));
    document.addEventListener("keydown", (e) => e.key === "Escape" && closeDrawer());

    if (!S.guilds.length) {
      $("#guild-name").textContent = "Aucune donnée";
      $("#guild-sub").textContent = "Lance l'uploader après une session de jeu avec l'add-on.";
      return;
    }
    selectGuild(S.guilds[0].key);
  }

  function guildMembers(includeLeft) {
    return S.members.filter((m) => m.guild_key === S.guildKey && (includeLeft || m.in_guild));
  }

  function selectGuild(key) {
    S.guildKey = key;
    const g = S.guilds.find((x) => x.key === key);
    $("#guild-name").textContent = g.name;
    $("#guild-sub").textContent = g.realm || "";
    const motd = g.info && g.info.motd;
    $("#motd").textContent = motd || "";
    show($("#motd"), !!motd);
    $("#footer").textContent = `Dernier scan : ${fmtDate(g.scanned_at)}${g.scanned_by ? " par " + shortName(g.scanned_by) : ""}${DEMO ? " · données de démonstration" : ""}`;

    const ms = guildMembers(false);
    const fill = (sel, first, values) => {
      $(sel).innerHTML = `<option value="">${first}</option>` + values.map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join("");
    };
    fill("#f-class", "Toutes les classes", [...new Set(ms.map((m) => m.class).filter(Boolean))]
      .map((c) => [c, (CLASSES[c] || [c])[0]]).sort((a, b) => a[1].localeCompare(b[1])));
    const ranks = new Map();
    ms.forEach((m) => m.rank && ranks.set(m.rank_index, m.rank));
    fill("#f-rank", "Tous les rangs", [...ranks.entries()].sort((a, b) => a[0] - b[0]).map(([i, r]) => [String(i), r]));
    fill("#f-prof", "Tous les métiers", [...new Set(ms.flatMap((m) => professions(m).map((p) => p.name)))].sort().map((p) => [p, p]));

    const bank = g.info && g.info.bank;
    show($('.tab[data-tab="bank"]'), !!(bank && asList(bank.tabs).length));
    show($('.tab[data-tab="raids"]'), ms.some((m) => asList(prof(m).lockouts && prof(m).lockouts.list).length));
    if (["bank", "raids"].includes(S.tab) && $(`.tab[data-tab="${S.tab}"]`).classList.contains("hidden")) setTab("roster");

    renderStats();
    renderRoster();
    renderProfs();
    renderRecipes();
    renderInactive();
    renderBank();
    renderRaids();
  }

  function setTab(t) {
    S.tab = t;
    document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b.dataset.tab === t));
    ["roster", "profs", "inactive", "bank", "raids"].forEach((x) => show($("#tab-" + x), x === t));
  }

  function renderStats() {
    const ms = guildMembers(false);
    const maxLvl = Math.max(0, ...ms.map((m) => m.level || 0));
    const ilvls = ms.map(ilvl).filter(Boolean);
    const stats = [
      [ms.length, "membres"],
      [ms.filter((m) => m.online).length, "en ligne au dernier scan"],
      [ms.filter((m) => m.level === maxLvl).length, `niveau ${maxLvl}`],
      [ms.filter(hasAddon).length, "avec l'add-on"],
      [ilvls.length ? (ilvls.reduce((a, b) => a + b, 0) / ilvls.length).toFixed(1) : "—", "iLvl moyen"],
    ];
    $("#stats").innerHTML = stats.map(([v, l]) => `<div class="stat"><div class="v">${esc(v)}</div><div class="l">${esc(l)}</div></div>`).join("");
  }

  function renderRoster() {
    const q = $("#f-search").value.trim().toLowerCase();
    const fc = $("#f-class").value, fr = $("#f-rank").value, fp = $("#f-prof").value;
    const fo = $("#f-online").checked, fa = $("#f-addon").checked, fl = $("#f-left").checked;

    let rows = guildMembers(fl).filter((m) =>
      (!q || [m.name, m.public_note, m.zone, S.notes[m.guild_key + "|" + m.name]].some((x) => x && x.toLowerCase().includes(q))) &&
      (!fc || m.class === fc) && (!fr || String(m.rank_index) === fr) &&
      (!fp || professions(m).some((p) => p.name === fp)) &&
      (!fo || m.online) && (!fa || hasAddon(m)));

    const { key, asc } = S.sort;
    const val = (m) => key === "ilvl" ? ilvl(m) || 0 : key === "class" ? className(m)
      : key === "last_online" ? (m.online ? Date.now() : new Date(m.last_online || 0).getTime())
      : key === "name" ? shortName(m.name).toLowerCase() : m[key] == null ? "" : m[key];
    rows.sort((a, b) => {
      const x = val(a), y = val(b);
      const c = typeof x === "number" && typeof y === "number" ? x - y : String(x).localeCompare(String(y));
      return (asc ? c : -c) || shortName(a.name).localeCompare(shortName(b.name));
    });

    document.querySelectorAll("th[data-sort]").forEach((th) => {
      th.classList.toggle("sorted", th.dataset.sort === key);
      th.classList.toggle("asc", th.dataset.sort === key && asc);
    });

    $("#roster-body").innerHTML = rows.length ? rows.map((m) => `
      <tr data-name="${esc(m.name)}" class="${m.in_guild ? "" : "left"}">
        <td><span class="dot ${m.online ? "on" : ""}"></span><strong style="color:${classColor(m.class)}">${esc(shortName(m.name))}</strong>${hasAddon(m) ? '<span class="addon-mark" title="Fiche détaillée (add-on)">◆</span>' : ""}</td>
        <td class="num">${esc(m.level ?? "")}</td>
        <td>${esc(className(m))}</td>
        <td>${esc(m.rank || "")}</td>
        <td>${professions(m).map((p) => `<span class="prof-chip">${esc(p.name)} ${esc(p.skill)}</span>`).join("")}</td>
        <td class="num">${esc(ilvl(m) ?? "")}</td>
        <td>${esc(m.zone || "")}</td>
        <td>${m.online ? "en ligne" : esc(ago(m.last_online))}</td>
      </tr>`).join("") : `<tr><td colspan="8" class="empty">Personne ne correspond à ces filtres.</td></tr>`;
    $("#roster-body").querySelectorAll("tr[data-name]").forEach((tr) => (tr.onclick = () => openMember(tr.dataset.name)));
    $("#roster-count").textContent = `${rows.length} personne(s) affichée(s)`;
  }

  function renderProfs() {
    const byProf = new Map();
    for (const m of guildMembers(false)) {
      for (const p of professions(m)) {
        if (!byProf.has(p.name)) byProf.set(p.name, []);
        byProf.get(p.name).push({ m, p });
      }
    }
    const cards = [...byProf.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([name, list]) => {
      list.sort((a, b) => b.p.skill - a.p.skill);
      const cap = Math.max(300, ...list.map((x) => x.p.max || x.p.skill || 0));
      return `<div class="prof-card"><h3>${esc(name)} <span>${list.length} artisan(s)</span></h3>
        ${list.map(({ m, p }) => `
          <div class="crafter" data-name="${esc(m.name)}">
            <span class="cname" style="color:${classColor(m.class)}">${esc(shortName(m.name))}${m.online ? ' <span class="dot on"></span>' : ""}</span>
            <span class="muted">${esc(p.skill)}${p.max ? " / " + esc(p.max) : ""}</span>
            <div class="bar"><i style="width:${Math.min(100, (p.skill / cap) * 100)}%"></i></div>
          </div>`).join("")}</div>`;
    });
    $("#profs-grid").innerHTML = cards.join("") || `<p class="empty">Aucun métier connu pour l'instant : il faut que des membres installent l'add-on.</p>`;
    $("#profs-grid").querySelectorAll(".crafter").forEach((el) => (el.onclick = () => openMember(el.dataset.name)));
  }

  // Recherche de recettes : "qui sait fabriquer X ?"
  function renderRecipes() {
    const q = ($("#f-recipe").value || "").trim().toLowerCase();
    const byRecipe = new Map();
    let total = 0;
    for (const m of guildMembers(false)) {
      for (const [profName, p] of Object.entries(recipesByProf(m))) {
        for (const r of asList(p && p.list)) {
          if (!r || !r.n) continue;
          total++;
          if (q && !r.n.toLowerCase().includes(q)) continue;
          const key = profName + "|" + r.n;
          if (!byRecipe.has(key)) byRecipe.set(key, { r, profName, who: [] });
          byRecipe.get(key).who.push({ m, cd: r.cd });
        }
      }
    }
    const box = $("#recipes-result");
    if (!total) {
      box.innerHTML = `<p class="muted small">Les recettes apparaissent quand un membre équipé de l'add-on ouvre la fenêtre de son métier en jeu.</p>`;
      return;
    }
    if (!q) {
      box.innerHTML = `<p class="muted small">${byRecipe.size} recettes connues dans la guilde. Tape un nom pour savoir qui peut la fabriquer.</p>`;
      return;
    }
    const list = [...byRecipe.values()].sort((a, b) => a.r.n.localeCompare(b.r.n)).slice(0, 60);
    const now = Date.now() / 1000;
    box.innerHTML = list.length ? `<ul class="recipe-list">${list.map(({ r, profName, who }) => `
      <li><div>${itemLink(r)} <span class="muted small">${esc(profName)}</span></div>
        <div class="who">${who.map(({ m, cd }) => `<span class="crafter-chip" data-name="${esc(m.name)}" style="color:${classColor(m.class)}">${esc(shortName(m.name))}${m.online ? ' <span class="dot on"></span>' : ""}${cd && cd > now ? ` <span class="muted small" title="Temps de recharge">⏳ ${esc(fmtDate(cd * 1000))}</span>` : ""}</span>`).join("")}</div></li>`).join("")}</ul>`
      : `<p class="empty">Personne ne connaît de recette contenant « ${esc(q)} ».</p>`;
    box.querySelectorAll("[data-name]").forEach((el) => (el.onclick = () => openMember(el.dataset.name)));
  }

  function renderBank() {
    const g = S.guilds.find((x) => x.key === S.guildKey);
    const bank = g && g.info && g.info.bank;
    if (!bank) return;
    const q = ($("#f-bank").value || "").trim().toLowerCase();
    const money = bank.money ? `${Math.floor(bank.money / 10000)} po ${Math.floor(bank.money / 100) % 100} pa` : "";
    $("#bank-meta").textContent = [money, bank.at ? "vue " + ago(bank.at * 1000) : ""].filter(Boolean).join(" · ");
    $("#bank-grid").innerHTML = asList(bank.tabs).map((t) => {
      const items = asList(t.items).filter((x) => !q || (x.n || "").toLowerCase().includes(q));
      if (q && !items.length) return "";
      return `<div class="prof-card"><h3>${esc(t.name || "Onglet")} <span>${items.length} objet(s)</span></h3>
        ${t.viewable === false ? '<p class="muted small">Onglet non visible par l\'uploader.</p>' : ""}
        <ul class="gear">${items.map((x) => `<li>${itemLink(x)}<span class="muted">× ${esc(x.c)}</span></li>`).join("")}</ul></div>`;
    }).join("") || `<p class="empty">Rien ne correspond.</p>`;
  }

  function renderRaids() {
    const now = Date.now() / 1000;
    const byInst = new Map();
    for (const m of guildMembers(false)) {
      for (const l of asList(prof(m).lockouts && prof(m).lockouts.list)) {
        if (!l || !l.n || (l.reset && l.reset < now)) continue;
        const key = l.n + (l.d ? " (" + l.d + ")" : "");
        if (!byInst.has(key)) byInst.set(key, []);
        byInst.get(key).push({ m, l });
      }
    }
    $("#raids-grid").innerHTML = [...byInst.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([name, list]) => `
      <div class="prof-card"><h3>${esc(name)} <span>${list.length} verrouillé(s)</span></h3>
        ${list.map(({ m, l }) => `<div class="crafter" data-name="${esc(m.name)}">
          <span class="cname" style="color:${classColor(m.class)}">${esc(shortName(m.name))}</span>
          <span class="muted small">${l.total ? esc(l.done || 0) + "/" + esc(l.total) + " · " : ""}reset ${esc(fmtDate(l.reset * 1000))}</span></div>`).join("")}
      </div>`).join("") || `<p class="empty">Aucun membre verrouillé en ce moment (d'après les fiches add-on).</p>`;
    $("#raids-grid").querySelectorAll("[data-name]").forEach((el) => (el.onclick = () => openMember(el.dataset.name)));
  }

  function renderInactive() {
    const days = +$("#f-days").value;
    const limit = Date.now() - days * 86400e3;
    const rows = guildMembers(false).filter((m) => !m.online && m.last_online && new Date(m.last_online).getTime() < limit)
      .sort((a, b) => new Date(a.last_online) - new Date(b.last_online));
    $("#inactive-body").innerHTML = rows.length ? rows.map((m) => `
      <tr data-name="${esc(m.name)}">
        <td><strong style="color:${classColor(m.class)}">${esc(shortName(m.name))}</strong></td>
        <td class="num">${esc(m.level ?? "")}</td><td>${esc(className(m))}</td><td>${esc(m.rank || "")}</td>
        <td>${esc(ago(m.last_online))}</td><td class="muted">${esc(m.public_note || "")}</td>
      </tr>`).join("") : `<tr><td colspan="6" class="empty">Personne d'absent depuis plus de ${days} jours.</td></tr>`;
    $("#inactive-body").querySelectorAll("tr[data-name]").forEach((tr) => (tr.onclick = () => openMember(tr.dataset.name)));
  }

  /* --------------------------------------------------------------- Fiche */

  function openMember(name) {
    const m = S.members.find((x) => x.guild_key === S.guildKey && x.name === name);
    if (!m) return;
    const p = prof(m), c = core(m);
    const kv = (rows) => `<dl class="kv">${rows.filter((r) => r[1] != null && r[1] !== "").map(([k, v]) => `<dt>${esc(k)}</dt><dd>${v}</dd>`).join("")}</dl>`;
    const sec = (title, body, when) => (body ? `<section><h4>${esc(title)}${typeof when === "number" ? ` <span class="when">${esc(ago(when * 1000))}</span>` : ""}</h4>${body}</section>` : "");
    const fold = (summary, body) => `<details><summary>${summary}</summary>${body}</details>`;
    const officerNote = S.notes[m.guild_key + "|" + m.name];
    const now = Date.now() / 1000;

    const gear = gearItems(m).sort((a, b) => a.slot - b.slot);
    const gearHtml = gear.length ? `<ul class="gear">${gear.map((x) => `
      <li><span class="muted">${esc(SLOT_NAMES[x.slot] || "Emplacement " + x.slot)}</span>
        <span>${itemLink(x)}${x.l ? ` <span class="muted small">${esc(x.l)}</span>` : ""}${x.e ? ' <span class="small" title="Enchanté">✦</span>' : ""}${x.dur != null && x.dur < 30 ? ` <span class="warn small" title="Durabilité">${esc(x.dur)} %</span>` : ""}</span></li>`).join("")}</ul>` : "";

    const profHtml = professions(m).map((x) => `
      <div class="crafter"><span>${esc(x.name)}</span><span class="muted">${esc(x.skill)}${x.max ? " / " + esc(x.max) : ""}</span>
      <div class="bar"><i style="width:${Math.min(100, (x.skill / Math.max(300, x.max || 0)) * 100)}%"></i></div></div>`).join("");

    const recipes = Object.entries(recipesByProf(m)).sort((a, b) => a[0].localeCompare(b[0]));
    const recipesHtml = recipes.map(([name, r]) => {
      const list = asList(r && r.list);
      return fold(`${esc(name)} <span class="muted small">${list.length} recette(s)</span>`,
        `<ul class="plain">${list.map((x) => `<li>${itemLink(x)}${x.cd && x.cd > now ? ` <span class="muted small">⏳ ${esc(fmtDate(x.cd * 1000))}</span>` : ""}</li>`).join("")}</ul>`);
    }).join("");

    const tal = p.talents;
    const talHtml = tal && asList(tal.tabs).length ? `<div class="chips">${asList(tal.tabs).map((t) => `<span class="prof-chip">${esc(t.n || "?")} <strong>${esc(t.p || 0)}</strong></span>`).join("")}</div>
      ${asList(tal.tabs).filter((t) => asList(t.list).length).map((t) => fold(esc(t.n || "Arbre"),
        `<ul class="plain">${asList(t.list).map((x) => `<li>${esc(x.n)} <span class="muted small">${esc(x.r)}/${esc(x.m)}</span></li>`).join("")}</ul>`)).join("")}
      ${tal.unspent ? `<p class="muted small">${esc(tal.unspent)} point(s) non dépensé(s)</p>` : ""}` : "";

    const st = p.stats;
    const statsHtml = st ? kv([
      ["Vie / ressource", esc([st.hp, st.power].filter((v) => v != null).join(" / "))],
      ["For / Agi / End", esc([st.str, st.agi, st.sta].map((v) => v ?? "—").join(" / "))],
      ["Int / Esp", esc([st.int, st.spi].map((v) => v ?? "—").join(" / "))],
      ["Armure", esc(st.armor)],
      ["Défense", esc(st.defense)],
      ["Esquive / Parade / Blocage", st.dodge != null ? esc(`${st.dodge} % / ${st.parry ?? 0} % / ${st.block ?? 0} %`) : null],
      ["PA / PA distance", esc([st.ap, st.rap].filter((v) => v != null).join(" / "))],
      ["Crit. / Toucher", st.crit != null ? esc(`${st.crit} % / ${st.hit ?? 0} %`) : null],
      ["Puissance des sorts", st.spellPower ? esc(st.spellPower) : null],
      ["Soins", st.healing ? esc(st.healing) : null],
      ["Crit. sorts", st.spellCrit ? esc(st.spellCrit + " %") : null],
      ["Mana / 5 s", st.mp5 ? esc(st.mp5 + (st.mp5Casting != null ? ` (${st.mp5Casting} en incantation)` : "")) : null],
      ["Résistances", st.resist ? esc(["fire", "nature", "frost", "shadow", "arcane"].map((k) => ({ fire: "Feu", nature: "Nature", frost: "Givre", shadow: "Ombre", arcane: "Arcanes" }[k]) + " " + (st.resist[k] ?? 0)).join(" · ")) : null],
    ]) : "";

    const reps = asList(p.reputations && p.reputations.list).filter((x) => x && x.n);
    const repHtml = reps.length ? fold(`${reps.filter((x) => x.s >= 8).length} exalté(s), ${reps.filter((x) => x.s === 7).length} révéré(s)`,
      `<ul class="plain">${reps.sort((a, b) => (b.s || 0) - (a.s || 0)).map((x) => `<li>${esc(x.n)} <span class="muted small">${esc(STANDING[x.s] || "")}${x.max > x.min ? ` ${esc((x.v || 0) - (x.min || 0))}/${esc(x.max - x.min)}` : ""}</span></li>`).join("")}</ul>`) : "";

    const locks = asList(p.lockouts && p.lockouts.list).filter((l) => l && (!l.reset || l.reset > now));
    const lockHtml = locks.length ? `<ul class="plain">${locks.map((l) => `<li>${esc(l.n)}${l.d ? ` <span class="muted small">${esc(l.d)}</span>` : ""}
      <span class="muted small">${l.total ? esc(l.done || 0) + "/" + esc(l.total) + " · " : ""}reset ${esc(fmtDate(l.reset * 1000))}</span></li>`).join("")}</ul>` : "";

    const pvp = p.pvp;
    const pvpHtml = pvp && (pvp.hk || pvp.rank) ? kv([
      ["Rang", esc(pvp.rankName || (pvp.rank ? "Rang " + pvp.rank : null))],
      ["Victoires honorables", esc(pvp.hk)],
      ["Cette semaine", pvp.weekHK != null ? esc(`${pvp.weekHK} VH${pvp.weekHonor ? ", " + pvp.weekHonor + " honneur" : ""}`) : null],
      ["Plus haut rang", esc(pvp.highestRank || null)],
    ]) : "";

    const skills = asList(p.skills && p.skills.list).filter((x) => x && x.n && x.m > 1);
    const skillHtml = skills.length ? fold(`${skills.length} compétence(s)`, `<ul class="plain">${skills.map((x) =>
      `<li>${esc(x.n)} <span class="muted small">${esc(x.r)}/${esc(x.m)}${x.cat ? " · " + esc(x.cat) : ""}</span></li>`).join("")}</ul>`) : "";

    const bagList = (inv) => `<ul class="gear">${asList(inv.items).sort((a, b) => (b.q || 0) - (a.q || 0) || String(a.n).localeCompare(String(b.n)))
      .map((x) => `<li>${itemLink(x)}<span class="muted">× ${esc(x.c)}</span></li>`).join("")}</ul>`;
    const inv = p.inventory, bank = p.bank;
    const invHtml = [
      inv && asList(inv.items).length ? fold(`Sacs <span class="muted small">${asList(inv.items).length} objet(s)${inv.slots ? `, ${inv.free}/${inv.slots} places libres` : ""}</span>`, bagList(inv)) : "",
      bank && asList(bank.items).length ? fold(`Banque <span class="muted small">${asList(bank.items).length} objet(s), vue ${esc(ago(bank.at * 1000))}</span>`, bagList(bank)) : "",
    ].join("");

    const coll = p.collections;
    const collHtml = coll ? kv([
      ["Montures", asList(coll.mounts).length ? esc(asList(coll.mounts).map((x) => x.n).join(", ")) : null],
      ["Mascottes", asList(coll.pets).length ? esc(asList(coll.pets).length) : null],
      ["Monnaies", asList(coll.currencies).length ? esc(asList(coll.currencies).map((x) => `${x.n} ${x.c}`).join(" · ")) : null],
    ]) : "";
    const quests = p.quests;

    $("#drawer-content").innerHTML = `
      <h2 style="color:${classColor(m.class)}">${esc(shortName(m.name))}</h2>
      <div class="muted">${esc([m.level && "Niveau " + m.level, RACES[c.race] || c.raceLocalized || c.race, className(m), specOf(m)].filter(Boolean).join(" · "))}</div>
      ${c.title ? `<div class="muted small">${esc(c.title)}</div>` : ""}
      <section>${kv([
        ["Rang", esc(m.rank)],
        ["Statut", m.online ? '<span class="dot on"></span>en ligne' : esc(ago(m.last_online))],
        ["Zone", esc(m.zone)],
        ["Royaume", esc(m.name.split("-")[1])],
        ["Faction", esc(c.faction)],
        ["Niveau d'objet", esc(c.ilvl)],
        ["Expérience", c.xpMax && m.level ? esc(`${Math.round((c.xp / c.xpMax) * 100)} %${c.rested ? " (+ " + Math.round((c.rested / c.xpMax) * 100) + " % reposé)" : ""}`) : null],
        ["Pierre de foyer", esc(c.bind)],
        ["Hauts faits", esc(m.achievement_points || c.achievementPoints)],
        ["Quêtes terminées", quests && quests.count ? esc(quests.count) : null],
        ["Fiche add-on", hasAddon(m) ? esc(fmtDate(m.profile_at)) + (p.addonVersion ? ` <span class="muted small">v${esc(p.addonVersion)}</span>` : "") : "non installé"],
        m.in_guild ? [] : ["A quitté la guilde", esc(fmtDate(m.left_at))],
      ])}</section>
      ${m.public_note ? `<section><h4>Note publique</h4><div class="note">${esc(m.public_note)}</div></section>` : ""}
      ${officerNote ? `<section><h4>Note d'officier</h4><div class="note officer">${esc(officerNote)}</div></section>` : ""}
      ${sec("Équipement", gearHtml, p.gear && p.gear.at)}
      ${sec("Talents", talHtml, tal && tal.at)}
      ${sec("Métiers", profHtml)}
      ${sec("Recettes", recipesHtml, p.recipes && p.recipes.at)}
      ${sec("Statistiques", statsHtml, st && st.at)}
      ${sec("Raids et donjons verrouillés", lockHtml)}
      ${sec("JcJ", pvpHtml)}
      ${sec("Réputations", repHtml)}
      ${sec("Compétences", skillHtml)}
      ${sec("Collections", collHtml)}
      ${sec("Sacs et banque", invHtml)}
    `;
    show($("#drawer"));
    $("#drawer").setAttribute("aria-hidden", "false");
  }

  function closeDrawer() {
    show($("#drawer"), false);
    $("#drawer").setAttribute("aria-hidden", "true");
  }

  boot().catch((e) => {
    console.error(e);
    showLogin("Erreur de chargement : " + (e.message || e));
  });
})();
