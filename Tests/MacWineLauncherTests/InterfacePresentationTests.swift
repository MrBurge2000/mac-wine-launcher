import AppKit
import SwiftUI
import Testing
@testable import MacWineLauncher

@Test func interfaceKeepsEveryBottleSectionAvailable() {
    #expect(BottlePage.allCases.map(\.rawValue) == [
        "Apps", "Graphics & Display", "Troubleshooting", "Bottle"
    ])
    #expect(Set(BottlePage.allCases.map(\.id)).count == BottlePage.allCases.count)
}

@Test func interfaceNamesDoNotChangeStoredRuntimeOrRendererIdentifiers() {
    #expect(LauncherInterface.engineName(.managedWine) == "Sikarugir Wine")
    #expect(EngineKind.managedWine.rawValue == "Mac Wine Launcher Wine")
    #expect(LauncherInterface.graphicsName(.automatic) == "Automatic")
    #expect(GraphicsBackend.automatic.rawValue == "automatic")
    #expect(Set(GraphicsBackend.allCases.map(LauncherInterface.graphicsName)).count == GraphicsBackend.allCases.count)
    for backend in GraphicsBackend.allCases {
        #expect(!LauncherInterface.graphicsDescription(backend).isEmpty)
    }
}

@Test func directXCoverageReflectsTheInstalledRenderers() {
    #expect(LauncherInterface.availableDirectXVersions([.automatic]) == [])
    #expect(LauncherInterface.availableDirectXVersions([.automatic, .wineD3D]) == [9, 10, 11])
    #expect(LauncherInterface.availableDirectXVersions([.dxmt]) == [10, 11])
    #expect(LauncherInterface.availableDirectXVersions([.dxvk, .d9vk]) == [9, 10, 11])
    #expect(LauncherInterface.availableDirectXVersions([.d3dMetal]) == [11, 12])
    #expect(LauncherInterface.availableDirectXVersions(GraphicsBackend.allCases) == [9, 10, 11, 12])
}

@Test func interfacePreservesEveryDisplayChoice() {
    #expect(Set(DisplayProfile.allCases.map(LauncherInterface.displayName)).count == DisplayProfile.allCases.count)
    #expect(LauncherInterface.displayName(.standard) == "Match screen (recommended)")
    #expect(DisplayProfile.standard.retinaModeRegistryValue == "N")
    #expect(DisplayProfile.retinaRecommended.windowsDPI == 192)
    #expect(DisplayProfile.retinaCompact.windowsDPI == 144)
    for profile in DisplayProfile.allCases {
        #expect(!LauncherInterface.displayDescription(profile).isEmpty)
    }
}

@Test func compatibilityGuidanceUsesTheVisibleRendererName() {
    let assessment = GameCompatibility.assess(title: "Example", notes: "DX11 single player")
    let explanation = LauncherInterface.compatibilityExplanation(assessment)
    #expect(explanation.contains("Automatic"))
    #expect(!explanation.contains("AAA Auto"))
    #expect(assessment.recommendedBackend == .automatic)
    #expect(assessment.rating == .likely)
}

@Test @MainActor func interfaceSymbolsExistOnTheTestSystem() {
    for name in ["shippingbox", "shippingbox.and.arrow.backward", "gamecontroller", "app", "app.dashed", "cpu", "display", "wrench.and.screwdriver", "checkmark.shield", "puzzlepiece.extension", "power", "trash"] {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
    }
}

@Test @MainActor func progressFeedbackKeepsACompactIntrinsicHeight() {
    for fraction: Double? in [nil, 0.42] {
        let feedback = LauncherProgressView(
            title: "Steam started. Waiting for its interface…",
            fraction: fraction,
            detail: "The current operation stays visible above the bottle sections."
        )
        .frame(width: 640)
        let host = NSHostingView(rootView: feedback)
        #expect(host.fittingSize.height > 0)
        #expect(host.fittingSize.height < 100)
    }
}
