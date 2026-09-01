# Releasing

GitHub Releases are generated only from version tags.

1. Update `version` in `release.json`.
2. Add the version section to `CHANGELOG.md`.
3. Run `./scripts/verify.ps1` from PowerShell 7 on Windows.
4. Commit and push the reviewed source.
5. Create and push an annotated `v<version>` tag.

```powershell
git tag -a v1.0.0 -m "MGS4 Fast Boot 1.0.0"
git push origin main
git push origin v1.0.0
```

`.github/workflows/release.yml` rejects a tag that does not match
`release.json`, rebuilds twice, verifies reproducibility, creates a deterministic
ZIP, validates every manifest hash and x64 PE payload, and publishes the ZIP,
manifest, and SHA-256 file with the GitHub Release.

The workflow does not publish to Nexus Mods and does not use a Nexus API key.
