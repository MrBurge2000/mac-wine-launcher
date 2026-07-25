import Foundation

enum EngineDiscovery {
    static func discover(fileManager: FileManager = .default) -> [Engine] {
        var candidates = managedRuntimeCandidates(fileManager: fileManager) + [
            (.crossover, "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
            (.crossover, NSHomeDirectory() + "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
            (.wine, "/opt/homebrew/bin/wine64"),
            (.wine, "/opt/homebrew/bin/wine"),
            (.wine, "/usr/local/bin/wine64"),
            (.wine, "/usr/local/bin/wine"),
            (.whisky, "/Applications/Whisky.app/Contents/MacOS/Whisky")
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for folder in path.split(separator: ":") {
                candidates.append((.wine, "\(folder)/wine64"))
                candidates.append((.wine, "\(folder)/wine"))
            }
        }

        var seen = Set<String>()
        return candidates.compactMap { kind, path in
            guard fileManager.isExecutableFile(atPath: path), seen.insert(path).inserted else {
                return nil
            }
            return Engine(kind: kind, executableURL: URL(fileURLWithPath: path))
        }.sorted { left, right in
            if left.kind.preferenceRank != right.kind.preferenceRank {
                return left.kind.preferenceRank < right.kind.preferenceRank
            }
            if left.kind == .steamBridge {
                return runtimePreference(for: left.executableURL.path) <
                    runtimePreference(for: right.executableURL.path)
            }
            return left.executableURL.path < right.executableURL.path
        }
    }

    static func managedRuntimeRoot(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SteamBridge/Runtime", directoryHint: .isDirectory)
    }

    private static func managedRuntimeCandidates(fileManager: FileManager) -> [(EngineKind, String)] {
        let root = managedRuntimeRoot(fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [(EngineKind, String)] = []
        for case let url as URL in enumerator {
            guard ["wine64", "wine"].contains(url.lastPathComponent),
                  url.path.contains("/bin/"),
                  fileManager.isExecutableFile(atPath: url.path) else { continue }
            results.append((.steamBridge, url.path))
        }
        return results.sorted { left, right in
            runtimePreference(for: left.1) < runtimePreference(for: right.1)
        }
    }

    static func runtimePreference(for path: String) -> Int {
        if path.localizedCaseInsensitiveContains("/Sikarugir/wswine.bundle/bin/wine") {
            return 0
        }
        if path.localizedCaseInsensitiveContains("Sikarugir") {
            return 5
        }
        let stagingPenalty = path.localizedCaseInsensitiveContains("staging") ? 20 : 30
        let architecturePenalty = path.hasSuffix("/wine64") ? 0 : 1
        return stagingPenalty + architecturePenalty
    }
}
