import AppKit
import SwiftUI

@MainActor
final class MacWineLauncherAppDelegate: NSObject, NSApplicationDelegate {
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
                  let engine = engines.first(where: { $0.kind == bottle.engine })
            else { return nil }
            return (bottle, engine)
        }
        guard !targets.isEmpty else { return .terminateNow }

        Task.detached {
            var failures: [String] = []
            for (bottle, engine) in targets {
                do {
                    try Launcher.stopBottleProcesses(in: bottle, using: engine)
                } catch {
                    NSLog("Mac Wine Launcher shutdown cleanup failed for %@: %@", bottle.name, error.localizedDescription)
                    failures.append("\(bottle.name): \(error.localizedDescription)")
                }
            }
            let details = failures.joined(separator: "\n\n")
            await MainActor.run {
                if !details.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "Wine cleanup did not finish"
                    alert.informativeText = details
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Keep Launcher Open")
                    alert.addButton(withTitle: "Quit Anyway")
                    let shouldQuit = alert.runModal() == .alertSecondButtonReturn
                    if !shouldQuit { self.terminationInProgress = false }
                    NSApplication.shared.reply(toApplicationShouldTerminate: shouldQuit)
                } else {
                    NSApplication.shared.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        return .terminateLater
    }
}

@main
struct MacWineLauncherApp: App {
    @NSApplicationDelegateAdaptor(MacWineLauncherAppDelegate.self) private var appDelegate
    @StateObject private var store = BottleStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onAppear {
                    appDelegate.bottlesProvider = { store.bottles }
                    let engines = EngineDiscovery.discover()
                    for bottle in store.bottles {
                        if let engine = engines.first(where: { $0.kind == bottle.engine }),
                           engine.kind != .crossover, engine.kind != .whisky {
                            WineProcessLedger.shared.watch(bottle, using: engine)
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 720)
    }
}
