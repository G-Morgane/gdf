# Lecture du fichier SavedVariables de WoW (tables Lua) -> objets PowerShell.
# Utilisé par Export-GuildScribe.ps1 et Start-Uploader.ps1.

$script:GsLatin1 = [System.Text.Encoding]::GetEncoding(28591)
$script:GsUtf8 = New-Object System.Text.UTF8Encoding($false)

function Find-GuildScribeFiles {
  param([string]$WowDir)
  $dirs = @()
  if ($WowDir) { $dirs += $WowDir }
  foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, "C:\", "D:\", "E:\")) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    $wow = [IO.Path]::Combine($root, "World of Warcraft")
    if (Test-Path $wow) {
      $dirs += Get-ChildItem $wow -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object FullName
    }
  }
  foreach ($d in ($dirs | Select-Object -Unique)) {
    Get-ChildItem (Join-Path $d "WTF\Account\*\SavedVariables\GuildScribe.lua") -ErrorAction SilentlyContinue
  }
}

function ConvertFrom-GuildScribeLua {
  param([Parameter(Mandatory)][string]$Path)

  $script:src = [System.IO.File]::ReadAllText((Resolve-Path $Path), $script:GsLatin1)
  $script:pos = 0

  $root = [ordered]@{}
  while ($true) {
    Skip-GsWs
    if ($script:pos -ge $script:src.Length) { break }
    $m = [regex]::Match((Get-GsAhead 128), '^([A-Za-z_]\w*)\s*=')
    if (-not $m.Success) { throw "Variable attendue à la position $($script:pos)" }
    $script:pos += $m.Length
    $root[$m.Groups[1].Value] = Read-GsValue
  }
  return $root
}

function Get-GsAhead([int]$n) {
  $script:src.Substring($script:pos, [Math]::Min($n, $script:src.Length - $script:pos))
}

function Skip-GsWs {
  $src = $script:src
  while ($script:pos -lt $src.Length) {
    $c = $src[$script:pos]
    if ([char]::IsWhiteSpace($c)) { $script:pos++; continue }
    if ($c -eq '-' -and $script:pos + 1 -lt $src.Length -and $src[$script:pos + 1] -eq '-') {
      $nl = $src.IndexOf("`n", $script:pos)
      $script:pos = if ($nl -lt 0) { $src.Length } else { $nl + 1 }
      continue
    }
    break
  }
}

function Expect-Gs([char]$ch) {
  Skip-GsWs
  if ($script:src[$script:pos] -ne $ch) { throw "Attendu '$ch' à la position $($script:pos)" }
  $script:pos++
}

function Read-GsString {
  $src = $script:src
  $quote = $src[$script:pos]; $script:pos++
  $sb = New-Object System.Text.StringBuilder
  while ($src[$script:pos] -ne $quote) {
    $c = $src[$script:pos]
    if ($c -eq '\') {
      $script:pos++
      $n = $src[$script:pos]
      if ([char]::IsDigit($n)) {
        $digits = ""
        while ($digits.Length -lt 3 -and [char]::IsDigit($src[$script:pos])) { $digits += $src[$script:pos]; $script:pos++ }
        [void]$sb.Append([char][int]$digits)
        continue
      }
      switch -CaseSensitive ($n) {
        'n' { [void]$sb.Append("`n") } 't' { [void]$sb.Append("`t") } 'r' { [void]$sb.Append("`r") }
        default { [void]$sb.Append($n) }
      }
      $script:pos++
    } else {
      [void]$sb.Append($c); $script:pos++
    }
  }
  $script:pos++
  # Octets lus en latin-1 -> redécodés en UTF-8.
  return $script:GsUtf8.GetString($script:GsLatin1.GetBytes($sb.ToString()))
}

function Read-GsValue {
  Skip-GsWs
  $c = $script:src[$script:pos]
  if ($c -eq '{') { return ,(Read-GsTable) }
  if ($c -eq '"' -or $c -eq "'") { return Read-GsString }
  $m = [regex]::Match((Get-GsAhead 64), '^(-?\d+\.?\d*(?:[eE][-+]?\d+)?|true|false|nil)')
  if (-not $m.Success) { throw "Valeur inattendue à la position $($script:pos)" }
  $script:pos += $m.Length
  switch ($m.Value) {
    'true' { return $true } 'false' { return $false } 'nil' { return $null }
    default {
      if ($m.Value -match '^-?\d+$') { return [long]$m.Value }
      return [double]::Parse($m.Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
  }
}

function Read-GsTable {
  Expect-Gs '{'
  $d = [ordered]@{}
  $n = 1
  $allInt = $true
  while ($true) {
    Skip-GsWs
    if ($script:src[$script:pos] -eq '}') { $script:pos++; break }
    if ($script:src[$script:pos] -eq '[') {
      $script:pos++
      $k = Read-GsValue
      Expect-Gs ']'; Expect-Gs '='
      $d["$k"] = Read-GsValue
      if (-not ($k -is [long])) { $allInt = $false }
    } else {
      $m = [regex]::Match((Get-GsAhead 128), '^([A-Za-z_]\w*)\s*=(?!=)')
      if ($m.Success) {
        $script:pos += $m.Length
        $d[$m.Groups[1].Value] = Read-GsValue
        $allInt = $false
      } else {
        $d["$n"] = Read-GsValue
        $n++
      }
    }
    Skip-GsWs
    if ($script:src[$script:pos] -eq ',' -or $script:src[$script:pos] -eq ';') { $script:pos++ }
  }
  # Table 1..n sans trou -> tableau JSON.
  if ($d.Count -gt 0 -and $allInt) {
    $isSeq = $true
    for ($i = 1; $i -le $d.Count; $i++) { if (-not $d.Contains("$i")) { $isSeq = $false; break } }
    if ($isSeq) {
      $arr = New-Object System.Collections.ArrayList
      for ($i = 1; $i -le $d.Count; $i++) { [void]$arr.Add($d["$i"]) }
      return ,$arr
    }
  }
  return $d
}

function ConvertTo-GsJson($data) {
  ConvertTo-Json -InputObject $data -Depth 30 -Compress
}
