# Installs the repo guard rails after a fresh clone.
#   powershell -ExecutionPolicy Bypass -File tools/setup.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

git config core.hooksPath .githooks
git update-index --chmod=+x .githooks/pre-commit 2>$null

Write-Host "core.hooksPath = $(git config core.hooksPath)"
Write-Host "pre-commit guard active (blocks secrets / personal paths / >2MB files)."
Write-Host "Bypass a single commit with: git commit --no-verify"
