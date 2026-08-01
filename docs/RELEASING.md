# Release checklist

1. Update `CFBundleShortVersionString`, `CFBundleVersion`, and `CHANGELOG.md`.
2. Run `swift test`.
3. Run `./scripts/package-dmg.sh`.
4. Verify `codesign --verify --deep --strict "dist/Mac Wine Launcher.app"`.
5. Test installation, Steam launch, Stop Steam & Wine, and Command-Q cleanup.
6. Commit through a pull request and wait for required CI and owner review.
7. Merge without bypassing branch protection.
8. Tag the merge commit as `vX.Y.Z`.
9. Publish the DMG and universal ZIP on GitHub Releases with SHA-256 checksums.

The repository's community artifacts are ad-hoc signed. Developer ID signing and Apple
notarization require maintainer credentials and must never be stored in the repository.
