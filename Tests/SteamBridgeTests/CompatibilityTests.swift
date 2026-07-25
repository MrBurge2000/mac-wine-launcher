import Foundation
import Testing
@testable import SteamBridge

@Test func antiCheatIsBlocked() {
    let result = GameCompatibility.assess(title: "Example", notes: "Uses Easy Anti-Cheat")
    #expect(result.rating == .blocked)
}

@Test func directXElevenIsLikely() {
    let result = GameCompatibility.assess(title: "Example", notes: "DX11 single player")
    #expect(result.rating == .likely)
}

@Test func freeRuntimeIsPreferred() {
    let kinds = EngineKind.allCases.sorted { $0.preferenceRank < $1.preferenceRank }
    #expect(kinds.first == .steamBridge)
}

@Test func stagingRuntimeAssetIsPreferredForGaming() {
    let staging = RuntimeInstaller.Asset(
        name: "wine-staging-11.10-osx64.tar.xz",
        browserDownloadURL: URL(string: "https://example.com/staging")!
    )
    let stable = RuntimeInstaller.Asset(
        name: "wine-stable-11.0-osx64.tar.xz",
        browserDownloadURL: URL(string: "https://example.com/stable")!
    )
    let selected = RuntimeInstaller.preferredAsset(in: [
        .init(assets: [staging]),
        .init(assets: [stable])
    ])
    #expect(selected == staging)
}

@Test func steamLaunchDisablesProblematicCEFGPUPaths() {
    #expect(Launcher.steamCompatibilityArguments.contains("-cef-disable-gpu"))
    #expect(Launcher.steamCompatibilityArguments.contains("-cef-disable-gpu-compositing"))
    #expect(Launcher.steamCompatibilityArguments.contains("-no-cef-sandbox"))
}

@Test func steamInstallerUsesSilentMode() {
    #expect(Launcher.silentInstallerArguments == ["/S"])
}

@Test @MainActor func bottleStorePersists() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = BottleStore(rootURL: root)
    let created = try first.create(name: "Test", engine: .wine)
    let second = BottleStore(rootURL: root)
    #expect(second.bottles == [created])
}

@Test @MainActor func bottleStoreUninstallsBottleData() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = BottleStore(rootURL: root)
    let bottle = try store.create(name: "Disposable", engine: .steamBridge)
    let marker = URL(fileURLWithPath: bottle.path).appending(path: "installed-game.dat")
    try Data("game data".utf8).write(to: marker)

    try await store.uninstall(bottle)

    #expect(!FileManager.default.fileExists(atPath: bottle.path))
    #expect(store.bottles.isEmpty)
}

@Test @MainActor func bottleStoreRefusesToDeleteOutsideManagedFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    var bottle = Bottle(name: "Unsafe", path: outside.path, engine: .steamBridge)
    bottle.path = outside.path
    let store = BottleStore(rootURL: root)

    do {
        try await store.uninstall(bottle)
        Issue.record("Expected uninstall to reject an unmanaged path.")
    } catch {
        #expect(error is BottleStore.StoreError)
    }

    #expect(FileManager.default.fileExists(atPath: outside.path))
}
