# Contributing to Mac Wine Launcher

Thanks for helping improve Mac Wine Launcher. Contributions are accepted through reviewed
pull requests; nobody should push feature work directly to `main`.

## Before you start

1. Search existing issues and pull requests.
2. Open a feature request before starting a large or user-visible change.
3. Report security problems privately using the process in [SECURITY.md](SECURITY.md).
4. Do not submit DRM bypasses, ownership spoofing, credential collection, kernel-driver
   workarounds, or bundled proprietary runtimes without redistribution permission.

## Development workflow

1. Fork this repository.
2. Create a focused branch from the latest `main`.
3. Make the smallest coherent change.
4. Run `swift test` and `./scripts/package-app.sh` on macOS.
5. Update tests and documentation when behavior changes.
6. Open a pull request using the repository template.

Pull requests must pass CI and owner review. A pull request is only a proposal: it does
not alter the original project until an authorized maintainer explicitly merges it.
Force-pushes and branch deletion are disabled on `main`.

## Code expectations

- Preserve user data and validate destructive paths.
- Keep downloads HTTPS-only, version-pinned, and SHA-256 verified.
- Avoid shell interpolation for user-provided arguments.
- Scope Wine process cleanup to the selected managed bottle and runtime.
- Add regression tests for bug fixes.
- Keep game-specific workarounds executable-scoped and grouped under Known Game Fixes.

By contributing, you agree that your contribution is licensed under the MIT License.
