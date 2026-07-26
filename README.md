# SteamBridge

SteamBridge is a macOS launcher for running the Windows version of Steam through an
installed compatibility engine. It can download and manage its own free Wine runtime,
create isolated bottles, install Windows Steam, and launch it without CrossOver.

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

The free runtime uses Wine's available WineD3D/Vulkan path. It will not match every
commercial CrossOver optimization, and some DirectX 12 titles will still fail.

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
