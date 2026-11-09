<#
.SYNOPSIS
  Compile GuildScribe.exe et fabrique le zip d'installation à donner aux membres.
  Le jeton est commun à tous les membres : crée-le dans Supabase avec
    select public.create_upload_token('Membres');
  et révoque-le (update upload_tokens set revoked = true where label = 'Membres';)
  s'il fuit, puis refais un zip avec un nouveau jeton.
  Un officier qui installe ce kit garde son jeton personnel s'il en a déjà un.

.EXAMPLE
  .\kit\Build-MemberKit.ps1 -UploadToken abcd... -SiteUrl https://gdf-ashy.vercel.app
#>
param(
  [Parameter(Mandatory)][string]$UploadToken,
  [string]$SiteUrl = "https://gdf-ashy.vercel.app",
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
New-Item -ItemType Directory -Force $root | Out-Null

# Compilation avec le compilateur C# fourni avec Windows (.NET Framework 4).
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
& $csc /nologo /codepage:65001 /target:winexe /optimize+ "/out:$root\GuildScribe.exe" `
  /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll (Join-Path $repo "uploader\GuildScribe.cs")
if ($LASTEXITCODE -ne 0) { throw "Compilation de GuildScribe.exe impossible." }

Copy-Item -Recurse (Join-Path $repo "GuildScribe") $root
Copy-Item (Join-Path $PSScriptRoot "LISEZMOI.txt") $root
[ordered]@{ supabaseUrl = $url; anonKey = $key; uploadToken = $UploadToken; siteUrl = $SiteUrl } |
  ConvertTo-Json | Set-Content (Join-Path $root "kit.json") -Encoding UTF8

if (Test-Path $Out) { Remove-Item $Out -Force }
Compress-Archive -Path $root -DestinationPath $Out
Remove-Item -Recurse -Force $stage
Write-Host "Kit prêt : $Out"
