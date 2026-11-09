<#
  Installateur GuildScribe pour les membres (lancé par "Installer GuildScribe.bat").
  1. trouve WoW Forever et copie l'add-on dans Interface\AddOns
  2. copie l'uploader dans %LOCALAPPDATA%\GuildScribe\uploader
  3. l'installe avec le jeton de la guilde (kit.json) et le fait démarrer avec Windows
#>
param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA "GuildScribe\uploader"

function Say($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color }

if ($Uninstall) {
  $inst = Join-Path $dest "Install-Uploader.ps1"
  if (Test-Path $inst) { & $inst -Uninstall } else { Say "L'uploader n'est pas installé." }
  Say "L'add-on reste dans WoW : supprime le dossier Interface\AddOns\GuildScribe si tu n'en veux plus." Yellow
  return
}

# Fichiers téléchargés : enlève la marque "venant d'Internet".
Get-ChildItem $here -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$kit = Get-Content (Join-Path $here "kit.json") -Raw -Encoding UTF8 | ConvertFrom-Json

function Resolve-Forever([string]$dir) {
  if (-not $dir) { return $null }
  $dir = $dir.TrimEnd('\')
  if ((Split-Path $dir -Leaf) -ieq "_forever_" -and (Test-Path $dir -PathType Container)) { return $dir }
  $sub = [IO.Path]::Combine($dir, "_forever_")
  if (Test-Path $sub -PathType Container) { return $sub }
  return $null
}

function Find-Forever {
  $candidates = New-Object System.Collections.Generic.List[string]
  foreach ($key in "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
                   "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft") {
    try {
      $p = (Get-ItemProperty $key -ErrorAction Stop).InstallPath
      if ($p) { $candidates.Add($p); $candidates.Add((Split-Path $p.TrimEnd('\') -Parent)) }
    } catch {}
  }
  foreach ($root in ${env:ProgramFiles(x86)}, $env:ProgramFiles) {
    if ($root) { $candidates.Add([IO.Path]::Combine($root, "World of Warcraft")) }
  }
  foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
    foreach ($rel in "World of Warcraft", "Games\World of Warcraft", "Jeux\World of Warcraft", "Battle.net\World of Warcraft") {
      $candidates.Add([IO.Path]::Combine($drive.Root, $rel))
    }
  }
  foreach ($c in $candidates | Select-Object -Unique) {
    $f = Resolve-Forever $c
    if ($f) { return $f }
  }
  return $null
}

Say "=== Installation de GuildScribe ===" Cyan
$forever = Find-Forever
if (-not $forever) {
  Say "WoW Forever introuvable automatiquement : choisis le dossier World of Warcraft (ou _forever_)." Yellow
  Add-Type -AssemblyName System.Windows.Forms
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = "Choisis le dossier World of Warcraft (ou son sous-dossier _forever_)"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $forever = Resolve-Forever $dlg.SelectedPath }
  if (-not $forever) { throw "Aucun dossier _forever_ trouvé. Installation annulée." }
}
Say "WoW Forever : $forever"

# 1. Add-on
$addons = [IO.Path]::Combine($forever, "Interface", "AddOns")
try {
  New-Item -ItemType Directory -Force $addons | Out-Null
  Copy-Item -Recurse -Force (Join-Path $here "GuildScribe") $addons
} catch {
  throw "Impossible de copier l'add-on dans $addons. Ferme WoW, puis relance l'installateur avec clic droit > Exécuter en tant qu'administrateur."
}
Say "Add-on installé dans $addons\GuildScribe" Green

# 2. Uploader (remplace une version précédente)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like "*Start-Uploader.ps1*" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item -Force (Join-Path $here "uploader\*.ps1") $dest

# 3. Config + démarrage auto
& (Join-Path $dest "Install-Uploader.ps1") -SupabaseUrl $kit.supabaseUrl -AnonKey $kit.anonKey -UploadToken $kit.uploadToken -WowDir $forever

Say ""
Say "C'est fini ! Lance WoW Forever : à la sélection du perso, bouton AddOns, vérifie que GuildScribe est coché." Green
Say "Tes infos partiront toutes seules à chaque déconnexion ou /reload." Green
