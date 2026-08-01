import Foundation

enum AppDataPaths {
    static let currentFolderName = "Mac Wine Launcher"

    static func supportRoot(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) -> URL {
        let support = supportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appending(
            path: currentFolderName,
            directoryHint: .isDirectory
        )
    }
}
