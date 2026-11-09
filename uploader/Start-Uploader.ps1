<#
.SYNOPSIS
  Uploader GuildScribe : surveille GuildScribe.lua et envoie les données au site
  à chaque fois que WoW l'écrit (déconnexion, /reload).

  Lancé automatiquement au démarrage de Windows par Install-Uploader.ps1.
  -Once : un seul envoi puis arrêt (pratique pour tester).
#>
param(
  [switch]$Once,
  [int]$IntervalSeconds = 20
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GuildScribe.Parser.ps1")

$dataDir = Join-Path $env:APPDATA "GuildScribe"
$configPath = Join-Path $dataDir "config.json"
$statePath = Join-Path $dataDir "state.json"
$logPath = Join-Path $dataDir "uploader.log"
New-Item -ItemType Directory -Force $dataDir | Out-Null

function Write-Log($msg) {
  $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
  Add-Content -Path $logPath -Value $line -Encoding UTF8
  Write-Host $line
  # Garde un log de taille raisonnable.
  if ((Get-Item $logPath).Length -gt 512KB) {
    Get-Content $logPath -Tail 500 -Encoding UTF8 | Set-Content $logPath -Encoding UTF8
  }
}

if (-not (Test-Path $configPath)) { throw "Config absente : lance d'abord Install-Uploader.ps1" }
$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$state = @{}
if (Test-Path $statePath) {
  (Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
}

function Send-File($file) {
  $db = (ConvertFrom-GuildScribeLua -Path $file.FullName)["GuildScribeDB"]
  if (-not $db) { Write-Log "Rien dans $($file.FullName)"; return }

  $body = [ordered]@{ p_token = $config.uploadToken; p_payload = $db }
  $bytes = $script:GsUtf8.GetBytes((ConvertTo-GsJson $body))
  $headers = @{ apikey = $config.anonKey }
  # Anciennes clés (JWT "eyJ...") : aussi en Bearer. Nouvelles clés sb_publishable_ : apikey seul.
  if ($config.anonKey -like "eyJ*") { $headers.Authorization = "Bearer $($config.anonKey)" }
  $url = $config.supabaseUrl.TrimEnd('/') + "/rest/v1/rpc/ingest_guild"

  $res = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bytes
  Write-Log ("Envoyé {0} : {1} guilde(s), {2} membre(s)" -f $file.Directory.Parent.Name, $res.guilds, $res.members)
}

Write-Log "Uploader démarré."
while ($true) {
  foreach ($file in @(Find-GuildScribeFiles -WowDir $config.wowDir)) {
    $key = $file.FullName
    $stamp = $file.LastWriteTimeUtc.Ticks
    if ($state[$key] -eq $stamp) { continue }
    # Attend que WoW ait fini d'écrire.
    if (((Get-Date).ToUniversalTime() - $file.LastWriteTimeUtc).TotalSeconds -lt 3) { continue }
    try {
      Send-File $file
      $state[$key] = $stamp
      $state | ConvertTo-Json | Set-Content $statePath -Encoding UTF8
    } catch {
      Write-Log "Erreur d'envoi : $($_.Exception.Message)"
    }
  }
  if ($Once) { break }
  Start-Sleep -Seconds $IntervalSeconds
}
