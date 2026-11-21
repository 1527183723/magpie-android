<#
.SYNOPSIS
  Windows entry point. The gateway build itself is scripts/build-magpie-android.sh,
  which also runs in Git Bash/WSL and in GitHub Actions.
#>
$ErrorActionPreference = "Stop"
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) { throw "bash not found; install Git for Windows or use WSL" }
& $bash.Source (Join-Path $PSScriptRoot "build-magpie-android.sh") @args
exit $LASTEXITCODE
