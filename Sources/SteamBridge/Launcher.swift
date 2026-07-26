import AppKit
import Foundation

enum Launcher {
    static let steamInstallerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    static let minimumSteamInstallerSize = 1_000_000
    // Retained for advanced/legacy Wine installs. The managed Sikarugir runtime
    // carries its own Steam-specific CEF fixes and must launch without these flags.
    static let steamCompatibilityArguments = [
        "-no-cef-sandbox",
        "-cef-disable-gpu",
        "-cef-disable-gpu-compositing",
        "-cef-disable-gpu-sandbox",
        "-cef-disable-occlusion",
        "-cef-force-opaque-backgrounds"
    ]
    static let silentInstallerArguments = ["/S"]

    static func installSteam(
        in bottle: Bottle,
        using engine: Engine,
        progress: @escaping @MainActor @Sendable (SteamInstallProgress) -> Void = { _ in }
    ) async throws {
        if engine.kind == .crossover {
            try openEngineApp(for: engine)
            return
        }
        guard engine.kind != .whisky else {
            throw LaunchError.guiEngine(
                "Whisky is no longer maintained. SteamBridge Wine is the free recommended option."
            )
        }
        await progress(.init(stage: .preparing, fraction: 0.02, detail: "Stopping old Steam processes…"))
        try stopBottleProcesses(in: bottle, using: engine)

        let installer = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-SteamSetup.exe")
        defer { try? FileManager.default.removeItem(at: installer) }
        try await downloadSteamInstaller(to: installer, progress: progress)
        try validateSteamInstaller(at: installer)

        await progress(.init(
            stage: .installing,
            fraction: 0.62,
            detail: "Installing Windows Steam. This usually takes 1–3 minutes…"
        ))
        try await runAndWait(
            engine: engine,
            bottle: bottle,
            arguments: [installer.path] + silentInstallerArguments
        )

        guard isSteamInstalled(in: bottle) else {
            throw LaunchError.steamMissingAfterInstall
        }
        await progress(.init(stage: .launching, fraction: 0.94, detail: "Opening Steam…"))
        try launchSteam(in: bottle, using: engine)
        await progress(.init(
            stage: .ready,
            fraction: 1,
            detail: "Steam is installed; its updater is opening"
        ))
    }

    static func launchSteam(
        in bottle: Bottle,
        using engine: Engine,
        graphicsBackend: GraphicsBackend = .automatic,
        displayProfile: DisplayProfile? = nil
    ) throws {
        if engine.kind == .crossover {
            try openEngineApp(for: engine)
            return
        }
        guard engine.kind != .whisky else {
            NSWorkspace.shared.open(engine.executableURL)
            return
        }
        let steamPath = steamExecutableURL(in: bottle).path
        guard isSteamInstalled(in: bottle) else {
            throw LaunchError.steamMissing
        }
        try stopBottleProcesses(in: bottle, using: engine)
        if let displayProfile {
            try applyDisplayProfile(displayProfile, in: bottle, using: engine)
            try stopBottleProcesses(in: bottle, using: engine)
        }
        if isSikarugir(engine) {
            clearSteamWebCaches(in: bottle)
        }
        try run(
            engine: engine,
            bottle: bottle,
            arguments: [steamPath] + steamArguments(for: engine),
            graphicsBackend: graphicsBackend
        )
    }

    static func repairAndLaunchSteam(
        in bottle: Bottle,
        using engine: Engine,
        graphicsBackend: GraphicsBackend = .automatic,
        displayProfile: DisplayProfile? = nil
    ) throws {
        guard engine.kind != .crossover, engine.kind != .whisky else {
            try launchSteam(
                in: bottle,
                using: engine,
                graphicsBackend: graphicsBackend,
                displayProfile: displayProfile
            )
            return
        }
        try stopBottleProcesses(in: bottle, using: engine)
        clearSteamWebCaches(in: bottle)
        try launchSteam(
            in: bottle,
            using: engine,
            graphicsBackend: graphicsBackend,
            displayProfile: displayProfile
        )
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

    static func steamExecutableURL(in bottle: Bottle) -> URL {
        URL(fileURLWithPath: bottle.path, isDirectory: true)
            .appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
    }

    static func isSteamInstalled(in bottle: Bottle, fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: steamExecutableURL(in: bottle).path)
    }

