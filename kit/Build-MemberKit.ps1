<#
.SYNOPSIS
  Fabrique le zip d'installation à donner aux membres.
  Le jeton est commun à tous les membres : crée-le dans Supabase avec
    select public.create_upload_token('Membres');
  et révoque-le (update upload_tokens set revoked = true where label = 'Membres';)
  s'il fuit, puis refais un zip avec un nouveau jeton.

.EXAMPLE
  .\kit\Build-MemberKit.ps1 -UploadToken abcd...
#>
param(
  [Parameter(Mandatory)][string]$UploadToken,
  [string]$Out = (Join-Path (Split-Path $PSScriptRoot -Parent) "GuildScribe-Installateur.zip")
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

# URL et clé publique reprises de la config du site.
$cfg = Get-Content (Join-Path $repo "web\config.js") -Raw -Encoding UTF8
$url = [regex]::Match($cfg, 'supabaseUrl:\s*"([^"]+)"').Groups[1].Value
$key = [regex]::Match($cfg, 'anonKey:\s*"([^"]+)"').Groups[1].Value
if (-not $url -or -not $key) { throw "web\config.js doit contenir supabaseUrl et anonKey." }

$stage = Join-Path ([IO.Path]::GetTempPath()) ("gs-kit-" + [guid]::NewGuid().ToString("N"))
$root = Join-Path $stage "GuildScribe-Installateur"
$files = Join-Path $root "fichiers"
New-Item -ItemType Directory -Force (Join-Path $files "uploader") | Out-Null

Copy-Item (Join-Path $PSScriptRoot "Installer GuildScribe.bat"), (Join-Path $PSScriptRoot "Desinstaller GuildScribe.bat"), (Join-Path $PSScriptRoot "LISEZMOI.txt") $root
Copy-Item (Join-Path $PSScriptRoot "Install-Kit.ps1") $files
Copy-Item -Recurse (Join-Path $repo "GuildScribe") $files
Copy-Item (Join-Path $repo "uploader\*.ps1") (Join-Path $files "uploader")
[ordered]@{ supabaseUrl = $url; anonKey = $key; uploadToken = $UploadToken } |
  ConvertTo-Json | Set-Content (Join-Path $files "kit.json") -Encoding UTF8

if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path $root -DestinationPath $Out
Remove-Item -Recurse -Force $stage
Write-Host "Kit prêt : $Out"
