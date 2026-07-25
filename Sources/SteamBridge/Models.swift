import Foundation

enum EngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case steamBridge = "SteamBridge Wine"
    case crossover = "CrossOver"
    case wine = "Wine"
    case whisky = "Whisky"

    var id: String { rawValue }

    var preferenceRank: Int {
        switch self {
        case .steamBridge: 0
        case .crossover: 1
        case .wine: 2
        case .whisky: 3
        }
    }

    var status: String {
        switch self {
        case .steamBridge: "Free · Recommended"
        case .crossover: "Recommended"
        case .wine: "Advanced"
        case .whisky: "Unmaintained"
        }
    }
}

struct Engine: Identifiable, Hashable, Sendable {
    let kind: EngineKind
    let executableURL: URL
    var id: String { executableURL.path }
}

struct Bottle: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var engine: EngineKind
    var createdAt: Date

    init(name: String, path: String, engine: EngineKind) {
        id = UUID()
        self.name = name
        self.path = path
        self.engine = engine
        createdAt = Date()
    }
}

enum CompatibilityRating: String, Codable, Sendable {
    case unknown = "Unknown"
    case likely = "Likely"
    case limited = "Limited"
    case blocked = "Blocked"
}

struct GameCompatibility: Sendable {
    let rating: CompatibilityRating
    let explanation: String

    static func assess(title: String, notes: String) -> GameCompatibility {
        let text = "\(title) \(notes)".lowercased()
        let blockers = ["easy anti-cheat", "easyanticheat", "battleye", "vanguard", "kernel anti-cheat"]
        if blockers.contains(where: text.contains) {
            return .init(
                rating: .blocked,
                explanation: "Kernel-level or unsupported anti-cheat is a common hard blocker under Wine."
            )
        }
        if text.contains("directx 12") || text.contains("dx12") {
            return .init(
                rating: .limited,
                explanation: "DirectX 12 support varies by engine, macOS version, and Apple Silicon GPU."
            )
        }
        if text.contains("directx 11") || text.contains("dx11") || text.contains("single player") {
            return .init(
                rating: .likely,
                explanation: "This profile is often a good candidate, but it is not a guarantee."
            )
        }
        return .init(
            rating: .unknown,
            explanation: "Launch it in an isolated bottle and check community compatibility reports first."
        )
    }
}
