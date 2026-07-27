# SteamBridge

SteamBridge is a macOS launcher for Windows apps and the Windows version of Steam
through an installed compatibility engine. It can download and manage its own free
Wine runtime, create isolated bottles, launch EXE/MSI applications and installers,
install Windows Steam, and launch it without CrossOver.

## What it is (and is not)

Wine translates Windows APIs; Apple’s Rosetta translates Intel CPU instructions on
Apple Silicon. SteamBridge coordinates those layers. It is not a universal emulator,
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
./.build/release/SteamBridge
```

To create a normal `.app` bundle:

```sh
./scripts/package-app.sh
open ./dist/SteamBridge.app
```

To create the branded drag-to-Applications disk image:

```sh
./scripts/package-dmg.sh
open ./dist/SteamBridge.dmg
```

The local build is ad-hoc signed. Public distribution without Gatekeeper warnings
requires an Apple Developer ID Application certificate and Apple notarization.

SteamBridge Wine is the default and costs nothing. The app installs the current
Sikarugir Wine 10 gaming engine and its matching open-source macOS support libraries
from the official `Sikarugir-App/Engines` and `Sikarugir-App/Wrapper` releases. Both
downloads are pinned to trusted SHA-256 checksums and stored under SteamBridge's own
Application Support directory. CrossOver and system Wine installations remain
supported, while Whisky is detected only for existing users.

The free runtime includes a switchable graphics stack. **AAA Auto** uses D3DMetal for
64-bit DirectX 11 and 12 games on supported Apple Silicon Macs. DXMT and DXVK provide
alternate DirectX 10/11 paths, D9VK accelerates many DirectX 9 games, and WineD3D is
the conservative fallback. SteamBridge also enables Rosetta's AVX advertisement on
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

Known game fixes are scoped to the affected executable. When
**Don't Panic! It is Just Turbulence** is installed, SteamBridge automatically writes
a menu-safe DirectInput mouse-warp override for that game only. The Input section can
restore Wine's default behavior or force pointer capture for camera-heavy scenes
without changing mouse behavior in any other game.

No translation layer can guarantee every Windows game. Renderer-specific bugs,
unsupported launchers, Windows driver requirements, DRM, and developer-disabled or
kernel anti-cheat can still prevent a title from running.

The managed runtime contains Steam-specific CEF and macOS windowing fixes. A normal
**Launch Steam** automatically upgrades legacy SteamBridge runtimes when needed, stops
stale Wine processes, clears Steam's real per-user web cache, and launches through the
tested Wine 10 environment. The manual black-window repair action remains available,
but it is not required for the normal path.

**Install Windows Steam** downloads a fresh copy of Valve's official installer every
time, validates that the download is a complete Windows executable, shows download and
installation progress, stops conflicting bottle processes, verifies that Steam was
actually installed, and then opens it. Existing installations are labeled clearly and
can be reinstalled from the same button. Valve's current first-launch Steam client
updates total about 570 MB and appear in Steam's own updater window before sign-in.

## Privacy and safety

Bottles live under `~/Library/Application Support/SteamBridge/Bottles`. The
**Uninstall Bottle** action asks for confirmation, stops that bottle's Wine processes,
and permanently removes Windows Steam, installed games, and other data stored inside
the bottle. It keeps SteamBridge and the shared Wine runtime installed.

SteamBridge validates the bottle path before deletion and refuses to remove anything
outside its managed Bottles directory. Steam credentials are entered only in Steam,
never in SteamBridge.
