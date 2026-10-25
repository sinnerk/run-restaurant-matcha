# Parses every module and the built file with a Lua 5.1 grammar.
#   powershell -ExecutionPolicy Bypass -File check.ps1
# Requires node; luaparse is installed on demand into tools/node if missing.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$pkg = Join-Path $root 'tools\node\node_modules\luaparse'
$nodeDir = Join-Path $root 'tools\node'
if (-not (Test-Path $nodeDir)) { New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null }
if (-not (Test-Path $pkg)) {
  Write-Host 'installing luaparse...'
  Push-Location $nodeDir
  npm install luaparse --silent --no-audit --no-fund | Out-Null
  Pop-Location
}

$targets = @()
$targets += Get-ChildItem -Path (Join-Path $root 'src') -Filter '*.lua' | ForEach-Object { $_.FullName }
if (Test-Path (Join-Path $root 'dist\RunRestaurant.lua')) {
  $targets += (Join-Path $root 'dist\RunRestaurant.lua')
}
if (Test-Path (Join-Path $root 'tools\Recon.lua')) {
  $targets += (Join-Path $root 'tools\Recon.lua')
}

$script = @'
const fs = require('fs');
const lp = require(process.argv[2]);
const files = process.argv.slice(3);
let bad = 0;
for (const f of files) {
  try {
    lp.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1' });
    console.log('ok   ' + f);
  } catch (e) {
    bad++;
    console.log('FAIL ' + f + ' :: ' + e.message);
  }
}
process.exit(bad ? 1 : 0);
'@
$tmp = Join-Path $env:TEMP 'rr-parse.js'
Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8

& node $tmp $pkg @targets
if ($LASTEXITCODE -ne 0) { throw "syntax check failed" }
Write-Host ("checked {0} files" -f $targets.Count)
