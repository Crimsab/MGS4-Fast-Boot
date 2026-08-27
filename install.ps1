[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$GameRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    try {
        $steamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    }
    catch {
        throw 'Steam was not found. Re-run this script with -GameRoot followed by the MGS4 installation path.'
    }

    $libraries = [Collections.Generic.List[string]]::new()
    $libraries.Add([IO.Path]::GetFullPath($steamPath))
    $libraryFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $libraryFile) {
        foreach ($line in Get-Content -LiteralPath $libraryFile) {
            if ($line -match '^\s*"path"\s+"([^"]+)"') {
                $library = $Matches[1] -replace '\\\\', '\'
                if (-not $libraries.Contains($library)) { $libraries.Add($library) }
            }
        }
    }
    foreach ($library in $libraries) {
        $candidate = Join-Path $library 'steamapps\common\METAL GEAR SOLID 4'
        if (Test-Path -LiteralPath (Join-Path $candidate 'MGS4\mgs4.exe') -PathType Leaf) {
            $GameRoot = $candidate
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($GameRoot)) {
        throw 'MGS4 was not found in the registered Steam libraries.'
    }
}
$GameRoot = [IO.Path]::GetFullPath($GameRoot)
if ($null -ne (Get-Process -Name 'mgs4', 'launcher' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw 'Close MGS4 and its launcher before changing the seamless Fast Boot loader.'
}

$launcherRoot = Join-Path $GameRoot 'Launcher'
$pluginsRoot = Join-Path $launcherRoot 'plugins'
$launcherExecutable = Join-Path $launcherRoot 'launcher.exe'
$gameExecutable = Join-Path $GameRoot 'MGS4\mgs4.exe'
$targetProxy = Join-Path $launcherRoot 'version.dll'
$targetPlugin = Join-Path $pluginsRoot 'MGS4FastBoot.asi'
$targetConfig = Join-Path $launcherRoot 'MGS4FastBoot.ini'
$installManifest = Join-Path $launcherRoot 'MGS4FastBoot.install.json'

if ($Action -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $installManifest -PathType Leaf)) {
        throw 'Fast Boot install manifest was not found; refusing an untracked uninstall.'
    }
    $installed = Get-Content -LiteralPath $installManifest -Raw | ConvertFrom-Json

    if (Test-Path -LiteralPath $targetPlugin) {
        $hash = (Get-FileHash -LiteralPath $targetPlugin -Algorithm SHA256).Hash
        if ($hash -ne $installed.PluginSha256) { throw 'Installed Fast Boot plugin was modified; refusing a partial uninstall.' }
    }
    $otherPlugins = @(Get-ChildItem -LiteralPath $pluginsRoot -Filter '*.asi' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $targetPlugin })
    $removeProxy = (Test-Path -LiteralPath $targetProxy) -and $otherPlugins.Count -eq 0
    if ($removeProxy) {
        $hash = (Get-FileHash -LiteralPath $targetProxy -Algorithm SHA256).Hash
        if ($hash -ne $installed.ProxySha256) { throw 'Installed ASI loader proxy was modified; refusing a partial uninstall.' }
    }
    if (Test-Path -LiteralPath $targetConfig) {
        $hash = (Get-FileHash -LiteralPath $targetConfig -Algorithm SHA256).Hash
        $configProperty = $installed.PSObject.Properties['ConfigSha256']
        $expectedConfigHash = if ($null -ne $configProperty) { $configProperty.Value } else { 'CC5A7616158953F9E5624622CE7B6AAC2D8CAA1773734282D510E5CEB6937581' }
        if ($hash -ne $expectedConfigHash) {
            throw 'Fast Boot configuration was modified; restore it or remove the deployment manually.'
        }
    }

    if (Test-Path -LiteralPath $targetPlugin) {
        Remove-Item -LiteralPath $targetPlugin -Force
    }
    if ($removeProxy) {
        Remove-Item -LiteralPath $targetProxy -Force
    }
    Remove-Item -LiteralPath $targetConfig -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $launcherRoot 'MGS4FastBoot.log') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $installManifest -Force
    [pscustomobject]@{ Action = $Action; Installed = $false; LauncherRoot = $launcherRoot }
    return
}

$packagePayload = $PSScriptRoot
$developmentPayload = Join-Path $projectRoot 'dist\fastboot-loader'
$distRoot = if (Test-Path -LiteralPath (Join-Path $packagePayload 'manifest.json') -PathType Leaf) {
    $packagePayload
} else {
    $developmentPayload
}
$distManifest = Join-Path $distRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $distManifest -PathType Leaf)) {
    throw 'The Fast Boot payload is missing or incomplete. Download the release archive again.'
}
$built = Get-Content -LiteralPath $distManifest -Raw | ConvertFrom-Json
$sourceProxy = Join-Path $distRoot 'version.dll'
$sourcePlugin = Join-Path $distRoot 'MGS4FastBoot.asi'
$sourceConfig = Join-Path $distRoot 'MGS4FastBoot.ini'
if ((Get-FileHash -LiteralPath $sourceProxy -Algorithm SHA256).Hash -ne $built.ProxySha256 -or
    (Get-FileHash -LiteralPath $sourcePlugin -Algorithm SHA256).Hash -ne $built.PluginSha256 -or
    (Get-FileHash -LiteralPath $sourceConfig -Algorithm SHA256).Hash -ne $built.ConfigSha256) {
    throw 'Fast Boot distribution hash verification failed.'
}

$expectedLauncherHash = 'DAF16D8A6C2A4E0E4480D08D865EB9F6A445A05CF1F238EB2D4391048E35A561'
$expectedGameHash = '9E8DF67EA7F41E7F8306CE1A77584707209069B3C75389B3F00445EFE459FE41'
if (-not (Test-Path -LiteralPath $launcherExecutable -PathType Leaf) -or
    (Get-FileHash -LiteralPath $launcherExecutable -Algorithm SHA256).Hash -ne $expectedLauncherHash) {
    throw 'The official launcher is missing or does not match the verified build.'
}
if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf) -or
    (Get-FileHash -LiteralPath $gameExecutable -Algorithm SHA256).Hash -ne $expectedGameHash) {
    throw 'mgs4.exe is missing or does not match the verified build.'
}

foreach ($target in @($targetProxy, $targetPlugin, $targetConfig, $installManifest)) {
    if (Test-Path -LiteralPath $target) {
        throw "Deployment conflict: $target already exists."
    }
}

New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null
$copied = [Collections.Generic.List[string]]::new()
try {
    Copy-Item -LiteralPath $sourceProxy -Destination $targetProxy -ErrorAction Stop
    $copied.Add($targetProxy)
    Copy-Item -LiteralPath $sourcePlugin -Destination $targetPlugin -ErrorAction Stop
    $copied.Add($targetPlugin)
    Copy-Item -LiteralPath $sourceConfig -Destination $targetConfig -ErrorAction Stop
    $copied.Add($targetConfig)

    [ordered]@{
        Version = $built.Version
        ProxySha256 = $built.ProxySha256
        PluginSha256 = $built.PluginSha256
        ConfigSha256 = $built.ConfigSha256
        InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $installManifest -Encoding utf8
}
catch {
    foreach ($path in $copied) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    throw
}

[pscustomobject]@{
    Action = $Action
    Installed = $true
    LauncherRoot = $launcherRoot
    ProxySha256 = $built.ProxySha256
    PluginSha256 = $built.PluginSha256
    ShiftBypass = $true
}
