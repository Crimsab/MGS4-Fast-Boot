[CmdletBinding()]
param([switch]$SkipBuild)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$releaseMetadata = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$version = $releaseMetadata.version

$scripts = @(
    Get-Item -LiteralPath (Join-Path $root 'build.ps1'), (Join-Path $root 'package.ps1')
    Get-ChildItem -LiteralPath (Join-Path $root 'scripts'), (Join-Path $root 'installer') -Filter '*.ps1' -File
)
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell syntax error in $($script.FullName): $($errors[0].Message)"
    }
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'package.ps1') | Out-Host
    $firstPluginHash = (Get-FileHash -LiteralPath (Join-Path $root 'dist\payload\MGS4FastBoot.asi') -Algorithm SHA256).Hash
    $reproBuild = Join-Path $root 'build-repro'
    $reproDist = Join-Path $root 'dist\repro'
    try {
        & (Join-Path $PSScriptRoot 'build.ps1') -Clean -BuildDirectory $reproBuild -OutputDirectory $reproDist | Out-Host
        $secondPluginHash = (Get-FileHash -LiteralPath (Join-Path $reproDist 'MGS4FastBoot.asi') -Algorithm SHA256).Hash
        if ($firstPluginHash -ne $secondPluginHash) {
            throw "The plugin build is not reproducible: $firstPluginHash != $secondPluginHash"
        }
    }
    finally {
        Remove-Item -LiteralPath $reproBuild, $reproDist -Recurse -Force -ErrorAction SilentlyContinue
    }

    $firstPackageHash = (Get-FileHash -LiteralPath (Join-Path $root "release\MGS4-Fast-Boot-$version.zip") -Algorithm SHA256).Hash
    & (Join-Path $PSScriptRoot 'package.ps1') -SkipBuild | Out-Host
    $secondPackageHash = (Get-FileHash -LiteralPath (Join-Path $root "release\MGS4-Fast-Boot-$version.zip") -Algorithm SHA256).Hash
    if ($firstPackageHash -ne $secondPackageHash) {
        throw "The release archive is not reproducible: $firstPackageHash != $secondPackageHash"
    }
}

$release = Join-Path $root 'release'
$zip = Join-Path $release "MGS4-Fast-Boot-$version.zip"
$manifestPath = Join-Path $release "MGS4-Fast-Boot-$version.manifest.json"
$checksumPath = Join-Path $release "MGS4-Fast-Boot-$version.sha256"
foreach ($path in $zip, $manifestPath, $checksumPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing release artifact: $path"
    }
}

$expectedChecksum = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
$actualChecksum = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
if ($actualChecksum -ne $expectedChecksum) {
    throw 'Release checksum does not match the ZIP.'
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.Version -ne $version -or $manifest.SupportedSteamBuildId -ne $releaseMetadata.supportedSteamBuildId) {
    throw 'Release manifest version or supported Steam build is invalid.'
}

$extract = Join-Path ([IO.Path]::GetTempPath()) "mgs4-fast-boot-verify-$([guid]::NewGuid().ToString('N'))"
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $extract
    $bundle = Join-Path $extract "MGS4-Fast-Boot-$version"
    if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
        throw 'The archive is missing its versioned top-level directory.'
    }
    $expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $manifest.Files) {
        [void]$expectedFiles.Add($file.Path)
        $path = Join-Path $bundle ($file.Path.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Manifest entry is missing from the archive: $($file.Path)"
        }
        if ((Get-Item -LiteralPath $path).Length -ne $file.Bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.Sha256) {
            throw "Manifest verification failed: $($file.Path)"
        }
    }
    [void]$expectedFiles.Add('FILE-MANIFEST.json')
    $actualFiles = @(Get-ChildItem -LiteralPath $bundle -File -Recurse | ForEach-Object {
        [IO.Path]::GetRelativePath($bundle, $_.FullName).Replace('\', '/')
    })
    if ($actualFiles.Count -ne $expectedFiles.Count -or @($actualFiles | Where-Object { -not $expectedFiles.Contains($_) }).Count -ne 0) {
        throw 'The archive contains unlisted files.'
    }

    & (Join-Path $bundle 'mods\FastBoot\Install-Mgs4FastBootLoader.ps1') -Action Validate | Out-Host

    foreach ($relative in 'mods\FastBoot\version.dll', 'mods\FastBoot\MGS4FastBoot.asi') {
        $path = Join-Path $bundle $relative
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -lt 256 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
            throw "$relative is not a PE file."
        }
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550 -or
            [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
            throw "$relative is not an x64 PE file."
        }
    }
}
finally {
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    Valid = $true
    Version = $version
    Package = $zip
    Sha256 = $actualChecksum
    Files = $expectedFiles.Count
}
