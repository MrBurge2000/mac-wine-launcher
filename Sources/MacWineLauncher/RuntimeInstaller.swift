import CryptoKit
import Foundation

enum RuntimeInstaller {
    static let currentVersion = "WS12WineSikarugir10.0_6+Template-1.0.11+WineICU-72.1"
    static let runtimeFolderName = "Sikarugir"
    static let versionFileName = ".mac-wine-launcher-runtime-version"
    static let wineICUVersion = "72.1"
    static let wineICUFolderName = "WineICU"

    static let engineAsset = Asset(
        name: "WS12WineSikarugir10.0_6.tar.xz",
        browserDownloadURL: URL(
            string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz"
        )!,
        sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2"
    )

    static let supportAsset = Asset(
        name: "Template-1.0.11.tar.xz",
        browserDownloadURL: URL(
            string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz"
        )!,
        sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a"
    )

    static let wineICUX64Asset = Asset(
        name: "wine-icu-72.1-x86_64-artifacts.zip",
        browserDownloadURL: URL(
            string: "https://gitlab.winehq.org/wine/wine-icu/-/jobs/artifacts/65cb37fe5d8eb867a3968a333e728fb1f7a918f7/download?job=build-zip-x86_64"
        )!,
        sha256: "22b1d21f8dc863810cf823f31fa0fa664c734e97604b059a41e1cfd6121e0209"
    )

    static let wineICUX86Asset = Asset(
        name: "wine-icu-72.1-x86-artifacts.zip",
        browserDownloadURL: URL(
            string: "https://gitlab.winehq.org/wine/wine-icu/-/jobs/artifacts/65cb37fe5d8eb867a3968a333e728fb1f7a918f7/download?job=build-zip-x86"
        )!,
        sha256: "cdcbe53812d15637bf4a501cf248e41e47f753d4488d3ba8a49553421664a1a7"
    )

    static func install(
        fileManager: FileManager = .default,
        progress: @escaping @MainActor @Sendable (InstallProgress) -> Void = { _ in }
    ) async throws {
        try ensurePlatformRuntime()
        await progress(.init(stage: .checking, fraction: 0.01, detail: "Checking the gaming runtime…"))

        if isCurrentRuntimeInstalled(fileManager: fileManager) {
            await progress(.init(stage: .ready, fraction: 1, detail: "Gaming runtime is already current"))
            return
        }

        let installedRoot = currentRuntimeRoot(fileManager: fileManager)
        if hasCoreRuntimeFiles(at: installedRoot, fileManager: fileManager) {
            try await installWineICU(
                into: installedRoot,
                fileManager: fileManager,
                fractionRange: 0.03...0.96,
                progress: progress
            )
            try writeVersionMarker(in: installedRoot)
            guard isCurrentRuntimeInstalled(fileManager: fileManager) else {
                throw InstallError.runtimeNotFound
            }
            await progress(.init(
                stage: .ready,
                fraction: 1,
                detail: "Windows app compatibility components ready"
            ))
            return
        }

        let engineArchive = fileManager.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-\(engineAsset.name)")
        let supportArchive = fileManager.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-\(supportAsset.name)")
        defer {
            try? fileManager.removeItem(at: engineArchive)
            try? fileManager.removeItem(at: supportArchive)
        }

        try await download(
            engineAsset,
            to: engineArchive,
            fractionRange: 0.03...0.62,
            label: "Gaming engine",
            progress: progress
        )
        try verify(engineAsset, at: engineArchive)

        try await download(
            supportAsset,
            to: supportArchive,
            fractionRange: 0.62...0.88,
            label: "macOS support libraries",
            progress: progress
        )
        try verify(supportAsset, at: supportArchive)

        let root = EngineDiscovery.managedRuntimeRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        let engineExtraction = staging.appending(path: "engine", directoryHint: .isDirectory)
        let supportExtraction = staging.appending(path: "support", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: engineExtraction, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: supportExtraction, withIntermediateDirectories: true)

        await progress(.init(
            stage: .extracting,
            fraction: 0.90,
            detail: "Extracting the gaming engine…"
        ))
        try await extract(engineArchive, to: engineExtraction)

        await progress(.init(
            stage: .extracting,
            fraction: 0.94,
            detail: "Preparing macOS graphics and font libraries…"
        ))
        try await extract(supportArchive, to: supportExtraction)

        let engineBundle = engineExtraction.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        let frameworks = supportExtraction
            .appending(path: "Template-1.0.11.app/Contents/Frameworks", directoryHint: .isDirectory)
        guard fileManager.isExecutableFile(atPath: engineBundle.appending(path: "bin/wine").path),
              fileManager.fileExists(atPath: frameworks.path) else {
            throw InstallError.runtimeNotFound
        }

        let assembled = staging.appending(path: runtimeFolderName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: assembled, withIntermediateDirectories: true)
        try fileManager.moveItem(
            at: engineBundle,
            to: assembled.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        )
        try fileManager.copyItem(
            at: frameworks,
            to: assembled.appending(path: "Frameworks", directoryHint: .isDirectory)
        )
        try await installWineICU(
            into: assembled,
            fileManager: fileManager,
            fractionRange: 0.945...0.985,
            progress: progress
        )
        try writeVersionMarker(in: assembled)

        await progress(.init(stage: .installing, fraction: 0.99, detail: "Activating the new runtime…"))
        try replaceRuntime(with: assembled, in: root, fileManager: fileManager)

        guard isCurrentRuntimeInstalled(fileManager: fileManager) else {
            throw InstallError.runtimeNotFound
        }
        await progress(.init(stage: .ready, fraction: 1, detail: "Gaming runtime ready"))
    }

