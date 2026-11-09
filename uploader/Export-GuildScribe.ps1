<#
.SYNOPSIS
  Convertit GuildScribe.lua en JSON (sans rien envoyer). Pratique pour vérifier.

.EXAMPLE
  .\Export-GuildScribe.ps1 -Out guild.json
  .\Export-GuildScribe.ps1 -Path "C:\...\SavedVariables\GuildScribe.lua" -Out guild.json
#>
param(
  [string]$Path,
  [string]$WowDir,
  [string]$Out = "guild.json"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GuildScribe.Parser.ps1")

if (-not $Path) {
  $f = @(Find-GuildScribeFiles -WowDir $WowDir) | Select-Object -First 1
  if (-not $f) { throw "GuildScribe.lua introuvable. Utilise -Path ou -WowDir." }
  $Path = $f.FullName
}

$data = (ConvertFrom-GuildScribeLua -Path $Path)["GuildScribeDB"]
if (-not $data) { throw "GuildScribeDB absent du fichier." }

$json = ConvertTo-Json -InputObject $data -Depth 30
$outPath = if ([IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
[System.IO.File]::WriteAllText($outPath, $json, $script:GsUtf8)

foreach ($key in $data["guilds"].Keys) {
  $members = @($data["guilds"][$key]["members"].Values | Where-Object { $_["inGuild"] })
  $detailed = @($members | Where-Object { $_["profile"] -and $_["profile"]["level"] })
  Write-Host "$key : $($members.Count) membres, $($detailed.Count) fiches détaillées"
}
Write-Host "-> $outPath"
