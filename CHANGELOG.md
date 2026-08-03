# Changelog

All notable changes to Mac Wine Launcher are recorded here.

## [Unreleased]

## [0.6.2] - 2026-08-04

- Added an automatic software-rendering fallback for Qt launchers that cannot create
  an OpenGL context inside Wine.
- Added a dedicated Cyberpunk 2077 launch path that safely asks Steam to start the
  game with REDlauncher skipped, while leaving Steam and other Wine apps running.
- Added process-level startup verification and coverage for the new compatibility fix.

## [0.6.1] - 2026-08-02

- Completed a full product-identity audit across source, runtime metadata, packaging,
  installer artwork, documentation, website copy, and public release assets.
- Introduced a completely original portal-and-apps icon across the app and website.
- Rebuilt the drag-to-Applications installer artwork with Mac Wine Launcher branding.
- Removed obsolete compatibility identifiers so new builds and managed data use only
  Mac Wine Launcher names.

## [0.6.0] - 2026-08-02

- Initial public release of Mac Wine Launcher.
- Added managed Wine bottles, Windows application launching, Windows Steam installation,
  DirectX renderer selection, Retina profiles, known-game fixes, and battery-safe shutdown.

[Unreleased]: https://github.com/MrBurge2000/mac-wine-launcher/compare/v0.6.2...HEAD
[0.6.2]: https://github.com/MrBurge2000/mac-wine-launcher/releases/tag/v0.6.2
[0.6.1]: https://github.com/MrBurge2000/mac-wine-launcher/releases/tag/v0.6.1