    static func validateSteamInstaller(at url: URL) throws {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size >= minimumSteamInstallerSize,
              let handle = try? FileHandle(forReadingFrom: url) else {
            throw LaunchError.invalidInstaller
        }
        defer { try? handle.close() }
        guard (try? handle.read(upToCount: 2)) == Data([0x4d, 0x5a]) else {
            throw LaunchError.invalidInstaller
        }
    }

    private static func downloadSteamInstaller(
        to destination: URL,
        progress: @escaping @MainActor @Sendable (SteamInstallProgress) -> Void
    ) async throws {
        await progress(.init(
            stage: .connecting,
            fraction: nil,
            detail: "Connecting to Valve’s download server. This can take up to 30 seconds…"
        ))
        let downloader = SteamInstallerDownloadDelegate(
            destination: destination,
            progress: progress
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(
            configuration: configuration,
            delegate: downloader,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        try await downloader.download(steamInstallerURL, using: session)
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

    private static func run(
        engine: Engine,
        bottle: Bottle,
        arguments: [String],
        graphicsBackend: GraphicsBackend = .wineD3D
    ) throws {
        let process = configuredProcess(
            engine: engine,
            bottle: bottle,
            arguments: arguments,
            graphicsBackend: graphicsBackend
        )
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
        arguments: [String],
        graphicsBackend: GraphicsBackend = .wineD3D
    ) -> Process {
        let process = Process()
        process.executableURL = engine.executableURL
        process.arguments = arguments
        process.environment = configuredEnvironment(
            engine: engine,
            bottle: bottle,
            graphicsBackend: graphicsBackend
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    static func steamArguments(for engine: Engine) -> [String] {
        isSikarugir(engine) ? [] : steamCompatibilityArguments
    }

    static func isSikarugir(_ engine: Engine) -> Bool {
        engine.kind == .steamBridge &&
            engine.executableURL.path.localizedCaseInsensitiveContains("Sikarugir")
    }

    static func configuredEnvironment(
        engine: Engine,
        bottle: Bottle,
        graphicsBackend: GraphicsBackend = .wineD3D,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = baseEnvironment
        environment["WINEPREFIX"] = bottle.path
        environment["WINEDEBUG"] = "-all"

        guard isSikarugir(engine) else { return environment }

        let bin = engine.executableURL.deletingLastPathComponent()
        let bundle = bin.deletingLastPathComponent()
        let runtime = bundle.deletingLastPathComponent()
        let wineLibrary = bundle.appending(path: "lib/wine", directoryHint: .isDirectory)
        let libraryPaths = [
            runtime.appending(path: "Frameworks", directoryHint: .isDirectory).path,
            runtime.path,
            bundle.appending(path: "lib", directoryHint: .isDirectory).path
        ]
        let dllPaths = [
            wineLibrary.appending(path: "x86_64-unix", directoryHint: .isDirectory).path,
            wineLibrary.appending(path: "x86_64-windows", directoryHint: .isDirectory).path,
            wineLibrary.appending(path: "i386-windows", directoryHint: .isDirectory).path
        ]

        environment["WINEESYNC"] = "1"
        environment["WINEMSYNC"] = "1"
        environment["PATH"] = joinedPath(bin.path, existing: environment["PATH"])
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = joinedPath(
            libraryPaths.joined(separator: ":"),
            existing: environment["DYLD_FALLBACK_LIBRARY_PATH"]
        )
        environment["WINEDLLPATH"] = joinedPath(
            dllPaths.joined(separator: ":"),
            existing: environment["WINEDLLPATH"]
        )
        applyGraphicsBackend(
            graphicsBackend,
            engine: engine,
            environment: &environment
        )
        #if arch(arm64)
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 {
            environment["ROSETTA_ADVERTISE_AVX"] = "1"
        }
        #endif
        return environment
    }

    static func availableGraphicsBackends(
        for engine: Engine,
        fileManager: FileManager = .default
    ) -> Set<GraphicsBackend> {
        guard isSikarugir(engine) else { return [.automatic, .wineD3D] }
        let rendererRoot = rendererRootURL(for: engine)
        var result: Set<GraphicsBackend> = [.automatic, .wineD3D]
        for backend in GraphicsBackend.allCases {
            guard let folder = backend.rendererFolderName else { continue }
            if backend == .d3dMetal,
               (!isAppleSiliconProcess ||
                   ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15) {
                continue
            }
            if backend == .dxmt, !isAppleSiliconProcess {
                continue
            }
            let renderer = rendererRoot.appending(path: folder, directoryHint: .isDirectory)
            let requiredRelativePath: String
            switch backend {
            case .d3dMetal:
                requiredRelativePath = "wine/x86_64-windows/d3d12.dll"
            case .dxmt, .dxvk:
                requiredRelativePath = "wine/x86_64-windows/d3d11.dll"
            case .d9vk:
                requiredRelativePath = "wine/x86_64-windows/d3d9.dll"
            case .automatic, .wineD3D:
                continue
            }
            if fileManager.fileExists(
                atPath: renderer.appending(path: requiredRelativePath).path
            ) {
                result.insert(backend)
            }
        }
        return result
    }

    static func resolvedGraphicsBackend(
        _ requested: GraphicsBackend,
        for engine: Engine,
        isAppleSilicon: Bool = {
            #if arch(arm64)
            true
            #else
            false
            #endif
        }(),
        operatingSystemMajorVersion: Int =
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        fileManager: FileManager = .default
    ) -> GraphicsBackend {
        let available = availableGraphicsBackends(for: engine, fileManager: fileManager)
        if requested == .automatic {
            return GraphicsBackend.recommended(
                isAppleSilicon: isAppleSilicon,
                operatingSystemMajorVersion: operatingSystemMajorVersion,
                available: available
            )
        }
        return available.contains(requested) ? requested : .wineD3D
    }

    static func displayRegistryArguments(for profile: DisplayProfile) -> [[String]] {
        [
            [
                "reg", "add", "HKCU\\Software\\Wine\\Mac Driver",
                "/v", "RetinaMode",
                "/t", "REG_SZ",
                "/d", profile.retinaModeRegistryValue,
                "/f"
            ],
            [
                "reg", "add", "HKCU\\Control Panel\\Desktop",
                "/v", "LogPixels",
                "/t", "REG_DWORD",
                "/d", String(profile.windowsDPI),
                "/f"
            ]
        ]
    }

    static func applyDisplayProfile(
        _ profile: DisplayProfile,
        in bottle: Bottle,
        using engine: Engine
    ) throws {
        guard engine.kind != .crossover, engine.kind != .whisky else { return }
        for arguments in displayRegistryArguments(for: profile) {
            let process = configuredProcess(
                engine: engine,
                bottle: bottle,
                arguments: arguments
            )
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw LaunchError.displayConfigurationFailed(process.terminationStatus)
            }
        }
    }

    private static func rendererRootURL(for engine: Engine) -> URL {
        let bin = engine.executableURL.deletingLastPathComponent()
        let bundle = bin.deletingLastPathComponent()
        let runtime = bundle.deletingLastPathComponent()
        return runtime.appending(path: "Frameworks/renderer", directoryHint: .isDirectory)
    }

    private static func applyGraphicsBackend(
        _ requested: GraphicsBackend,
        engine: Engine,
        environment: inout [String: String]
    ) {
        environment.removeValue(forKey: "WINEDLLPATH_PREPEND")
        environment.removeValue(forKey: "CX_D3DMETALPATH")
        environment.removeValue(forKey: "CX_APPLEGPT_LIBD3DSHARED_PATH")
        environment.removeValue(forKey: "CX_APPLEGPTK_LIBD3DSHARED_PATH")
        environment.removeValue(forKey: "DXMT_LOG_LEVEL")

        let backend = resolvedGraphicsBackend(requested, for: engine)
        guard let folder = backend.rendererFolderName else { return }

        let renderer = rendererRootURL(for: engine)
            .appending(path: folder, directoryHint: .isDirectory)
        environment["WINEDLLPATH_PREPEND"] = renderer
            .appending(path: "wine", directoryHint: .isDirectory).path

        if backend == .d3dMetal {
            let external = renderer.appending(path: "external", directoryHint: .isDirectory)
            let sharedLibrary = external.appending(path: "libd3dshared.dylib").path
            environment["CX_D3DMETALPATH"] = external.path
            environment["CX_APPLEGPT_LIBD3DSHARED_PATH"] = sharedLibrary
            environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = sharedLibrary
        } else if backend == .dxmt {
            environment["DXMT_LOG_LEVEL"] = "none"
        }
    }

    private static var isAppleSiliconProcess: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private static func joinedPath(_ prefix: String, existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return prefix }
        return prefix + ":" + existing
    }

    static func stopBottleProcesses(in bottle: Bottle, using engine: Engine) throws {
        let wineserver = engine.executableURL
            .deletingLastPathComponent()
            .appending(path: "wineserver")
        guard FileManager.default.isExecutableFile(atPath: wineserver.path) else { return }
        let process = Process()
        process.executableURL = wineserver
        process.arguments = ["-k"]
        process.environment = configuredEnvironment(engine: engine, bottle: bottle)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    enum LaunchError: LocalizedError {
        case downloadFailed
        case invalidInstaller
        case steamMissing
        case steamMissingAfterInstall
        case engineCouldNotOpen
        case installerFailed(Int32)
        case displayConfigurationFailed(Int32)
        case guiEngine(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "Steam’s Windows installer could not be downloaded."
            case .invalidInstaller: "The downloaded Steam installer was incomplete or invalid. Try again."
            case .steamMissing: "Steam is not installed in this bottle yet."
            case .steamMissingAfterInstall:
                "The Steam installer finished, but Steam was not found. Try Install Windows Steam again."
            case .engineCouldNotOpen: "The compatibility engine could not be opened."
            case .installerFailed(let status): "The Steam installer exited with status \(status)."
            case .displayConfigurationFailed(let status):
                "The Retina and Windows scaling settings could not be applied (status \(status))."
            case .guiEngine(let message): message
            }
        }
    }

    struct SteamInstallProgress: Equatable, Sendable {
        let stage: Stage
        let fraction: Double?
        let detail: String

        enum Stage: String, Equatable, Sendable {
            case preparing = "Preparing"
            case connecting = "Connecting"
            case downloading = "Downloading"
            case installing = "Installing"
            case launching = "Launching"
            case ready = "Ready"
        }
    }
}

private final class SteamInstallerDownloadDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable {
    private let destination: URL
    private let progress: @MainActor @Sendable (Launcher.SteamInstallProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var didFinish = false

    init(
        destination: URL,
        progress: @escaping @MainActor @Sendable (Launcher.SteamInstallProgress) -> Void
    ) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ url: URL, using session: URLSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let hasTotal = totalBytesExpectedToWrite > 0
        let downloadFraction = hasTotal
            ? min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
            : nil
        let overallFraction = downloadFraction.map { 0.05 + ($0 * 0.52) }
        let downloaded = ByteCountFormatter.string(
            fromByteCount: totalBytesWritten,
            countStyle: .file
        )
        let detail: String
        if hasTotal {
            let total = ByteCountFormatter.string(
                fromByteCount: totalBytesExpectedToWrite,
                countStyle: .file
            )
            detail = "Steam installer: \(downloaded) of \(total)"
        } else {
            detail = "Steam installer: \(downloaded) downloaded"
        }
        Task { @MainActor [progress] in
            progress(.init(stage: .downloading, fraction: overallFraction, detail: detail))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            finish(.failure(Launcher.LaunchError.downloadFailed))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
