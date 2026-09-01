[CmdletBinding()]
param([switch]$Clean)

& (Join-Path $PSScriptRoot 'scripts\build.ps1') -Clean:$Clean
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
