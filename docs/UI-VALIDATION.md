# Native interface validation

Validated locally on 2026-10-08, macOS 26.5.2 with 24 GB memory. This is the
0.6.10/build 29 interface update, based on the 0.6.9 release.

## Functionality retained

- Apps: install/reinstall Windows Steam, launch Steam, stop the selected bottle,
  open its C: drive, run Windows executables/installers with arguments, and use or
  clear the per-bottle recent-app list.
- Graphics & Display: all available renderer choices, Automatic selection, all
  three display profiles, and apply/relaunch.
- Troubleshooting: black-window repair, installed-game fix details and manual
  fallback controls, mouse profiles, and compatibility assessment.
- Bottle: runtime update, bottle information, minimized Steam start, cleanup on
  launcher quit, and confirmed uninstall.
- Initial setup: free runtime installation with progress and new-bottle creation.

Runtime, launch, shutdown, storage, compatibility, and game-fix implementations
are unchanged from 0.6.9. The action-method block in ContentView is byte-identical
to that release. Persistent runtime/renderer/display identifiers are unchanged.
The interface uses native controls and system colors, with no new polling,
decorative animation, or third-party UI dependency.

## Verification performed

- The Swift Testing suite reports 64 passing tests, including presentation names,
  retained display choices, installed-renderer coverage, native symbols, and
  compact progress-view sizing. The two opt-in real-Wine diagnostic tests were
  not enabled in this run; simulated isolation tests are not a fresh real-bottle
  isolation result.
- Universal arm64/x86_64 packaging succeeded. Strict signature verification
  passed for the built and installed apps, and their executable hashes matched.
  Signing remains ad hoc, not Developer ID/notarized.
- Inspected light and dark appearance during development. The finished app uses
  the Mac's system appearance, without a forced color scheme.
- Exercised every section, renderer/display/mouse menus, installed-game fix
  disclosure, and the compatibility assessment. Canceled the new-bottle, Windows
  app picker, and uninstall dialogs without creating or deleting user data.
  Blank bottle names disable Create.
- Found and corrected a status-related minimum-size expansion during live QA.
  On the final build, navigation and feedback remain visible during a real Steam
  startup, on completion, after cleanup, and when switching sections. Scroll
  position resets to the top of the newly selected section.
- Started real Windows Steam through the primary launch button; its existing
  interface-health check succeeded. Stopped it through Stop Steam & Wine and
  verified no Wine, Steam, Steam web-helper, or Wukong processes remained.
  Launcher-quit cleanup was also exercised during development.
- The existing bottle manifest, Wukong GameUserSettings.ini and Engine.ini hashes
  matched the pre-update baseline. Renderer and mouse-profile preferences remained
  unset, the saved Retina display choice remained intact, both shutdown/start
  preferences stayed enabled, and recent-app history retained its hash.
- After cleanup, two five-second idle samples showed the native launcher at 0.3%
  CPU and about 58 MB process memory. The earlier 0.6.9 samples were 0.2–0.3%
  CPU and about 57 MB. This is a short idle check, not a gaming FPS benchmark.

## Limits

This was an interface update, not another gameplay/performance tuning pass. No
full Wukong playthrough, FPS comparison, fresh runtime download, Steam reinstall,
destructive uninstall, Intel execution, or older-macOS UI run was performed.
Keeping the engine and game-launch code unchanged does not prove every game runs
without regressions. This report records local interface validation; release
packaging, downloaded-asset checks, and CI results are recorded separately in the
GitHub release notes.
