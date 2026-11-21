<#
.SYNOPSIS
  Windows entry point. The Android build itself is scripts/build-apk.sh,
  which also runs in Git Bash/WSL and in GitHub Actions.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { throw "bash not found; install Git for Windows or use WSL" }
& $bash.Source (Join-Path $PSScriptRoot "build-apk.sh") @args
exit $LASTEXITCODE
