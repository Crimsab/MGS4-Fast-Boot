[CmdletBinding()]
param([switch]$SkipBuild)

& (Join-Path $PSScriptRoot 'scripts\package.ps1') -SkipBuild:$SkipBuild
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
