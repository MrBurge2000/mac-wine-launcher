import Combine
import Foundation

@MainActor
final class BottleStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []

    private let fileManager: FileManager
    private let rootURL: URL
    private let manifestURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? AppDataPaths.supportRoot(
            fileManager: fileManager,
            supportDirectory: applicationSupportURL
        )
        manifestURL = self.rootURL.appending(path: "bottles.json")
        load()
    }

    func create(name: String, engine: EngineKind) throws -> Bottle {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw StoreError.emptyName }
        let folderName = cleanName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = rootURL.appending(path: "Bottles/\(folderName)", directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: url.path) else { throw StoreError.alreadyExists }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let bottle = Bottle(name: cleanName, path: url.path, engine: engine)
        bottles.append(bottle)
        try save()
        return bottle
    }

    func uninstall(_ bottle: Bottle) async throws {
        let bottleURL = try validatedBottleURL(for: bottle)
        if fileManager.fileExists(atPath: bottleURL.path) {
            try await Task.detached {
                try FileManager.default.removeItem(at: bottleURL)
            }.value
        }
        bottles.removeAll { $0.id == bottle.id }
        try save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([Bottle].self, from: data) else { return }
        bottles = decoded
    }

    private func save() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bottles).write(to: manifestURL, options: .atomic)
    }

    private func validatedBottleURL(for bottle: Bottle) throws -> URL {
        let bottlesRoot = rootURL
            .appending(path: "Bottles", directoryHint: .isDirectory)
            .standardizedFileURL
        let bottleURL = URL(fileURLWithPath: bottle.path).standardizedFileURL
        let rootPrefix = bottlesRoot.path + "/"
        guard bottleURL.path.hasPrefix(rootPrefix) else {
            throw StoreError.unsafeLocation
        }

        let resolvedRoot = bottlesRoot.resolvingSymlinksInPath()
        let resolvedBottle = bottleURL.resolvingSymlinksInPath()
        guard resolvedBottle.path.hasPrefix(resolvedRoot.path + "/") else {
            throw StoreError.unsafeLocation
        }
        return bottleURL
    }

    enum StoreError: LocalizedError {
        case emptyName
        case alreadyExists
        case unsafeLocation

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a bottle name."
            case .alreadyExists: "A bottle with that folder name already exists."
            case .unsafeLocation: "Mac Wine Launcher refused to delete a bottle outside its managed Bottles folder."
            }
        }
    }
}
