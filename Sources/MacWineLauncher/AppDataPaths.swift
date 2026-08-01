import Foundation

enum AppDataPaths {
    static let currentFolderName = "Mac Wine Launcher"
    static let legacyFolderName = "SteamBridge"

    static func supportRoot(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) -> URL {
        let support = supportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let current = support.appending(
            path: currentFolderName,
            directoryHint: .isDirectory
        )
        let legacy = support.appending(
            path: legacyFolderName,
            directoryHint: .isDirectory
        )

        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return current
        }

        do {
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            // Another startup may have completed the migration first.
            return fileManager.fileExists(atPath: current.path) ? current : legacy
        }
    }

    static func legacySupportRoot(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) -> URL {
        let support = supportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appending(path: legacyFolderName, directoryHint: .isDirectory)
    }
}
