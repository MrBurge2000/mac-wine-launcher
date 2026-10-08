# Release checklist

1. Update `CFBundleShortVersionString`, `CFBundleVersion`, and `CHANGELOG.md`.
2. Run `swift test`.
3. Run `./scripts/package-dmg.sh`.
4. Verify `codesign --verify --deep --strict "dist/Mac Wine Launcher.app"`.
5. Test installation, Steam launch, Stop Steam & Wine, and Command-Q cleanup.
6. Commit on a development branch and run CI through a pull request. Do not approve
   or merge your own changes, and do not bypass branch protection.
7. Obtain the owner's explicit release approval. A release request is not approval
   to merge: when releasing the tested development branch, tag its exact tested
   commit as `vX.Y.Z` and leave main unchanged. Merge only with separate approval.
8. Publish the DMG and universal ZIP on GitHub Releases with SHA-256 checksums.
9. Download the published packages, compare their hashes, and verify the version,
   architectures, signature, and drag-to-Applications layout before announcing.

The repository's community artifacts are ad-hoc signed. Developer ID signing and Apple
notarization require maintainer credentials and must never be stored in the repository.
