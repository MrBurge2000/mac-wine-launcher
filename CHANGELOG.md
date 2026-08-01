# Changelog

All notable changes to SteamBridge are recorded here.

## [Unreleased]

No changes yet.

## [0.5.5] - 2026-08-01

- Grouped executable-scoped workarounds under a collapsed Known Game Bugs & Fixes area.
- Kept game-specific details out of normal Steam launch status.

## [0.5.4] - 2026-08-01

- Added automatic managed-bottle shutdown when SteamBridge quits.
- Added a visible Stop Steam & Wine action.
- Added bounded shutdown escalation for orphaned Wine helpers.
- Protected unrelated native processes with bottle-and-engine process matching.

## [0.5.3] - 2026-07-28

- Made normal Steam launch non-disruptive to other Windows applications.
- Added Steam UI health reporting.
- Added a clean built-in window-manager launch path.

## [0.5.2] - 2026-07-28

- Added generic Windows application launching and PyQt6/PySide6 compatibility.
- Repaired mixed-version Steam installations and inhibited client updates.

## [0.5.1] - 2026-07-26

- Added automatic DirectX renderer selection, Retina profiles, and executable-specific
  input workarounds.
- Fixed Steam installation progress and black login windows.

## [0.5.0] - 2026-07-26

- Initial public SteamBridge launcher.

[Unreleased]: https://github.com/MrBurge2000/SteamBridge/compare/v0.5.5...HEAD
[0.5.5]: https://github.com/MrBurge2000/SteamBridge/releases/tag/v0.5.5
