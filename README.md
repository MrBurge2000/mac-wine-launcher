# Mac Wine Launcher

[![CI](https://github.com/MrBurge2000/mac-wine-launcher/actions/workflows/ci.yml/badge.svg)](https://github.com/MrBurge2000/mac-wine-launcher/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/MrBurge2000/mac-wine-launcher)](https://github.com/MrBurge2000/mac-wine-launcher/releases/latest)
[![Official website](https://img.shields.io/badge/Website-Mac_Wine_Launcher-4ee7c0)](https://mac-wine-launcher.angelo01px2028.chatgpt.site)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](https://github.com/MrBurge2000/mac-wine-launcher/releases/latest)

**Mac Wine Launcher is a free, open-source Wine wrapper for macOS.** It gives Apple
Silicon and Intel Mac users an easy graphical way to install Wine, create isolated Wine
bottles, run Windows `.exe` and `.msi` apps, and install or launch Windows Steam on Mac.
No CrossOver subscription is required.

[Visit the official website](https://mac-wine-launcher.angelo01px2028.chatgpt.site) for a quick overview,
compatibility notes, and the latest verified download.

This project was formerly called SteamBridge. The new name makes its purpose clear and
avoids confusion with unrelated projects that already use that name.

## Download

Download the current DMG or universal ZIP from [GitHub Releases](https://github.com/MrBurge2000/mac-wine-launcher/releases/latest).
Open the DMG and drag Mac Wine Launcher into Applications. The current community build is
ad-hoc signed but not Apple-notarized, so macOS may require **Control-click → Open** on
first launch. Never download Mac Wine Launcher from an unofficial mirror.

## Highlights

- Managed, isolated Wine bottles for Windows Steam and ordinary Windows applications
- Free pinned Wine runtime with SHA-256 verification and visible installation progress
- DirectX 9–12 renderer selection, Retina scaling, and executable-scoped game fixes
- Automatic Steam UI health checks and recovery tools
- Battery-safe shutdown that removes orphaned Wine and Steam helper processes
- Universal macOS application for Apple Silicon and Intel

## Run Windows apps and Windows Steam on macOS with Wine

Mac Wine Launcher wraps the Wine compatibility layer in a native SwiftUI interface. You
can install the managed free runtime with one button, make a separate bottle for each
Windows environment, then choose a Windows app or install Windows Steam. Apple Silicon
Macs use Rosetta 2 for the Intel parts of the Windows runtime.

If you are searching for an easy Wine wrapper for Mac, a Windows app launcher for
macOS, or a way to run Windows Steam games on Apple Silicon, this is what the project is
built for. It is a compatibility layer—not a Windows virtual machine or a Linux emulator.

## Project links

- [Official Mac Wine Launcher website](https://mac-wine-launcher.angelo01px2028.chatgpt.site)
- [Latest release](https://github.com/MrBurge2000/mac-wine-launcher/releases/latest)
- [Report a bug](https://github.com/MrBurge2000/mac-wine-launcher/issues/new?template=bug_report.yml)
- [Request a feature](https://github.com/MrBurge2000/mac-wine-launcher/issues/new?template=feature_request.yml)
- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## What it is (and is not)

Wine translates Windows APIs; Apple’s Rosetta translates Intel CPU instructions on
Apple Silicon. Mac Wine Launcher coordinates those layers. It is not a universal emulator,
does not bypass DRM, and cannot make every game work.

Linux-only games are not directly supported. In practice, Steam usually provides a
Windows build of the same game; install that build inside Windows Steam. Linux-native
binaries would require a Linux virtual machine because macOS and Linux have different
kernels and graphics stacks.

Common blockers include kernel anti-cheat (Vanguard and many Easy Anti-Cheat/BattlEye
configurations), some third-party launchers, AVX requirements under some translation
paths, and engine-specific DirectX 12 bugs.

## Build

Requirements: macOS 14+ on Apple Silicon or Intel. Apple Silicon needs Rosetta 2
for the x86 Windows runtime.
If Xcode is installed, open it once and accept Apple's license before building.

```sh
swift test
swift build -c release
./.build/release/MacWineLauncher
```

To create a normal `.app` bundle:

```sh
./scripts/package-app.sh
open "./dist/Mac Wine Launcher.app"
```

To create the branded drag-to-Applications disk image:

```sh
./scripts/package-dmg.sh
open ./dist/Mac-Wine-Launcher.dmg
```

The local build is ad-hoc signed. Public distribution without Gatekeeper warnings
requires an Apple Developer ID Application certificate and Apple notarization.

Mac Wine Launcher Wine is the default and costs nothing. The app installs the current
Sikarugir Wine 10 gaming engine and its matching open-source macOS support libraries
from the official `Sikarugir-App/Engines` and `Sikarugir-App/Wrapper` releases. Both
downloads are pinned to trusted SHA-256 checksums and stored under Mac Wine Launcher's own
Application Support directory. CrossOver and system Wine installations remain
supported, while Whisky is detected only for existing users.

The free runtime includes a switchable graphics stack. **AAA Auto** uses D3DMetal for
64-bit DirectX 11 and 12 games on supported Apple Silicon Macs. DXMT and DXVK provide
alternate DirectX 10/11 paths, D9VK accelerates many DirectX 9 games, and WineD3D is
the conservative fallback. Mac Wine Launcher also enables Rosetta's AVX advertisement on
supported macOS versions. Games launched from a Steam session inherit the selected
graphics mode.

The **Windows Apps** section launches `.exe`, `.msi`, `.com`, `.bat`, and `.cmd`
files directly through Wine. MSI packages use Windows Installer automatically, quoted
launch arguments are parsed without a shell, each app starts from its own folder, and
recent apps are remembered separately for each bottle. The selected graphics backend
is shared with directly launched apps.

The managed runtime also installs WineHQ's pinned 32-bit and 64-bit ICU compatibility
libraries into each bottle. This supplies the Windows Unicode system DLLs expected by
current PyQt6 and other modern Windows applications. Packaged PyQt6/PySide6 apps are
detected automatically and Qt WebEngine uses a Wine-safe software rendering fallback,
without changing the graphics mode used by games or other Windows apps.

Per-bottle display profiles control Wine's macOS Retina mode and Windows DPI. The
recommended Retina profile renders Steam at 2× resolution with 200% Windows scaling,
keeping the interface readable while exposing higher display resolutions to games.
Each game still controls its own fullscreen resolution; native Retina is sharpest,
while a lower in-game resolution usually delivers better frame rate.

Known game fixes are scoped to the affected executable and applied silently. When an
installed title needs a game-specific input or graphics workaround, Mac Wine Launcher enables
it automatically without changing other games. A collapsed **Known Game Bugs & Fixes**
section exposes the affected title and manual fallbacks only for troubleshooting.

No translation layer can guarantee every Windows game. Renderer-specific bugs,
unsupported launchers, Windows driver requirements, DRM, and developer-disabled or
kernel anti-cheat can still prevent a title from running.

The managed runtime contains Steam-specific CEF and macOS windowing fixes. A normal
**Launch Steam** automatically upgrades legacy managed runtimes when needed and
launches through the tested Wine 10 environment without stopping the bottle, closing
other Windows apps, or clearing their state. Steam uses Wine's built-in window-manager
library so incompatible local window proxies cannot prevent its interface from opening.
Mac Wine Launcher waits for `steamwebhelper.exe` and reports a clear failure if the interface
does not appear within 30 seconds. The explicit black-window repair remains available
for the rare case where Steam's web cache genuinely needs to be rebuilt.

Since version 0.5.4, Mac Wine Launcher also owns the shutdown lifecycle of its managed bottles. Closing the
last Mac Wine Launcher window or choosing Quit stops Steam and Wine by default. Shutdown first
asks the bottle's `wineserver` to exit, then terminates and finally force-stops only
processes proven to have files open inside that bottle. This prevents detached
`steamwebhelper.exe` and `wineserver` processes from silently consuming CPU and battery.
The Steam section includes a visible **Stop Steam & Wine** button and an opt-out toggle
for users who intentionally want their Windows apps to continue after Mac Wine Launcher quits.

**Install Windows Steam** downloads a fresh copy of Valve's official installer every
time, validates that the download is a complete Windows executable, shows download and
installation progress, stops conflicting bottle processes, verifies that Steam was
actually installed, and then opens it. Existing installations are labeled clearly and
can be reinstalled from the same button. Valve's current first-launch Steam client
updates total about 570 MB and appear in Steam's own updater window before sign-in.

## Privacy and safety

Bottles live under `~/Library/Application Support/Mac Wine Launcher/Bottles`. The
**Uninstall Bottle** action asks for confirmation, stops that bottle's Wine processes,
and permanently removes Windows Steam, installed games, and other data stored inside
the bottle. It keeps Mac Wine Launcher and the shared Wine runtime installed.

Mac Wine Launcher validates the bottle path before deletion and refuses to remove anything
outside its managed Bottles directory. Steam credentials are entered only in Steam,
never in Mac Wine Launcher.

## Contributing

Community changes are welcome through forks and pull requests. The protected `main`
branch cannot be changed directly; every proposed change remains a reviewable diff until
the repository owner approves and merges it. Read [CONTRIBUTING.md](CONTRIBUTING.md)
before opening a pull request.

## License

Mac Wine Launcher is available under the [MIT License](LICENSE). Steam and related trademarks
belong to Valve Corporation. Mac Wine Launcher is an independent project and is not affiliated
with or endorsed by Valve.
