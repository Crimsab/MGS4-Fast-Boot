# MGS4 Fast Boot

Source code for MGS4 Fast Boot 1.0.0.

## Build

Requirements:

- Windows
- Visual Studio 2022 with Desktop development with C++
- CMake 3.24 or newer
- PowerShell 5.1 or newer
- curl

Run:

```powershell
.\build.ps1
```

The script downloads Ultimate ASI Loader v9.7.4 and MinHook v1.3.4 from their
official repositories, verifies both archives by SHA-256, and builds the x64
Release plugin. Output is written to `dist`.

To reproduce the Nexus archive:

```powershell
.\package.ps1
```

The archive is written to `release`. Generated directories are ignored by Git.
