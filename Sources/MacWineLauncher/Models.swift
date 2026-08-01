import Foundation

enum EngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case managedWine = "Mac Wine Launcher Wine"
    case crossover = "CrossOver"
    case wine = "Wine"
    case whisky = "Whisky"

    var id: String { rawValue }

    var preferenceRank: Int {
        switch self {
        case .managedWine: 0
        case .crossover: 1
        case .wine: 2
        case .whisky: 3
        }
    }

    var status: String {
        switch self {
        case .managedWine: "Free · Recommended"
        case .crossover: "Recommended"
        case .wine: "Advanced"
        case .whisky: "Unmaintained"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "SteamBridge Wine" {
            self = .managedWine
            return
        }
        guard let kind = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown compatibility engine: \(value)"
            )
        }
        self = kind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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

struct RecentWindowsApplication: Identifiable, Codable, Equatable, Sendable {
    var path: String
    var lastLaunchedAt: Date

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum WindowsCommandLine {
    static func parse(_ commandLine: String) throws -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        let characters = Array(commandLine)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if index + 1 < characters.count {
                    let next = characters[index + 1]
                    if next == quote || (quote == nil && (next == "\"" || next == "'")) {
                        current.append(next)
                        index += 2
                        hasToken = true
                        continue
                    }
                }
                current.append(character)
                hasToken = true
                index += 1
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                hasToken = true
                index += 1
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                hasToken = true
            } else if character.isWhitespace {
                if hasToken {
                    arguments.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
            index += 1
        }

        guard quote == nil else {
            throw ParseError.unclosedQuote
        }
        if hasToken {
            arguments.append(current)
        }
        return arguments
    }

    enum ParseError: LocalizedError {
        case unclosedQuote

        var errorDescription: String? {
            "The launch arguments contain an unclosed quote."
        }
    }
}

enum CompatibilityRating: String, Codable, Sendable {
    case unknown = "Unknown"
    case likely = "Likely"
    case limited = "Limited"
    case blocked = "Blocked"
}

enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case d3dMetal
    case dxmt
    case dxvk
    case d9vk
    case wineD3D

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "AAA Auto"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .d9vk: "D9VK"
        case .wineD3D: "WineD3D"
        }
    }

    var coverage: String {
        switch self {
        case .automatic: "Best available DirectX path"
        case .d3dMetal: "64-bit DirectX 11 + 12"
        case .dxmt: "DirectX 10 + 11 through Metal"
        case .dxvk: "DirectX 10 + 11 through Vulkan"
        case .d9vk: "DirectX 9 through Vulkan"
        case .wineD3D: "DirectX 9–11 compatibility fallback"
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            "Uses D3DMetal on supported Apple Silicon Macs for modern AAA games, then falls back to the strongest installed renderer."
        case .d3dMetal:
            "The fastest first choice for many modern 64-bit AAA games, including DirectX 12 titles."
        case .dxmt:
            "A strong Metal alternative for DirectX 10 and 11 games when D3DMetal has glitches."
        case .dxvk:
            "A Vulkan-based DirectX 10 and 11 alternative that can fix renderer-specific problems."
        case .d9vk:
            "An experimental high-performance path for older DirectX 9 games."
        case .wineD3D:
            "The most conservative OpenGL/Vulkan fallback. It is slower, but useful for older or unusual games."
        }
    }

    var rendererFolderName: String? {
        switch self {
        case .automatic, .wineD3D: nil
        case .d3dMetal: "d3dmetal"
        case .dxmt: "dxmt"
        case .dxvk: "dxvk"
        case .d9vk: "d9vk"
        }
    }

    static func recommended(
        isAppleSilicon: Bool,
        operatingSystemMajorVersion: Int,
        available: Set<GraphicsBackend>
    ) -> GraphicsBackend {
        if isAppleSilicon,
           operatingSystemMajorVersion >= 15,
           available.contains(.d3dMetal) {
            return .d3dMetal
        }
        if isAppleSilicon, available.contains(.dxmt) {
            return .dxmt
        }
        if available.contains(.dxvk) {
            return .dxvk
        }
        return .wineD3D
    }
}

