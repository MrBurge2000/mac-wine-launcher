# Architecture

Mac Wine Launcher is a SwiftUI macOS application built as a Swift Package executable.

## Components

- `BottleStore` creates, persists, validates, and uninstalls managed Wine prefixes.
- `EngineDiscovery` locates the managed Sikarugir runtime and supported external engines.
- `RuntimeInstaller` downloads pinned runtime artifacts and verifies SHA-256 checksums.
- `Launcher` owns Steam installation, Windows process launch, renderer selection,
  registry configuration, UI health checks, and bottle-scoped shutdown.
- `ContentView` presents bottle, Steam, Windows application, display, graphics, known-fix,
  and uninstall workflows.
- `MacWineLauncherAppDelegate` performs managed-bottle cleanup when the macOS app terminates.

## Trust boundaries

Mac Wine Launcher accepts local Windows executable paths and starts them directly through Wine;
it does not interpolate them into a shell. Runtime downloads are trusted only after their
pinned digest matches. Destructive bottle operations must resolve underneath the managed
Bottles directory. Process cleanup intersects bottle-open files with the selected Wine
engine so unrelated native applications are not terminated.

## Distribution

`scripts/package-app.sh` builds a universal arm64/x86_64 application and applies an ad-hoc
signature. `scripts/package-dmg.sh` creates the branded drag-to-Applications image. A
public production release should additionally use Developer ID signing and notarization.
