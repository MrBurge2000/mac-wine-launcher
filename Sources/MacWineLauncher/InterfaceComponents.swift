import SwiftUI

enum BottlePage: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case graphics = "Graphics & Display"
    case troubleshooting = "Troubleshooting"
    case bottle = "Bottle"

    var id: String { rawValue }
}

enum LauncherInterface {
    static func engineName(_ kind: EngineKind) -> String {
        switch kind {
        case .managedWine: "Sikarugir Wine"
        case .crossover: "CrossOver"
        case .wine: "Wine"
        case .whisky: "Whisky"
        }
    }

    static func graphicsName(_ backend: GraphicsBackend) -> String {
        backend == .automatic ? "Automatic" : backend.title
    }

    static func graphicsDescription(_ backend: GraphicsBackend) -> String {
        switch backend {
        case .automatic:
            "Chooses the best installed renderer for this Mac."
        case .d3dMetal:
            "Translates 64-bit DirectX 11 and 12 through Metal."
        case .dxmt:
            "Translates DirectX 10 and 11 through Metal."
        case .dxvk:
            "Translates DirectX 10 and 11 through Vulkan."
        case .d9vk:
            "An experimental Vulkan renderer for DirectX 9 games."
        case .wineD3D:
            "Wine’s compatibility fallback for DirectX 9–11. Useful for older games or renderer-specific problems."
        }
    }

    static func availableDirectXVersions(_ backends: [GraphicsBackend]) -> [Int] {
        var versions: Set<Int> = []
        for backend in backends {
            switch backend {
            case .automatic: break
            case .d3dMetal: versions.formUnion([11, 12])
            case .dxmt, .dxvk: versions.formUnion([10, 11])
            case .d9vk: versions.insert(9)
            case .wineD3D: versions.formUnion([9, 10, 11])
            }
        }
        return versions.sorted()
    }

    static func displayName(_ profile: DisplayProfile) -> String {
        switch profile {
        case .standard: "Match screen (recommended)"
        case .retinaRecommended: "Retina"
        case .retinaCompact: "Retina (smaller UI)"
        }
    }

    static func displayDescription(_ profile: DisplayProfile) -> String {
        switch profile {
        case .standard:
            "Uses your Mac’s logical screen resolution without Retina doubling."
        case .retinaRecommended:
            "Uses Retina resolution with 200% Windows scaling. Higher resolutions increase GPU load."
        case .retinaCompact:
            "Uses Retina resolution with 150% Windows scaling to fit more on screen. Higher resolutions increase GPU load."
        }
    }

    static func compatibilityExplanation(_ assessment: GameCompatibility) -> String {
        assessment.explanation.replacingOccurrences(
            of: GraphicsBackend.automatic.title,
            with: graphicsName(.automatic)
        )
    }
}

struct LauncherCard<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct LauncherProgressView: View {
    let title: String
    let fraction: Double?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if fraction == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                }
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if let fraction {
                    Text("\(Int(min(max(fraction, 0), 1) * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .accessibilityLabel(title)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LauncherToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityHint(detail)
        }
    }
}