    static func currentRuntimeRoot(fileManager: FileManager = .default) -> URL {
        EngineDiscovery.managedRuntimeRoot(fileManager: fileManager)
            .appending(path: runtimeFolderName, directoryHint: .isDirectory)
    }

    static func currentRuntimeExecutable(fileManager: FileManager = .default) -> URL {
        currentRuntimeRoot(fileManager: fileManager)
            .appending(path: "wswine.bundle/bin/wine")
    }

    static func isCurrentRuntimeInstalled(fileManager: FileManager = .default) -> Bool {
        let root = currentRuntimeRoot(fileManager: fileManager)
        guard hasCoreRuntimeFiles(at: root, fileManager: fileManager),
              isWineICUInstalled(at: root, fileManager: fileManager) else {
            return false
        }
        guard let value = try? String(
            contentsOf: root.appending(path: versionFileName),
            encoding: .utf8
        ) else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines) == currentVersion
    }

    static func isCurrentRuntime(_ engine: Engine, fileManager: FileManager = .default) -> Bool {
        guard engine.kind == .managedWine else { return false }
        return engine.executableURL.standardizedFileURL.path ==
            currentRuntimeExecutable(fileManager: fileManager).standardizedFileURL.path
    }

    static func wineICURoot(fileManager: FileManager = .default) -> URL {
        currentRuntimeRoot(fileManager: fileManager)
            .appending(path: "Compatibility/\(wineICUFolderName)", directoryHint: .isDirectory)
    }

    static func isWineICUInstalled(
        at runtimeRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = (runtimeRoot ?? currentRuntimeRoot(fileManager: fileManager))
            .appending(path: "Compatibility/\(wineICUFolderName)", directoryHint: .isDirectory)
        guard let marker = try? String(
            contentsOf: root.appending(path: "VERSION"),
            encoding: .utf8
        ), marker.trimmingCharacters(in: .whitespacesAndNewlines) == wineICUVersion else {
            return false
        }
        return ["x86_64", "x86"].allSatisfy { architecture in
            let directory = root.appending(path: architecture, directoryHint: .isDirectory)
            return ["icuuc72.dll", "icuin72.dll", "icudt72.dll"].allSatisfy {
                fileManager.fileExists(atPath: directory.appending(path: $0).path)
            }
        }
    }

    private static func download(
        _ asset: Asset,
        to destination: URL,
        fractionRange: ClosedRange<Double>,
        label: String,
        progress: @escaping @MainActor @Sendable (InstallProgress) -> Void
    ) async throws {
        await progress(.init(
            stage: .downloading,
            fraction: fractionRange.lowerBound,
            detail: "Starting \(label)…"
        ))
        let downloader = DownloadDelegate(
            destination: destination,
            fractionRange: fractionRange,
            label: label,
            progress: progress
        )
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await downloader.download(asset.browserDownloadURL, using: session)
    }

    private static func verify(_ asset: Asset, at archive: URL) throws {
        guard let data = try? Data(contentsOf: archive, options: .mappedIfSafe) else {
            throw InstallError.downloadFailed
        }
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == asset.sha256 else {
            throw InstallError.checksumMismatch
        }
    }

    private static func extract(_ archive: URL, to destination: URL) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xJf", archive.path, "-C", destination.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw InstallError.extractionFailed
            }
        }.value
    }

    private static func extractZip(_ archive: URL, to destination: URL) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, destination.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw InstallError.extractionFailed
            }
        }.value
    }

    private static func installWineICU(
        into runtimeRoot: URL,
        fileManager: FileManager,
        fractionRange: ClosedRange<Double>,
        progress: @escaping @MainActor @Sendable (InstallProgress) -> Void
    ) async throws {
        let compatibilityRoot = runtimeRoot.appending(
            path: "Compatibility",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: compatibilityRoot,
            withIntermediateDirectories: true
        )
        let staging = compatibilityRoot.appending(
            path: ".wine-icu-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let assets = [
            ("x86_64", wineICUX64Asset),
            ("x86", wineICUX86Asset)
        ]
        for (index, item) in assets.enumerated() {
            let (architecture, asset) = item
            let itemWidth = (fractionRange.upperBound - fractionRange.lowerBound) /
                Double(assets.count)
            let itemLowerBound = fractionRange.lowerBound + (Double(index) * itemWidth)
            let downloadUpperBound = itemLowerBound + (itemWidth * 0.78)
            let archive = fileManager.temporaryDirectory
                .appending(path: "\(UUID().uuidString)-\(asset.name)")
            let outerExtraction = staging.appending(
                path: "outer-\(architecture)",
                directoryHint: .isDirectory
            )
            let innerExtraction = staging.appending(
                path: "inner-\(architecture)",
                directoryHint: .isDirectory
            )
            defer { try? fileManager.removeItem(at: archive) }

            try await download(
                asset,
                to: archive,
                fractionRange: itemLowerBound...downloadUpperBound,
                label: "Windows \(architecture) Unicode support",
                progress: progress
            )
            try verify(asset, at: archive)
            try fileManager.createDirectory(
                at: outerExtraction,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: innerExtraction,
                withIntermediateDirectories: true
            )
            await progress(.init(
                stage: .extracting,
                fraction: downloadUpperBound,
                detail: "Preparing Windows \(architecture) Unicode support…"
            ))
            try await extractZip(archive, to: outerExtraction)
            let innerArchive = outerExtraction.appending(
                path: "build/wine-icu-\(wineICUVersion)-\(architecture).zip"
            )
            guard fileManager.fileExists(atPath: innerArchive.path) else {
                throw InstallError.runtimeNotFound
            }
            try await extractZip(innerArchive, to: innerExtraction)
            let extracted = innerExtraction.appending(
                path: "wine-icu-\(wineICUVersion)-\(architecture)",
                directoryHint: .isDirectory
            )
            guard ["icuuc72.dll", "icuin72.dll", "icudt72.dll"].allSatisfy({
                fileManager.fileExists(atPath: extracted.appending(path: $0).path)
            }) else {
                throw InstallError.runtimeNotFound
            }
            try fileManager.moveItem(
                at: extracted,
                to: staging.appending(path: architecture, directoryHint: .isDirectory)
            )
        }

        try Data((wineICUVersion + "\n").utf8).write(
            to: staging.appending(path: "VERSION"),
            options: .atomic
        )
        let destination = compatibilityRoot.appending(
            path: wineICUFolderName,
            directoryHint: .isDirectory
        )
        let backup = compatibilityRoot.appending(
            path: ".previous-wine-icu-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            if hadExisting {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if hadExisting, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private static func hasCoreRuntimeFiles(
        at root: URL,
        fileManager: FileManager
    ) -> Bool {
        fileManager.isExecutableFile(
            atPath: root.appending(path: "wswine.bundle/bin/wine").path
        ) && fileManager.fileExists(
            atPath: root.appending(path: "Frameworks", directoryHint: .isDirectory).path
        )
    }

    private static func writeVersionMarker(in runtimeRoot: URL) throws {
        try Data((currentVersion + "\n").utf8).write(
            to: runtimeRoot.appending(path: versionFileName),
            options: .atomic
        )
    }

    private static func replaceRuntime(
        with assembled: URL,
        in root: URL,
        fileManager: FileManager
    ) throws {
        let destination = root.appending(path: runtimeFolderName, directoryHint: .isDirectory)
        let backup = root.appending(path: ".previous-\(UUID().uuidString)", directoryHint: .isDirectory)
        let hadExistingRuntime = fileManager.fileExists(atPath: destination.path)

        if hadExistingRuntime {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: assembled, to: destination)
            if hadExistingRuntime {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if hadExistingRuntime, !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private static func ensurePlatformRuntime() throws {
        #if arch(arm64)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--pkg-info", "com.apple.pkg.RosettaUpdateAuto"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.rosettaRequired
        }
        #endif
    }

    struct Asset: Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let sha256: String
    }

    struct InstallProgress: Equatable, Sendable {
        let stage: Stage
        let fraction: Double?
        let detail: String

        enum Stage: String, Sendable {
            case checking = "Checking"
            case downloading = "Downloading"
            case extracting = "Extracting"
            case installing = "Installing"
            case ready = "Ready"
        }
    }

    enum InstallError: LocalizedError {
        case downloadFailed
        case checksumMismatch
        case extractionFailed
        case runtimeNotFound
        case rosettaRequired

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "The free gaming runtime download failed."
            case .checksumMismatch: "The runtime download was damaged or did not match its trusted checksum."
            case .extractionFailed: "The free gaming runtime could not be extracted."
            case .runtimeNotFound: "The runtime files were installed, but Wine or a required Windows compatibility component was missing."
            case .rosettaRequired:
                "Rosetta 2 is required on Apple Silicon. In Terminal, run: softwareupdate --install-rosetta"
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let fractionRange: ClosedRange<Double>
    private let label: String
    private let progress: @MainActor @Sendable (RuntimeInstaller.InstallProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    init(
        destination: URL,
        fractionRange: ClosedRange<Double>,
        label: String,
        progress: @escaping @MainActor @Sendable (RuntimeInstaller.InstallProgress) -> Void
    ) {
        self.destination = destination
        self.fractionRange = fractionRange
        self.label = label
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
        let knownTotal = totalBytesExpectedToWrite > 0
        let downloadFraction = knownTotal
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        let overallFraction = downloadFraction.map {
            fractionRange.lowerBound +
                (min(max($0, 0), 1) * (fractionRange.upperBound - fractionRange.lowerBound))
        }
        let downloaded = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let detail: String
        if knownTotal {
            let total = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            detail = "\(label): \(downloaded) of \(total)"
        } else {
            detail = "\(label): \(downloaded) downloaded"
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
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw RuntimeInstaller.InstallError.downloadFailed
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(with: .success(()))
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            finish(with: .failure(error))
        }
    }

    private func finish(with result: Result<Void, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
