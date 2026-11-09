<#
.SYNOPSIS
  Installe l'uploader GuildScribe : enregistre la config et le lance
  automatiquement (caché) à chaque ouverture de session Windows.
  Aucun droit administrateur nécessaire.

  Démarrage auto : raccourci dans le dossier Démarrage ; si Windows le bloque,
  entrée "Run" du registre utilisateur ; sinon un avertissement s'affiche.

.EXAMPLE
  .\Install-Uploader.ps1 -SupabaseUrl https://xxxx.supabase.co -AnonKey sb_publishable_... -UploadToken abcd...
  .\Install-Uploader.ps1 -Uninstall
#>
param(
  [string]$SupabaseUrl,
  [string]$AnonKey,
  [string]$UploadToken,
  [string]$WowDir,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$dataDir = Join-Path $env:APPDATA "GuildScribe"
$shortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "GuildScribe Uploader.lnk"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runName = "GuildScribe Uploader"

function Stop-Uploader {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*Start-Uploader.ps1*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($Uninstall) {
  Stop-Uploader
  Remove-Item $shortcut -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
  Write-Host "Uploader désinstallé (la config reste dans $dataDir)."
  return
}

if (-not $SupabaseUrl -or -not $AnonKey -or -not $UploadToken) {
  throw "Il faut -SupabaseUrl, -AnonKey et -UploadToken."
}

. (Join-Path $PSScriptRoot "GuildScribe.Parser.ps1")
$found = @(Find-GuildScribeFiles -WowDir $WowDir)
if ($found.Count -eq 0) {
  Write-Host "Pas encore de données de l'add-on : elles arriveront après ta première partie (déconnexion ou /reload)."
} else {
  $found | ForEach-Object { Write-Host "Trouvé : $($_.FullName)" }
}

New-Item -ItemType Directory -Force $dataDir | Out-Null
[ordered]@{
  supabaseUrl = $SupabaseUrl
  anonKey     = $AnonKey
  uploadToken = $UploadToken
  wowDir      = $WowDir
} | ConvertTo-Json | Set-Content (Join-Path $dataDir "config.json") -Encoding UTF8

$script = Join-Path $PSScriptRoot "Start-Uploader.ps1"
$psExe = (Get-Command powershell.exe).Source
$args_ = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

# Démarrage automatique avec Windows.
$autostart = $null
try {
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
  $lnk.TargetPath = $psExe
  $lnk.Arguments = $args_
  $lnk.WorkingDirectory = $PSScriptRoot
  $lnk.WindowStyle = 7
  $lnk.Save()
  if (Test-Path $shortcut) { $autostart = "raccourci du dossier Démarrage" }
} catch {}
if (-not $autostart) {
  try {
    Set-ItemProperty -Path $runKey -Name $runName -Value "`"$psExe`" $args_"
    $autostart = "registre utilisateur (Run)"
  } catch {}
}

Write-Host "Test d'envoi..."
& $script -Once

Stop-Uploader
Start-Process $psExe -ArgumentList $args_ -WindowStyle Hidden
Write-Host "L'uploader tourne en arrière-plan."
if ($autostart) {
  Write-Host "Il démarrera avec Windows ($autostart)."
} else {
  Write-Warning "Windows a bloqué le démarrage automatique (antivirus ?). L'uploader tourne jusqu'au prochain redémarrage : relance l'installation après, ou autorise-le dans l'antivirus."
}
Write-Host "Journal : $dataDir\uploader.log"
