# Changelog

All notable changes to Mac Wine Launcher are recorded here.

## [Unreleased]

## [0.6.6] - 2026-09-11

- Automatically applies Baldur’s Gate 3’s official `--skip-launcher` option
  when the game is installed, avoiding common Larian Launcher black-window and
  startup failures under Wine while preserving existing launch options.
- Expanded Known Game Bugs & Fixes so every active automatic fix, including
  Marvel Rivals, is counted and explained in one troubleshooting section.
- Kept destructive anti-cheat bypasses, executable renames, global virtual
  desktops, and forced low-quality renderer settings out of the automatic pass.

## [0.6.5] - 2026-09-11

- Opted the launcher into macOS Game Mode so supported systems can reduce
  background activity and prioritize smoother, more consistent gameplay.
- Disabled DXVK, DXMT, and vkd3d-proton diagnostic logging during normal game
  sessions to avoid unnecessary CPU and disk work.
- Kept renderer selection, image quality, overlays, and persistent shader caches
  unchanged so the performance pass does not trade away visual quality or
  compatibility.

## [0.6.4] - 2026-09-10

- Automatically disables Marvel Rivals' false Unreal Engine AMD/D3D12 driver
  warning inside Wine without changing the selected renderer or other games.
- Preserves existing per-user Unreal Engine settings and reapplies the scoped
  compatibility setting safely whenever Steam starts.

## [0.6.3] - 2026-08-04

- Made the Cyberpunk 2077 REDlauncher bypass automatic for the normal Steam Play
  button while preserving any launch options already configured by the player.
- Kept the dedicated manual launch button as a fallback and made the Steam settings
  repair repeatable without adding duplicate options.

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

[Unreleased]: https://github.com/MrBurge2000/mac-wine-launcher/compare/v0.6.6...HEAD
[0.6.6]: https://github.com/MrBurge2000/mac-wine-launcher/compare/v0.6.5...v0.6.6
[0.6.5]: https://github.com/MrBurge2000/mac-wine-launcher/compare/v0.6.4...v0.6.5
[0.6.4]: https://github.com/MrBurge2000/mac-wine-launcher/compare/v0.6.3...v0.6.4
[0.6.3]: https://github.com/MrBurge2000/mac-wine-launcher/releases/tag/v0.6.3
[0.6.2]: https://github.com/MrBurge2000/mac-wine-launcher/releases/tag/v0.6.2
[0.6.1]: https://github.com/MrBurge2000/mac-wine-launcher/releases/tag/v0.6.1
