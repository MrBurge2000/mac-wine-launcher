import Foundation

enum RuntimeInstaller {
    static let releasesURL = URL(
        string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases?per_page=20"
    )!

    static func install(
        fileManager: FileManager = .default,
        progress: @escaping @MainActor @Sendable (InstallProgress) -> Void = { _ in }
    ) async throws {
        try ensurePlatformRuntime()
        await progress(.init(stage: .checking, fraction: 0.02, detail: "Checking available Wine releases…"))
        var request = URLRequest(url: releasesURL)
        request.setValue("SteamBridge/0.2", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallError.releaseLookupFailed
        }
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let asset = preferredAsset(in: releases) else {
            throw InstallError.noCompatibleAsset
        }

        await progress(.init(stage: .downloading, fraction: 0.05, detail: "Starting \(asset.name)…"))
        let archive = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)-\(asset.name)")
        let downloader = DownloadDelegate(destination: archive, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer {
            session.finishTasksAndInvalidate()
            try? fileManager.removeItem(at: archive)
        }
        try await downloader.download(asset.browserDownloadURL, using: session)

        let root = EngineDiscovery.managedRuntimeRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        await progress(.init(
            stage: .extracting,
            fraction: 0.92,
            detail: "Extracting the runtime. This can take another minute…"
        ))
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xJf", archive.path, "-C", root.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError.extractionFailed }
        }.value

        guard EngineDiscovery.discover(fileManager: fileManager).contains(where: {
            $0.kind == .steamBridge
        }) else {
            throw InstallError.runtimeNotFound
        }
        await progress(.init(stage: .ready, fraction: 1, detail: "Runtime ready"))
    }

    static func preferredAsset(in releases: [Release]) -> Asset? {
        let assets = releases.flatMap(\.assets).filter {
            $0.name.hasSuffix(".tar.xz") && (
                $0.name.localizedCaseInsensitiveContains("wine-stable") ||
                $0.name.localizedCaseInsensitiveContains("wine-staging")
            )
        }
        return assets.first {
            $0.name.localizedCaseInsensitiveContains("wine-staging")
        } ?? assets.first
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

    struct Release: Decodable, Sendable {
        let assets: [Asset]
    }

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    struct InstallProgress: Equatable, Sendable {
        let stage: Stage
        let fraction: Double?
        let detail: String

        enum Stage: String, Sendable {
            case checking = "Checking"
            case downloading = "Downloading"
            case extracting = "Extracting"
            case ready = "Ready"
        }
    }

    enum InstallError: LocalizedError {
        case releaseLookupFailed
        case noCompatibleAsset
        case downloadFailed
        case extractionFailed
        case runtimeNotFound
        case rosettaRequired

        var errorDescription: String? {
            switch self {
            case .releaseLookupFailed: "The Wine release list could not be loaded."
            case .noCompatibleAsset: "No compatible macOS Wine package was found."
            case .downloadFailed: "The Wine runtime download failed."
            case .extractionFailed: "The Wine runtime could not be extracted."
            case .runtimeNotFound: "The archive was extracted, but its Wine executable was not found."
            case .rosettaRequired:
                "Rosetta 2 is required on Apple Silicon. In Terminal, run: softwareupdate --install-rosetta"
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @MainActor @Sendable (RuntimeInstaller.InstallProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    init(
        destination: URL,
        progress: @escaping @MainActor @Sendable (RuntimeInstaller.InstallProgress) -> Void
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
        let knownTotal = totalBytesExpectedToWrite > 0
        let downloadFraction = knownTotal
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : nil
        let overallFraction = downloadFraction.map { 0.05 + (min(max($0, 0), 1) * 0.83) }
        let downloaded = ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)
        let detail: String
        if knownTotal {
            let total = ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)
            detail = "\(downloaded) of \(total)"
        } else {
            detail = "\(downloaded) downloaded"
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
