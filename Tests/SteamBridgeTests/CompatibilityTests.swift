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
    #expect(RuntimeInstaller.wineICUX64Asset.sha256.count == 64)
    #expect(RuntimeInstaller.wineICUX86Asset.sha256.count == 64)
    #expect(RuntimeInstaller.currentVersion.contains("WineICU-72.1"))
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

@Test func windowsExecutableLaunchesDirectlyWithArguments() throws {
    let url = URL(fileURLWithPath: "/Applications/Example App.exe")
    let arguments = try Launcher.windowsApplicationArguments(
        for: url,
        additionalArguments: ["--safe-mode", "My File"]
    )
    #expect(arguments == [url.path, "--safe-mode", "My File"])
}

@Test func windowsInstallerUsesMSIExec() throws {
    let url = URL(fileURLWithPath: "/Downloads/Example.msi")
    let arguments = try Launcher.windowsApplicationArguments(for: url)
    #expect(arguments == ["msiexec", "/i", url.path])
}

@Test func windowsBatchScriptUsesCommandInterpreter() throws {
    let url = URL(fileURLWithPath: "/Downloads/setup.cmd")
    let arguments = try Launcher.windowsApplicationArguments(for: url)
    #expect(arguments == ["cmd", "/c", url.path])
}

@Test func wineICUInstallsOnlyBesideTheDetectedQtRuntimeWithoutOverwriting() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "WineICU", directoryHint: .isDirectory)
    let destination = root.appending(path: "App/_internal/PyQt6/Qt6/bin")
    for architecture in ["x86_64", "x86"] {
        let directory = source.appending(path: architecture, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        for fileName in ["icuuc72.dll", "icuin72.dll", "icudt72.dll"] {
            try Data("\(architecture)-\(fileName)".utf8).write(
                to: directory.appending(path: fileName)
            )
        }
    }
    let existing = destination.appending(path: "icuuc.dll")
    try FileManager.default.createDirectory(
        at: existing.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("keep-existing".utf8).write(to: existing)

    try Launcher.installWineICU(
        from: source,
        architecture: .x86_64,
        into: destination
    )

    #expect(try String(contentsOf: existing, encoding: .utf8) == "keep-existing")
    #expect(FileManager.default.fileExists(
        atPath: destination.appending(path: "icudt72.dll").path
    ))
    #expect(FileManager.default.fileExists(
        atPath: destination.appending(path: "icuin.dll").path
    ))
    #expect(try String(
        contentsOf: destination.appending(path: "icuuc72.dll"),
        encoding: .utf8
    ) == "x86_64-icuuc72.dll")
}

@Test func qtRuntimeArchitectureIsReadFromPEHeader() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let x64 = root.appending(path: "Qt6Core-x64.dll")
    let x86 = root.appending(path: "Qt6Core-x86.dll")
    try peStub(machine: 0x8664).write(to: x64)
    try peStub(machine: 0x014c).write(to: x86)

    #expect(Launcher.wineICUArchitecture(of: x64) == .x86_64)
    #expect(Launcher.wineICUArchitecture(of: x86) == .x86)
}

@Test func steamIntegrityRepairUnblocksUpdatesAndRestoresNewerBootstrap() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let steam = root.appending(path: "Steam", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: steam, withIntermediateDirectories: true)
    let current = steam.appending(path: "steam.exe")
    let backup = steam.appending(path: "steam.exe.old")
    try peStub(machine: 0x014c, marker: 1).write(to: current)
    try peStub(machine: 0x014c, marker: 2).write(to: backup)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)],
        ofItemAtPath: current.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 200)],
        ofItemAtPath: backup.path
    )
    try "BootStrapperInhibitAll=Enable\r\n".write(
        to: steam.appending(path: "steam.cfg"),
        atomically: true,
        encoding: .utf8
    )

    try Launcher.removeSteamUpdateInhibitor(in: steam)
    try Launcher.restoreNewerSteamBootstrapBackup(in: steam)

    #expect(!FileManager.default.fileExists(atPath: steam.appending(path: "steam.cfg").path))
    #expect(FileManager.default.fileExists(
        atPath: steam.appending(path: "steam.cfg.disabled-by-steambridge").path
    ))
    #expect(try Data(contentsOf: current).last == 2)
    #expect(FileManager.default.fileExists(
        atPath: steam.appending(path: "steam.exe.replaced-by-steambridge").path
    ))
}

