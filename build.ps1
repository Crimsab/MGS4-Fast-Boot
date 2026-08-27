[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$cache = Join-Path $root 'cache'
$build = Join-Path $root 'build'
$dist = Join-Path $root 'dist'
$asiArchive = Join-Path $cache 'Ultimate-ASI-Loader-NoPDB_x64-v9.7.4.zip'
$asiSource = Join-Path $cache 'Ultimate-ASI-Loader-NoPDB_x64-v9.7.4'
$minHookArchive = Join-Path $cache 'minhook-v1.3.4.zip'
$minHookSource = Join-Path $cache 'minhook-v1.3.4\minhook-1.3.4'
$asiArchiveHash = 'E5860E7D9A1805267535B65749575B5E406CC6EA3325C7392189C578815045D1'
$minHookArchiveHash = '172708123DAA0C98D20D3A980B16A50BE14AF243DC95DEE6F79C24193AD010E4'
$userAgent = 'OpenAI File Downloader, XaiImageApiFetch/1.0'

foreach ($command in 'cmake.exe', 'curl.exe') {
    if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command was not found. See README.md for build requirements."
    }
}

New-Item -ItemType Directory -Force -Path $cache, $dist | Out-Null
if (-not (Test-Path -LiteralPath $asiArchive -PathType Leaf)) {
    & curl.exe -L --fail --silent --show-error --user-agent $userAgent --output $asiArchive `
        'https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.4/Ultimate-ASI-Loader-NoPDB_x64.zip'
    if ($LASTEXITCODE -ne 0) { throw 'Ultimate ASI Loader download failed.' }
}
if ((Get-FileHash -LiteralPath $asiArchive -Algorithm SHA256).Hash -ne $asiArchiveHash) {
    throw 'Ultimate ASI Loader archive hash mismatch.'
}
if (-not (Test-Path -LiteralPath (Join-Path $asiSource 'dinput8.dll') -PathType Leaf)) {
    Remove-Item -LiteralPath $asiSource -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive -LiteralPath $asiArchive -DestinationPath $asiSource
}

if (-not (Test-Path -LiteralPath $minHookArchive -PathType Leaf)) {
    & curl.exe -L --fail --silent --show-error --user-agent $userAgent --output $minHookArchive `
        'https://github.com/TsudaKageyu/minhook/archive/refs/tags/v1.3.4.zip'
    if ($LASTEXITCODE -ne 0) { throw 'MinHook download failed.' }
}
if ((Get-FileHash -LiteralPath $minHookArchive -Algorithm SHA256).Hash -ne $minHookArchiveHash) {
    throw 'MinHook archive hash mismatch.'
}
if (-not (Test-Path -LiteralPath (Join-Path $minHookSource 'include\MinHook.h') -PathType Leaf)) {
    $minHookParent = Split-Path $minHookSource -Parent
    Remove-Item -LiteralPath $minHookParent -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $minHookParent | Out-Null
    Expand-Archive -LiteralPath $minHookArchive -DestinationPath $minHookParent
}

& cmake.exe -S $root -B $build -G 'Visual Studio 17 2022' -A x64 "-DMINHOOK_DIR=$minHookSource"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
& cmake.exe --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }

$plugin = Join-Path $dist 'MGS4FastBoot.asi'
$proxy = Join-Path $dist 'version.dll'
$config = Join-Path $dist 'MGS4FastBoot.ini'
Copy-Item -LiteralPath (Join-Path $build 'Release\MGS4FastBoot.asi') -Destination $plugin -Force
Copy-Item -LiteralPath (Join-Path $asiSource 'dinput8.dll') -Destination $proxy -Force
Copy-Item -LiteralPath (Join-Path $root 'MGS4FastBoot.ini') -Destination $config -Force

$manifest = [ordered]@{
    Name = 'MGS4 Fast Boot'
    Version = '1.0.0'
    MinHookVersion = 'v1.3.4'
    MinHookArchiveSha256 = $minHookArchiveHash
    UltimateAsiLoaderVersion = 'v9.7.4'
    UltimateAsiLoaderArchiveSha256 = $asiArchiveHash
    ProxySha256 = (Get-FileHash -LiteralPath $proxy -Algorithm SHA256).Hash
    PluginSha256 = (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash
    ConfigSha256 = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding utf8
$manifest
