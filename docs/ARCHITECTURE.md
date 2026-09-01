# Architecture

MGS4 Fast Boot is a build-locked launcher plugin, not a replacement launcher.

1. Steam starts Konami's official Unity launcher.
2. Ultimate ASI Loader loads `MGS4FastBoot.asi` into that launcher.
3. On a normal launch, the plugin restarts the official launcher through its
   hidden `-jump directGameStart` route.
4. The launcher remains responsible for saved region, language, display,
   controller, profile, and Steam settings.
5. The plugin intercepts only the final verified `mgs4.exe` process request and
   appends `--skip-to-main-menu` if it is absent.

Both the launcher and game executable must match the SHA-256 values in
`release.json`. Unknown builds fall back to the visible official launcher.

## Repository Layout

- `src/`: authored C++ plugin source.
- `assets/`: default user-editable configuration.
- `installer/`: hash-checking install, validation, and uninstall scripts.
- `scripts/`: dependency acquisition, compilation, packaging, and verification.
- `cmake/`: generated release configuration template.
- `docs/`: architecture and third-party notices.
- `release.json`: single source of release version, compatibility, dependency,
  and executable hashes.

Generated `build/`, `cache/`, `dist/`, and `release/` directories are ignored.
No game executable or proprietary game asset belongs in this repository.
