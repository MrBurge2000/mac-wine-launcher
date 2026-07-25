import AppKit
import Foundation

enum Launcher {
    static let steamInstallerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    static let steamCompatibilityArguments = [
        "-no-cef-sandbox",
        "-cef-disable-gpu",
        "-cef-disable-gpu-compositing",
        "-cef-disable-gpu-sandbox",
        "-cef-disable-occlusion",
        "-cef-force-opaque-backgrounds"
    ]
    static let silentInstallerArguments = ["/S"]

    static func installSteam(in bottle: Bottle, using engine: Engine) async throws {
        if engine.kind == .crossover {
            try openEngineApp(for: engine)
            return
        }
        guard engine.kind != .whisky else {
            throw LaunchError.guiEngine(
                "Whisky is no longer maintained. SteamBridge Wine is the free recommended option."
            )
        }
        let installer = FileManager.default.temporaryDirectory.appending(path: "SteamSetup.exe")
        if !FileManager.default.fileExists(atPath: installer.path) {
            let (temporary, response) = try await URLSession.shared.download(from: steamInstallerURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw LaunchError.downloadFailed
            }
            try? FileManager.default.removeItem(at: installer)
            try FileManager.default.moveItem(at: temporary, to: installer)
        }
        try await runAndWait(
            engine: engine,
            bottle: bottle,
            arguments: [installer.path] + silentInstallerArguments
        )
        try launchSteam(in: bottle, using: engine)
    }

    static func launchSteam(in bottle: Bottle, using engine: Engine) throws {
        if engine.kind == .crossover {
            try openEngineApp(for: engine)
            return
        }
        guard engine.kind != .whisky else {
            NSWorkspace.shared.open(engine.executableURL)
            return
        }
        let steamPath = "\(bottle.path)/drive_c/Program Files (x86)/Steam/steam.exe"
        guard FileManager.default.fileExists(atPath: steamPath) else {
            throw LaunchError.steamMissing
        }
        try stopBottleProcesses(in: bottle, using: engine)
        try run(engine: engine, bottle: bottle, arguments: [steamPath] + steamCompatibilityArguments)
    }

    static func repairAndLaunchSteam(in bottle: Bottle, using engine: Engine) throws {
        guard engine.kind != .crossover, engine.kind != .whisky else {
            try launchSteam(in: bottle, using: engine)
            return
        }
        try stopBottleProcesses(in: bottle, using: engine)
        clearSteamWebCaches(in: bottle)
        try launchSteam(in: bottle, using: engine)
    }

    static func clearSteamWebCaches(in bottle: Bottle) {
        let prefixURL = URL(fileURLWithPath: bottle.path, isDirectory: true)
        let usersURL = prefixURL.appending(path: "drive_c/users", directoryHint: .isDirectory)
        if let users = try? FileManager.default.contentsOfDirectory(
            at: usersURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for userURL in users {
                let cacheURL = userURL.appending(
                    path: "AppData/Local/Steam/htmlcache",
                    directoryHint: .isDirectory
                )
                try? FileManager.default.removeItem(at: cacheURL)
            }
        }

        let legacyCacheURL = prefixURL.appending(
            path: "drive_c/Program Files (x86)/Steam/config/htmlcache",
            directoryHint: .isDirectory
        )
        try? FileManager.default.removeItem(at: legacyCacheURL)
    }

    private static func openEngineApp(for engine: Engine) throws {
        var url = engine.executableURL
        while url.pathExtension != "app", url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        guard url.pathExtension == "app", NSWorkspace.shared.open(url) else {
            throw LaunchError.engineCouldNotOpen
        }
    }

    private static func run(engine: Engine, bottle: Bottle, arguments: [String]) throws {
        let process = configuredProcess(engine: engine, bottle: bottle, arguments: arguments)
        try process.run()
    }

    private static func runAndWait(
        engine: Engine,
        bottle: Bottle,
        arguments: [String]
    ) async throws {
        try await Task.detached {
            let process = configuredProcess(engine: engine, bottle: bottle, arguments: arguments)
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw LaunchError.installerFailed(process.terminationStatus)
            }
        }.value
    }

    private static func configuredProcess(
        engine: Engine,
        bottle: Bottle,
        arguments: [String]
    ) -> Process {
        let process = Process()
        process.executableURL = engine.executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = bottle.path
        environment["WINEDEBUG"] = "-all"
        process.environment = environment
        return process
    }

    static func stopBottleProcesses(in bottle: Bottle, using engine: Engine) throws {
        let wineserver = engine.executableURL
            .deletingLastPathComponent()
            .appending(path: "wineserver")
        guard FileManager.default.isExecutableFile(atPath: wineserver.path) else { return }
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = bottle.path
        process.environment = environment
        try process.run()
        process.waitUntilExit()
    }

    enum LaunchError: LocalizedError {
        case downloadFailed
        case steamMissing
        case engineCouldNotOpen
        case installerFailed(Int32)
        case guiEngine(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "Steam’s Windows installer could not be downloaded."
            case .steamMissing: "Steam is not installed in this bottle yet."
            case .engineCouldNotOpen: "The compatibility engine could not be opened."
            case .installerFailed(let status): "The Steam installer exited with status \(status)."
            case .guiEngine(let message): message
            }
        }
    }
}