enum DisplayProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case retinaRecommended
    case retinaCompact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard — fastest"
        case .retinaRecommended: "Retina — recommended"
        case .retinaCompact: "Retina — smaller UI"
        }
    }

    var summary: String {
        switch self {
        case .standard: "1× resolution · 100% Windows scale"
        case .retinaRecommended: "2× resolution · 200% Windows scale"
        case .retinaCompact: "2× resolution · 150% Windows scale"
        }
    }

    var explanation: String {
        switch self {
        case .standard:
            "Best frame rate and lowest GPU load. Steam and games render at the Mac’s logical resolution."
        case .retinaRecommended:
            "Makes Steam sharp while keeping text near its normal physical size. Games can select the Mac’s higher Retina resolutions."
        case .retinaCompact:
            "Keeps Retina sharpness but fits more content in Steam by making its interface smaller."
        }
    }

    var retinaModeRegistryValue: String {
        self == .standard ? "N" : "Y"
    }

    var windowsDPI: Int {
        switch self {
        case .standard: 96
        case .retinaRecommended: 192
        case .retinaCompact: 144
        }
    }
}

enum MouseCaptureProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case menuSafe
    case gameDefault
    case forceCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuSafe: "Menu-safe — recommended"
        case .gameDefault: "Game default"
        case .forceCapture: "Force camera capture"
        }
    }

    var summary: String {
        switch self {
        case .menuSafe:
            "Stops Wine from pinning the pointer when this game opens menus."
        case .gameDefault:
            "Lets the game choose when Wine should capture and warp the pointer."
        case .forceCapture:
            "Keeps the pointer captured for camera movement in gameplay."
        }
    }

    var wineRegistryValue: String {
        switch self {
        case .menuSafe: "disable"
        case .gameDefault: "enabled"
        case .forceCapture: "force"
        }
    }
}

struct GameCompatibility: Sendable {
    let rating: CompatibilityRating
    let explanation: String
    let recommendedBackend: GraphicsBackend

    static func assess(title: String, notes: String) -> GameCompatibility {
        let text = "\(title) \(notes)".lowercased()
        let blockers = ["easy anti-cheat", "easyanticheat", "battleye", "vanguard", "kernel anti-cheat"]
        if blockers.contains(where: text.contains) {
            return .init(
                rating: .blocked,
                explanation: "Kernel-level or developer-disabled anti-cheat cannot be fixed by changing the DirectX renderer.",
                recommendedBackend: .automatic
            )
        }
        if text.contains("directx 12") || text.contains("dx12") {
            return .init(
                rating: .likely,
                explanation: "Use D3DMetal for the best available 64-bit DirectX 12 path on Apple Silicon.",
                recommendedBackend: .d3dMetal
            )
        }
        if text.contains("directx 11") || text.contains("dx11") ||
            text.contains("unreal engine") || text.contains("aaa") {
            return .init(
                rating: .likely,
                explanation: "Start with AAA Auto. If the game has visual glitches, switch to DXMT, then DXVK.",
                recommendedBackend: .automatic
            )
        }
        if text.contains("directx 10") || text.contains("dx10") {
            return .init(
                rating: .likely,
                explanation: "DXMT is the preferred Metal path for DirectX 10 and also supports DirectX 11.",
                recommendedBackend: .dxmt
            )
        }
        if text.contains("directx 9") || text.contains("dx9") || text.contains("older game") {
            return .init(
                rating: .likely,
                explanation: "Try D9VK for speed. WineD3D remains the safer fallback for unusual older games.",
                recommendedBackend: .d9vk
            )
        }
        if text.contains("single player") {
            return .init(
                rating: .likely,
                explanation: "Single-player games without anti-cheat are often good candidates for AAA Auto.",
                recommendedBackend: .automatic
            )
        }
        return .init(
            rating: .unknown,
            explanation: "Start with AAA Auto, then try DXMT, DXVK, and WineD3D if the first renderer has problems.",
            recommendedBackend: .automatic
        )
    }
}
