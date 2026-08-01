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
        let current = support.appending(
            path: currentFolderName,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: current.path),
              let entries = try? fileManager.contentsOfDirectory(
                at: support,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return current
        }

        let candidates = entries.filter { entry in
            entry.standardizedFileURL != current.standardizedFileURL &&
                fileManager.fileExists(atPath: entry.appending(path: "bottles.json").path) &&
                fileManager.fileExists(
                    atPath: entry.appending(
                        path: "Runtime/Sikarugir/wswine.bundle",
                        directoryHint: .isDirectory
                    ).path
                )
        }
        guard candidates.count == 1 else { return current }

        do {
            try fileManager.moveItem(at: candidates[0], to: current)
        } catch {
            return fileManager.fileExists(atPath: current.path) ? current : candidates[0]
        }
        return current
    }
}
