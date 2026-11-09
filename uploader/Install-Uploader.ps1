<#
.SYNOPSIS
  Installe l'uploader GuildScribe : enregistre la config et le lance
  automatiquement (caché) à chaque ouverture de session Windows.
  Aucun droit administrateur nécessaire.

.EXAMPLE
  .\Install-Uploader.ps1 -SupabaseUrl https://xxxx.supabase.co -AnonKey eyJ... -UploadToken abcd...
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

if ($Uninstall) {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like "*Start-Uploader.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Remove-Item $shortcut -ErrorAction SilentlyContinue
  Write-Host "Uploader désinstallé (la config reste dans $dataDir)."
  return
}

if (-not $SupabaseUrl -or -not $AnonKey -or -not $UploadToken) {
  throw "Il faut -SupabaseUrl, -AnonKey et -UploadToken."
}

. (Join-Path $PSScriptRoot "GuildScribe.Parser.ps1")
$found = @(Find-GuildScribeFiles -WowDir $WowDir)
if ($found.Count -eq 0) {
  Write-Warning "Aucun GuildScribe.lua trouvé pour l'instant. Lance WoW avec l'add-on puis déconnecte-toi une fois. Si WoW est installé ailleurs, relance avec -WowDir 'D:\...\World of Warcraft\_forever_'."
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
$args_ = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($shortcut)
$lnk.TargetPath = (Get-Command powershell.exe).Source
$lnk.Arguments = $args_
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.WindowStyle = 7
$lnk.Save()

Write-Host "Test d'envoi..."
& $script -Once

Start-Process powershell.exe -ArgumentList $args_ -WindowStyle Hidden
Write-Host "Installé. L'uploader tourne en arrière-plan et démarrera avec Windows."
Write-Host "Journal : $dataDir\uploader.log"
