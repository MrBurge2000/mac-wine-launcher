import AppKit
import SwiftUI

final class SteamBridgeAppDelegate: NSObject, NSApplicationDelegate {
    static let stopWineOnQuitKey = "stopWineOnQuit"

    @MainActor var bottlesProvider: () -> [Bottle] = { [] }
    private var terminationInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.stopWineOnQuitKey: true])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UserDefaults.standard.bool(forKey: Self.stopWineOnQuitKey) else {
            return .terminateNow
        }
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true

        let bottles = bottlesProvider()
        let engines = EngineDiscovery.discover()
        let targets = bottles.compactMap { bottle -> (Bottle, Engine)? in
            guard bottle.engine != .crossover, bottle.engine != .whisky,
                  let engine = engines.first(where: { $0.kind == bottle.engine }) ?? engines.first
            else { return nil }
            return (bottle, engine)
        }
        guard !targets.isEmpty else { return .terminateNow }

        Task.detached {
            for (bottle, engine) in targets {
                do {
                    try Launcher.stopBottleProcesses(in: bottle, using: engine)
                } catch {
                    NSLog("SteamBridge shutdown cleanup failed for %@: %@", bottle.name, error.localizedDescription)
                }
            }
            await MainActor.run {
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct SteamBridgeApp: App {
    @NSApplicationDelegateAdaptor(SteamBridgeAppDelegate.self) private var appDelegate
    @StateObject private var store = BottleStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onAppear {
                    appDelegate.bottlesProvider = { store.bottles }
                }
        }
        .windowStyle(.titleBar)
    }
}
