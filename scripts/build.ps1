[CmdletBinding()]
param(
    [switch]$Clean,
    [string]$BuildDirectory,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$releaseMetadata = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$version = $releaseMetadata.version
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "release.json must contain a semantic version such as 1.0.0; found $version."
}

$cache = Join-Path $root 'cache'
$build = if ([string]::IsNullOrWhiteSpace($BuildDirectory)) { Join-Path $root 'build' } else { [IO.Path]::GetFullPath($BuildDirectory) }
$dist = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { Join-Path $root 'dist\payload' } else { [IO.Path]::GetFullPath($OutputDirectory) }
$asiArchive = Join-Path $cache 'Ultimate-ASI-Loader-NoPDB_x64-v9.7.4.zip'
$asiSource = Join-Path $cache 'Ultimate-ASI-Loader-NoPDB_x64-v9.7.4'
$minHookArchive = Join-Path $cache 'minhook-v1.3.4.zip'
$minHookParent = Join-Path $cache 'minhook-v1.3.4'
$minHookSource = Join-Path $minHookParent 'minhook-1.3.4'
$asiArchiveHash = $releaseMetadata.ultimateAsiLoader.archiveSha256
$minHookArchiveHash = $releaseMetadata.minHook.archiveSha256
$userAgent = 'OpenAI File Downloader, XaiImageApiFetch/1.0'

foreach ($command in 'cmake.exe', 'curl.exe') {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command was not found. See README.md for build requirements."
    }
}

if ($Clean) {
    Remove-Item -LiteralPath $build, $dist -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $cache, $dist | Out-Null

if ((-not (Test-Path -LiteralPath $asiArchive -PathType Leaf)) -or
    (Get-FileHash -LiteralPath $asiArchive -Algorithm SHA256).Hash -ne $asiArchiveHash) {
    $download = "$asiArchive.$([guid]::NewGuid().ToString('N')).download"
    try {
        & curl.exe -L --fail --silent --show-error --user-agent $userAgent --output $download $releaseMetadata.ultimateAsiLoader.url
        if ($LASTEXITCODE -ne 0) { throw 'Ultimate ASI Loader download failed.' }
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $asiArchiveHash) {
            throw 'Ultimate ASI Loader archive hash mismatch.'
        }
        Move-Item -LiteralPath $download -Destination $asiArchive -Force
    }
    finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}
if ((Get-FileHash -LiteralPath $asiArchive -Algorithm SHA256).Hash -ne $asiArchiveHash) {
    throw 'Ultimate ASI Loader archive hash mismatch.'
}
Remove-Item -LiteralPath $asiSource -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $asiArchive -DestinationPath $asiSource

if ((-not (Test-Path -LiteralPath $minHookArchive -PathType Leaf)) -or
    (Get-FileHash -LiteralPath $minHookArchive -Algorithm SHA256).Hash -ne $minHookArchiveHash) {
    $download = "$minHookArchive.$([guid]::NewGuid().ToString('N')).download"
    try {
        & curl.exe -L --fail --silent --show-error --user-agent $userAgent --output $download $releaseMetadata.minHook.url
        if ($LASTEXITCODE -ne 0) { throw 'MinHook download failed.' }
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $minHookArchiveHash) {
            throw 'MinHook archive hash mismatch.'
        }
        Move-Item -LiteralPath $download -Destination $minHookArchive -Force
    }
    finally { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
}
if ((Get-FileHash -LiteralPath $minHookArchive -Algorithm SHA256).Hash -ne $minHookArchiveHash) {
    throw 'MinHook archive hash mismatch.'
}
Remove-Item -LiteralPath $minHookParent -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $minHookParent | Out-Null
Expand-Archive -LiteralPath $minHookArchive -DestinationPath $minHookParent

& cmake.exe -S $root -B $build -G 'Visual Studio 17 2022' -A x64 "-DMINHOOK_DIR=$minHookSource"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
& cmake.exe --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }

$plugin = Join-Path $dist 'MGS4FastBoot.asi'
$proxy = Join-Path $dist 'version.dll'
$config = Join-Path $dist 'MGS4FastBoot.ini'
Copy-Item -LiteralPath (Join-Path $build 'Release\MGS4FastBoot.asi') -Destination $plugin -Force
Copy-Item -LiteralPath (Join-Path $asiSource 'dinput8.dll') -Destination $proxy -Force
Copy-Item -LiteralPath (Join-Path $root 'assets\MGS4FastBoot.ini') -Destination $config -Force

$manifest = [ordered]@{
    Name = 'MGS4 Fast Boot'
    Version = $version
    SupportedSteamBuildId = $releaseMetadata.supportedSteamBuildId
    ExpectedLauncherSha256 = $releaseMetadata.launcherSha256
    ExpectedGameSha256 = $releaseMetadata.gameSha256
    MinHookVersion = $releaseMetadata.minHook.version
    MinHookArchiveSha256 = $minHookArchiveHash
    UltimateAsiLoaderVersion = $releaseMetadata.ultimateAsiLoader.version
    UltimateAsiLoaderArchiveSha256 = $asiArchiveHash
    ProxySha256 = (Get-FileHash -LiteralPath $proxy -Algorithm SHA256).Hash
    PluginSha256 = (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash
    ConfigSha256 = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
}
$manifestJson = $manifest | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $dist 'manifest.json'), $manifestJson + "`n", [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Version = $version
    Payload = $dist
    ProxySha256 = $manifest.ProxySha256
    PluginSha256 = $manifest.PluginSha256
    ConfigSha256 = $manifest.ConfigSha256
}
