# Builds dist/RunRestaurant.lua from src/*.lua in filename order.
#   powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$order = @(
  '00_boot.lua'
  '10_caps.lua'
  '12_keymap.lua'
  '15_input.lua'
  '20_move.lua'
  '25_world.lua'
  '30_act.lua'
  '35_jobs.lua'
  '40_ui.lua'
  '50_jobs_world.lua'
  '60_main.lua'
)

$out = New-Object System.Collections.Generic.List[string]
$out.Add('-- Run a Restaurant! - Matcha toolkit')
$out.Add('-- built ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
$out.Add('-- paste this whole file into Matcha and execute')
$out.Add('')

$total = 0
foreach ($name in $order) {
  $path = Join-Path $root (Join-Path 'src' $name)
  if (-not (Test-Path $path)) { throw "missing module: $name" }
  $text = Get-Content -LiteralPath $path -Raw
  $total += $text.Length
  $out.Add('')
  $out.Add('-- ======================================================================')
  $out.Add("-- $name")
  $out.Add('-- ======================================================================')
  $out.Add($text.TrimEnd())
}

$dist = Join-Path $root 'dist'
if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
$target = Join-Path $dist 'RunRestaurant.lua'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, ($out -join "`n"), $utf8)

$size = (Get-Item $target).Length
Write-Host ("built {0} ({1:N0} bytes from {2:N0} chars across {3} modules)" -f $target, $size, $total, $order.Count)
