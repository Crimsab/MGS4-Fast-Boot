[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$manifestPath = Join-Path $dist 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    & (Join-Path $root 'build.ps1') | Out-Host
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$release = Join-Path $root 'release'
$stage = Join-Path ([IO.Path]::GetTempPath()) "mgs4-fast-boot-$([guid]::NewGuid().ToString('N'))"
$zip = Join-Path $release "MGS4-Fast-Boot-$($manifest.Version).zip"

$files = [ordered]@{
    'Install-Mgs4FastBoot.cmd' = Join-Path $root 'Install-Mgs4FastBoot.cmd'
    'Uninstall-Mgs4FastBoot.cmd' = Join-Path $root 'Uninstall-Mgs4FastBoot.cmd'
    'THIRD-PARTY-NOTICES.txt' = Join-Path $root 'THIRD-PARTY-NOTICES.txt'
    'mods\FastBoot\Install-Mgs4FastBootLoader.ps1' = Join-Path $root 'install.ps1'
    'mods\FastBoot\version.dll' = Join-Path $dist 'version.dll'
    'mods\FastBoot\MGS4FastBoot.asi' = Join-Path $dist 'MGS4FastBoot.asi'
    'mods\FastBoot\MGS4FastBoot.ini' = Join-Path $dist 'MGS4FastBoot.ini'
    'mods\FastBoot\manifest.json' = $manifestPath
}

New-Item -ItemType Directory -Force -Path $release, $stage | Out-Null
try {
    foreach ($entry in $files.GetEnumerator()) {
        $destination = Join-Path $stage $entry.Key
        New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
        Copy-Item -LiteralPath $entry.Value -Destination $destination
    }
    $fileManifest = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            Path = [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
            Bytes = $_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
    [ordered]@{
        Name = 'MGS4 Fast Boot'
        Version = $manifest.Version
        SupportedSteamBuildId = '24921893'
        Files = $fileManifest
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'FILE-MANIFEST.json') -Encoding utf8
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal -Force
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    Package = $zip
    Sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
}
