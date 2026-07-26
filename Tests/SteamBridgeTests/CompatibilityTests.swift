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
    #expect(result.recommendedBackend == .automatic)
}

@Test func directXTwelveUsesD3DMetal() {
    let result = GameCompatibility.assess(title: "Big game", notes: "DirectX 12")
    #expect(result.rating == .likely)
    #expect(result.recommendedBackend == .d3dMetal)
}

@Test func automaticRendererPrefersModernMetalOnSupportedAppleSilicon() {
    let backend = GraphicsBackend.recommended(
        isAppleSilicon: true,
        operatingSystemMajorVersion: 15,
        available: [.d3dMetal, .dxmt, .dxvk, .wineD3D]
    )
    #expect(backend == .d3dMetal)
}

@Test func automaticRendererFallsBackToDXMT() {
    let backend = GraphicsBackend.recommended(
        isAppleSilicon: true,
        operatingSystemMajorVersion: 14,
        available: [.d3dMetal, .dxmt, .wineD3D]
    )
    #expect(backend == .dxmt)
}

@Test func freeRuntimeIsPreferred() {
    let kinds = EngineKind.allCases.sorted { $0.preferenceRank < $1.preferenceRank }
    #expect(kinds.first == .steamBridge)
}

@Test func currentSikarugirRuntimeIsPinnedAndChecksummed() {
    #expect(RuntimeInstaller.engineAsset.name == "WS12WineSikarugir10.0_6.tar.xz")
    #expect(RuntimeInstaller.engineAsset.sha256.count == 64)
    #expect(RuntimeInstaller.supportAsset.name == "Template-1.0.11.tar.xz")
    #expect(RuntimeInstaller.supportAsset.sha256.count == 64)
}

@Test func currentRuntimeIsPreferredOverLegacyStaging() {
    let current = "/Runtime/Sikarugir/wswine.bundle/bin/wine"
    let legacy = "/Runtime/Wine Staging.app/Contents/Resources/wine/bin/wine64"
    #expect(EngineDiscovery.runtimePreference(for: current) <
        EngineDiscovery.runtimePreference(for: legacy))
}

@Test func sikarugirSteamLaunchUsesNativeEngineFixes() {
    let current = Engine(
        kind: .steamBridge,
        executableURL: URL(fileURLWithPath: "/Runtime/Sikarugir/wswine.bundle/bin/wine")
    )
    #expect(Launcher.steamArguments(for: current).isEmpty)
}

@Test func legacyWineKeepsCompatibilityFlags() {
    let legacy = Engine(
        kind: .wine,
        executableURL: URL(fileURLWithPath: "/usr/local/bin/wine")
    )
    #expect(Launcher.steamArguments(for: legacy).contains("-cef-disable-gpu"))
    #expect(Launcher.steamArguments(for: legacy).contains("-cef-force-opaque-backgrounds"))
}

@Test func steamInstallerUsesSilentMode() {
    #expect(Launcher.silentInstallerArguments == ["/S"])
}

@Test func managedRuntimeFindsAndActivatesD3DMetal() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = root.appending(path: "Sikarugir")
    let wine = runtime.appending(path: "wswine.bundle/bin/wine")
    let d3dMetal = runtime.appending(
        path: "Frameworks/renderer/d3dmetal/wine/x86_64-windows/d3d12.dll"
    )
    let shared = runtime.appending(
        path: "Frameworks/renderer/d3dmetal/external/libd3dshared.dylib"
    )
    try FileManager.default.createDirectory(
        at: wine.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: d3dMetal.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: shared.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: wine)
    try Data().write(to: d3dMetal)
    try Data().write(to: shared)
    let engine = Engine(kind: .steamBridge, executableURL: wine)
    let bottle = Bottle(name: "Test", path: "/Bottle", engine: .steamBridge)

    #expect(Launcher.availableGraphicsBackends(for: engine).contains(.d3dMetal))
    let environment = Launcher.configuredEnvironment(
        engine: engine,
        bottle: bottle,
        graphicsBackend: .d3dMetal,
        baseEnvironment: [:]
    )
    #expect(environment["WINEDLLPATH_PREPEND"]?.contains("/renderer/d3dmetal/wine") == true)
    #expect(environment["CX_D3DMETALPATH"]?.contains("/renderer/d3dmetal/external") == true)
    #expect(environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == shared.path)
}

@Test func retinaDisplayProfileWritesWineRegistrySettings() {
    let commands = Launcher.displayRegistryArguments(for: .retinaRecommended)
    #expect(commands.count == 2)
    #expect(commands[0].contains("RetinaMode"))
    #expect(commands[0].contains("Y"))
    #expect(commands[1].contains("LogPixels"))
    #expect(commands[1].contains("192"))
}

@Test func standardDisplayProfileDisablesRetina() {
    let commands = Launcher.displayRegistryArguments(for: .standard)
    #expect(commands[0].contains("N"))
    #expect(commands[1].contains("96"))
}

@Test func steamInstallationDetectionRequiresExecutable() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let bottle = Bottle(name: "Test", path: root.path, engine: .steamBridge)
    let executable = Launcher.steamExecutableURL(in: bottle)
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("steam".utf8).write(to: executable)
    #expect(!Launcher.isSteamInstalled(in: bottle))

    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
    )
    #expect(Launcher.isSteamInstalled(in: bottle))
}

@Test func steamInstallerValidationRejectsIncompleteDownloads() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let invalid = root.appending(path: "SteamSetup.exe")
    try Data("not an installer".utf8).write(to: invalid)

    #expect(throws: Launcher.LaunchError.self) {
        try Launcher.validateSteamInstaller(at: invalid)
    }
}

@Test func steamInstallerValidationAcceptsCompletePEFile() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let installer = root.appending(path: "SteamSetup.exe")
    var data = Data([0x4d, 0x5a])
    data.append(Data(repeating: 0, count: Launcher.minimumSteamInstallerSize))
    try data.write(to: installer)

    try Launcher.validateSteamInstaller(at: installer)
}

@Test func steamRepairClearsPerUserWebCache() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appending(path: "drive_c/users/test/AppData/Local/Steam/htmlcache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data("cached".utf8).write(to: cache.appending(path: "data.bin"))
    let bottle = Bottle(name: "Test", path: root.path, engine: .steamBridge)

    Launcher.clearSteamWebCaches(in: bottle)

    #expect(!FileManager.default.fileExists(atPath: cache.path))
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
