[CmdletBinding()]
param([switch]$SkipBuild)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$releaseMetadata = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$version = $releaseMetadata.version
$dist = Join-Path $root 'dist\payload'
$manifestPath = Join-Path $dist 'manifest.json'
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') | Out-Host
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'The compiled payload is missing. Run build.ps1 first.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.Version -ne $version) {
    throw "Payload version $($manifest.Version) does not match release.json version $version."
}

$payloadFiles = [ordered]@{
    'version.dll' = $manifest.ProxySha256
    'MGS4FastBoot.asi' = $manifest.PluginSha256
    'MGS4FastBoot.ini' = $manifest.ConfigSha256
}
foreach ($entry in $payloadFiles.GetEnumerator()) {
    $path = Join-Path $dist $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing release payload: $($entry.Key)"
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "Release payload hash mismatch: $($entry.Key)"
    }
}

$release = Join-Path $root 'release'
$stage = Join-Path ([IO.Path]::GetTempPath()) "mgs4-fast-boot-$version-$([guid]::NewGuid().ToString('N'))"
$bundleName = "MGS4-Fast-Boot-$version"
$bundleRoot = Join-Path $stage $bundleName
$zip = Join-Path $release "MGS4-Fast-Boot-$version.zip"
$externalManifest = Join-Path $release "MGS4-Fast-Boot-$version.manifest.json"
$checksum = Join-Path $release "MGS4-Fast-Boot-$version.sha256"
$files = [ordered]@{
    'Install-Mgs4FastBoot.cmd' = Join-Path $root 'installer\Install-Mgs4FastBoot.cmd'
    'Uninstall-Mgs4FastBoot.cmd' = Join-Path $root 'installer\Uninstall-Mgs4FastBoot.cmd'
    'README.md' = Join-Path $root 'README.md'
    'CHANGELOG.md' = Join-Path $root 'CHANGELOG.md'
    'LICENSE' = Join-Path $root 'LICENSE'
    'THIRD-PARTY-NOTICES.txt' = Join-Path $root 'docs\THIRD-PARTY-NOTICES.txt'
    'mods\FastBoot\Install-Mgs4FastBootLoader.ps1' = Join-Path $root 'installer\Install-Mgs4FastBootLoader.ps1'
    'mods\FastBoot\version.dll' = Join-Path $dist 'version.dll'
    'mods\FastBoot\MGS4FastBoot.asi' = Join-Path $dist 'MGS4FastBoot.asi'
    'mods\FastBoot\MGS4FastBoot.ini' = Join-Path $dist 'MGS4FastBoot.ini'
    'mods\FastBoot\manifest.json' = $manifestPath
}

New-Item -ItemType Directory -Force -Path $release, $bundleRoot | Out-Null
try {
    foreach ($entry in $files.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Missing package input: $($entry.Value)"
        }
        $destination = Join-Path $bundleRoot $entry.Key
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $entry.Value -Destination $destination
    }

    $fileManifest = @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            Path = [IO.Path]::GetRelativePath($bundleRoot, $_.FullName).Replace('\', '/')
            Bytes = $_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
    $releaseManifest = [ordered]@{
        Name = 'MGS4 Fast Boot'
        Version = $version
        SupportedSteamBuildId = $releaseMetadata.supportedSteamBuildId
        Files = $fileManifest
    }
    $manifestJson = $releaseManifest | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $bundleRoot 'FILE-MANIFEST.json'), $manifestJson + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($externalManifest, $manifestJson + "`n", [Text.UTF8Encoding]::new($false))

    Add-Type -AssemblyName System.IO.Compression
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    $output = [IO.File]::Open($zip, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        $fixedTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName) {
            $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
            $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTime
            $input = [IO.File]::OpenRead($file.FullName)
            $entryStream = $entry.Open()
            try { $input.CopyTo($entryStream) }
            finally {
                $entryStream.Dispose()
                $input.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
        $output.Dispose()
    }

    $zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    [IO.File]::WriteAllText($checksum, "$zipHash  $([IO.Path]::GetFileName($zip))`n", [Text.UTF8Encoding]::new($false))
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    Version = $version
    Package = $zip
    Manifest = $externalManifest
    Checksum = $checksum
    Sha256 = $zipHash
}
