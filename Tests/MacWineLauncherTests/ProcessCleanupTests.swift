import Darwin
import Foundation
import Testing
@testable import MacWineLauncher

@Test func shutdownKeepsAnotherBottleUsingTheSameEngineAlive() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appending(path: "First")
    let second = root.appending(path: "Second")
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    let a = Bottle(name: "First", path: first.path, engine: .wine)
    let b = Bottle(name: "Second", path: second.path, engine: .wine)
    let engine = Engine(kind: .wine, executableURL: URL(fileURLWithPath: "/bin/zsh"))
    func spawn(_ bottle: Bottle) throws -> Process {
        let process = Process()
        process.executableURL = engine.executableURL
        process.arguments = ["-c", "trap '' TERM; while true; do sleep 1; done"]
        process.environment = ["WINEPREFIX": bottle.path, "PATH": "/bin:/usr/bin"]
        process.currentDirectoryURL = URL(fileURLWithPath: bottle.path)
        try process.run()
        return process
    }
    let one = try spawn(a)
    let two = try spawn(b)
    defer { for process in [one, two] where process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) } }
    Thread.sleep(forTimeInterval: 0.1)
    try #require(Launcher.bottleProcessIDs(in: a, using: engine).contains(one.processIdentifier))
    #expect(!Launcher.bottleProcessIDs(in: a, using: engine).contains(two.processIdentifier))
    try Launcher.stopBottleProcesses(in: a, using: engine, gracefulTimeout: 0.1, terminationTimeout: 0.2)
    one.waitUntilExit()
    #expect(!one.isRunning)
    #expect(two.isRunning)
    #expect(Launcher.bottleProcessIDs(in: b, using: engine).contains(two.processIdentifier))
}

@Test func savedIdentityRetainsOwnershipWithoutOpenBottleFilesAndRejectsPIDReuse() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bottle = Bottle(name: "Tracked", path: root.appending(path: "NoOpenFiles").path, engine: .wine)
    let engine = Engine(kind: .wine, executableURL: URL(fileURLWithPath: "/bin/sleep"))
    let child = Process()
    child.executableURL = engine.executableURL
    child.arguments = ["30"]
    try child.run()
    defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
    let identity = try #require(WineProcessIdentity.current(child.processIdentifier))
    let storage = root.appending(path: "ledger.json")
    let ledger = WineProcessLedger(storage: storage)
    ledger.remember([identity], in: bottle, using: engine)
    // There is no WINEPREFIX and no file in this bottle, as for a process that has
    // closed descriptors on the way to exit. Restore the verified birth identity.
    let restored = WineProcessLedger(storage: storage)
    #expect(restored.identities(in: bottle, using: engine).contains(identity))
    let reusedPID = WineProcessIdentity(pid: identity.pid, startedSeconds: identity.startedSeconds + 1,
                                       startedMicroseconds: identity.startedMicroseconds)
    #expect(!reusedPID.isCurrent)
    restored.remember([reusedPID], in: bottle, using: engine)
    #expect(!restored.identities(in: bottle, using: engine).contains(reusedPID))
    child.terminate()
    child.waitUntilExit()
    #expect(restored.identities(in: bottle, using: engine).isEmpty)
}

@Test func minimizedSteamKeepsTheManagedRuntimeCompatibilityFlags() {
    let engine = Engine(kind: .managedWine, executableURL: URL(fileURLWithPath: "/Runtime/Sikarugir/wswine.bundle/bin/wine"))
    #expect(Launcher.steamArguments(for: engine, startMinimized: true) == ["-silent"])
    #expect(Launcher.steamArguments(for: engine) == [])
}

// Opt-in diagnostics for the installed runtime; no game/configuration changes.
@Test func installedBottleProcessDiagnostics() throws {
    guard let path = ProcessInfo.processInfo.environment["MWL_DIAGNOSE_BOTTLE"],
          let executable = ProcessInfo.processInfo.environment["MWL_DIAGNOSE_ENGINE"] else { return }
    let bottle = Bottle(name: "Diagnostics", path: path, engine: .managedWine)
    let engine = Engine(kind: .managedWine, executableURL: URL(fileURLWithPath: executable))
    let identities = Launcher.bottleProcessIdentities(in: bottle, using: engine)
    print("Verified bottle PIDs: \(identities.map(\.pid).sorted())")
    print("Unowned exiting Wine PIDs: \(WineProcessLedger.unownedExitingWinePIDs())")
}

@Test func actualWineBottleShutdownIsolation() throws {
    guard let executable = ProcessInfo.processInfo.environment["MWL_TEST_RUNTIME"] else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: "mwl-isolation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let engine = Engine(kind: .managedWine, executableURL: URL(fileURLWithPath: executable))
    let bottles = ["A", "B"].map { Bottle(name: $0, path: root.appending(path: $0).path, engine: .managedWine) }
    var processes: [Process] = []
    defer {
        for bottle in bottles { try? Launcher.stopBottleProcesses(in: bottle, using: engine, gracefulTimeout: 5) }
        if bottles.allSatisfy({ Launcher.bottleProcessIDs(in: $0, using: engine).isEmpty }) {
            try? FileManager.default.removeItem(at: root)
        }
    }
    for bottle in bottles {
        let process = Process()
        process.executableURL = engine.executableURL
        process.arguments = ["cmd", "/c", "ping -n 120 127.0.0.1 >NUL"]
        process.environment = Launcher.configuredEnvironment(engine: engine, bottle: bottle)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        processes.append(process)
    }
    Thread.sleep(forTimeInterval: 5)
    let one = Launcher.bottleProcessIdentities(in: bottles[0], using: engine)
    let two = Launcher.bottleProcessIdentities(in: bottles[1], using: engine)
    try #require(!one.isEmpty && !two.isEmpty)
    #expect(one.isDisjoint(with: two))
    do { try Launcher.stopBottleProcesses(in: bottles[0], using: engine, gracefulTimeout: 5) }
    catch Launcher.LaunchError.unownedWineStillExiting { /* Existing old orphan is reported but not signalled. */ }
    #expect(Launcher.bottleProcessIDs(in: bottles[0], using: engine).isEmpty)
    #expect(two.contains { $0.isCurrent })
    #expect(processes[1].isRunning)
    print("Actual Wine isolation: stopped A \(one.map(\.pid).sorted()); B still active \(two.filter(\.isCurrent).map(\.pid).sorted())")
}
