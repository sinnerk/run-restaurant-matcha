# Scans the FULL git history of this repo for secrets / personal data.
# Run before making the repo public, or any time you are unsure.
#   powershell -ExecutionPolicy Bypass -File tools/scan-history.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$patterns = [ordered]@{
    'absolute Windows user path' = '[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9._-]+'
    'Roblox session cookie'      = 'ROBLOSECURITY'
    'Discord webhook'            = 'discord(app)?\.com/api/webhooks'
    'API token'                  = 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{24,}|xox[baprs]-|AKIA[0-9A-Z]{16}'
    'private key'                = 'BEGIN [A-Z ]*PRIVATE KEY'
    'email address'              = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
}

$history = git log -p --all --no-color 2>$null
$found = $false

foreach ($name in $patterns.Keys) {
    $rx = $patterns[$name]
    $hits = $history | Select-String -Pattern $rx -CaseSensitive:$false |
            Where-Object { $_.Line -notmatch 'users\.noreply\.github\.com|example\.(com|org|net)' } |
            Select-Object -First 20
    if ($hits) {
        $found = $true
        Write-Host "`n[$name]" -ForegroundColor Red
        $hits | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) }
    }
}

if ($found) {
    Write-Host "`nFindings above. Either scrub history (git filter-repo) or keep the repo private." -ForegroundColor Yellow
    exit 1
}

Write-Host "Clean: no secrets or personal data in history." -ForegroundColor Green
exit 0
