# MGS4 Fast Boot

[![CI](https://github.com/Crimsab/MGS4-Fast-Boot/actions/workflows/ci.yml/badge.svg)](https://github.com/Crimsab/MGS4-Fast-Boot/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Crimsab/MGS4-Fast-Boot?label=release)](https://github.com/Crimsab/MGS4-Fast-Boot/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Skip directly to the native main menu while preserving the settings produced by
Konami's official launcher.

MGS4 Fast Boot does not guess or replace region, language, resolution,
controller, profile, or Steam arguments. It follows the official
`directGameStart` path and adds only the verified `--skip-to-main-menu` flag to
the final game request.

## Download

Download the precompiled ZIP, manifest, and checksum from the
[latest GitHub Release](https://github.com/Crimsab/MGS4-Fast-Boot/releases/latest).

The release includes the x64 plugin, pinned Ultimate ASI Loader proxy, default
configuration, installer, uninstaller, licenses, and a per-file SHA-256
manifest. You do not need Visual Studio or CMake to install a release.

## Compatibility

The current release supports only:

- Metal Gear Solid 4: Master Collection Version on Steam
- Steam buildid `24921893`
- `launcher.exe` SHA-256 `DAF16D8A...E35A561`
- `mgs4.exe` SHA-256 `9E8DF67E...9FE459FE41`

Unknown executable hashes are refused safely and continue through the visible
official launcher. Future game updates require a newly tested release.

## Install

1. Close MGS4 and its launcher.
2. Extract the complete release ZIP anywhere outside the game directory.
3. Open the extracted `MGS4-Fast-Boot-<version>` folder.
4. Double-click `Install-Mgs4FastBoot.cmd`.
5. Start the game normally with Steam's **Play** button.

The installer locates registered Steam libraries, verifies the supported game
build and payload hashes, then installs:

```text
METAL GEAR SOLID 4/
└── Launcher/
    ├── version.dll
    ├── MGS4FastBoot.ini
    └── plugins/
        └── MGS4FastBoot.asi
```

It refuses existing conflicting files instead of overwriting them.

## Use And Settings

- Normal Steam launch: use Fast Boot.
- Hold **Shift** while starting the game: show the official launcher once.
- Permanent disable: set `Enabled=0` in `Launcher\MGS4FastBoot.ini`.
- Keep the direct launcher path but disable menu skipping: set
  `SkipToMainMenu=0`.

```ini
[FastBoot]
Enabled=1
SkipToMainMenu=1
```

## Uninstall

Close the game and double-click `Uninstall-Mgs4FastBoot.cmd` from the extracted
release folder. The uninstaller verifies owned binaries before removing them.
A modified INI is preserved as `MGS4FastBoot.ini.user-backup`. If another ASI
plugin still needs the shared loader, `version.dll` is retained and reported.

## Verify A Download

```powershell
Get-FileHash .\MGS4-Fast-Boot-1.0.0.zip -Algorithm SHA256
Get-Content .\MGS4-Fast-Boot-1.0.0.sha256
```

The two SHA-256 values must match. `FILE-MANIFEST.json` inside the ZIP records
the length and hash of every distributed file.

## Build From Source

Developer requirements:

- Windows x64
- Visual Studio 2022 with **Desktop development with C++**
- CMake 3.24 or newer
- PowerShell 7
- curl

```powershell
# Clean x64 Release build. Dependencies are downloaded and hash-verified.
.\build.ps1 -Clean

# Build and create ZIP, external manifest, and checksum under release/.
.\package.ps1

# Parse scripts, build twice, prove reproducibility, package twice, and audit ZIP.
.\scripts\verify.ps1

# Validate only the local compiled payload without touching the game.
.\installer\Install-Mgs4FastBootLoader.ps1 -Action Validate
```

MinHook `v1.3.4` and Ultimate ASI Loader `v9.7.4` are downloaded from their
official repositories. Their archive hashes and URLs are locked in
`release.json`; extracted caches are recreated from verified archives for every
build. Third-party source and binaries remain in ignored generated directories.

## Automated Releases

Every push and pull request builds and verifies a downloadable workflow
artifact. Pushing a tag matching `v<release.json version>` runs the same checks
and creates a GitHub Release automatically with:

- `MGS4-Fast-Boot-<version>.zip`
- `MGS4-Fast-Boot-<version>.manifest.json`
- `MGS4-Fast-Boot-<version>.sha256`

See [Releasing](docs/RELEASING.md) and [Architecture](docs/ARCHITECTURE.md).

## Troubleshooting

- Unsupported build warning: update the game and use a release tested for that
  exact Steam build.
- Deployment conflict: remove or review the reported file manually; the
  installer never replaces an unknown loader or plugin.
- Launcher still visible: check `MGS4FastBoot.ini`, do not hold Shift, and read
  `Launcher\MGS4FastBoot.log`.
- Antivirus warning: ASI loaders and process hooks may trigger heuristic
  detections. Do not disable security software; verify the published checksum or
  build the public source yourself.

## Safety And Scope

- No game executable, archive, save, or settings file is patched.
- No DRM or Steam authentication is bypassed.
- The official launcher remains the owner of user settings.
- Activation is locked to independently verified executable hashes.
- Installation and uninstallation are explicit and hash checked.

Source: [MIT](LICENSE). Third-party components retain their original licenses in
[THIRD-PARTY-NOTICES.txt](docs/THIRD-PARTY-NOTICES.txt).