@Test func packagedPyQtAppsUseWineSafeWebEngineRendering() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appending(path: "Example.exe")
    let qtRuntime = root.appending(
        path: "_internal/PyQt6/Qt6",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: qtRuntime,
        withIntermediateDirectories: true
    )

    let environment = Launcher.windowsApplicationEnvironment(
        for: application,
        baseEnvironment: ["QTWEBENGINE_CHROMIUM_FLAGS": "--existing-flag"]
    )

    #expect(environment["QTWEBENGINE_DISABLE_SANDBOX"] == "1")
    #expect(environment["QT_QUICK_BACKEND"] == "software")
    #expect(environment["QT_OPENGL"] == "software")
    #expect(environment["QTWEBENGINE_CHROMIUM_FLAGS"]?.contains("--existing-flag") == true)
    #expect(environment["QTWEBENGINE_CHROMIUM_FLAGS"]?.contains("--disable-gpu") == true)
}

@Test func taskListProcessMatchingUsesTheExecutableColumn() {
    let output = """
    steam.exe                   32 C:\\Program Files (x86)\\Steam\\steam.exe
    steamwebhelper.exe         88 C:\\Program Files (x86)\\Steam\\bin\\cef\\steamwebhelper.exe
    """

    #expect(Launcher.taskListContainsProcess(output, named: "steamwebhelper.exe"))
    #expect(!Launcher.taskListContainsProcess(output, named: "helper.exe"))
}

@Test func steamLaunchUsesBuiltinWindowManagerWithoutLosingOtherOverrides() {
    let environment = Launcher.steamProcessEnvironment(
        baseEnvironment: [
            "WINEDLLOVERRIDES": "mscoree=;dwmapi=n;mshtml=",
            "KEEP_ME": "yes"
        ]
    )

    #expect(environment["WINEDLLOVERRIDES"] == "mscoree=;mshtml=;dwmapi=b")
    #expect(environment["KEEP_ME"] == "yes")
}

@Test func nonQtWindowsAppsKeepTheirEnvironment() {
    let application = URL(fileURLWithPath: "/Applications/Example.exe")
    let environment = ["CUSTOM": "value"]
    #expect(Launcher.windowsApplicationEnvironment(
        for: application,
        baseEnvironment: environment
    ) == environment)
}

private func peStub(machine: UInt16, marker: UInt8 = 0) -> Data {
    var data = Data(repeating: 0, count: 128)
    data[0] = 0x4d
    data[1] = 0x5a
    var offset = UInt32(64).littleEndian
    withUnsafeBytes(of: &offset) { data.replaceSubrange(0x3c..<0x40, with: $0) }
    data[64] = 0x50
    data[65] = 0x45
    var encodedMachine = machine.littleEndian
    withUnsafeBytes(of: &encodedMachine) {
        data.replaceSubrange(68..<70, with: $0)
    }
    data[data.count - 1] = marker
    return data
}

@Test func unsupportedWindowsApplicationIsRejected() {
    #expect(throws: Launcher.LaunchError.self) {
        try Launcher.windowsApplicationArguments(
            for: URL(fileURLWithPath: "/Downloads/archive.zip")
        )
    }
}

@Test func quotedWindowsArgumentsAreParsedWithoutShellExecution() throws {
    let arguments = try WindowsCommandLine.parse(
        #"--safe-mode "My File.txt" 'second value' C:\Games\Save"#
    )
    #expect(arguments == [
        "--safe-mode", "My File.txt", "second value", #"C:\Games\Save"#
    ])
}

@Test func unclosedWindowsArgumentQuoteIsRejected() {
    #expect(throws: WindowsCommandLine.ParseError.self) {
        try WindowsCommandLine.parse(#""unfinished"#)
    }
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

@Test func dontPanicMenuSafeProfileIsExecutableSpecific() {
    let commands = Launcher.gameInputRegistryArguments(
        for: .menuSafe,
        executableName: Launcher.dontPanicExecutableName
    )
    #expect(commands.count == 1)
    #expect(commands[0].contains("MouseWarpOverride"))
    #expect(commands[0].contains("disable"))
    #expect(
        commands[0].contains(
            "HKCU\\Software\\Wine\\AppDefaults\\Don't Panic! It is Just Turbulence.exe\\DirectInput"
        )
    )
}

@Test func dontPanicCameraProfileCanForceCapture() {
    let commands = Launcher.gameInputRegistryArguments(
        for: .forceCapture,
        executableName: Launcher.dontPanicExecutableName
    )
    #expect(commands[0].contains("force"))
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
