import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: BottleStore
    @State private var engines = EngineDiscovery.discover()
    @State private var selection: Bottle.ID?
    @State private var showingNewBottle = false
    @State private var message: String?
    @State private var isInstallingRuntime = false
    @State private var runtimeProgress: RuntimeInstaller.InstallProgress?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Bottles") {
                    ForEach(store.bottles) { bottle in
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bottle.name).lineLimit(1)
                                Text(LauncherInterface.engineName(bottle.engine))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 5)
                        }
                        .tag(bottle.id)
                        .help(bottle.name)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                Button(action: { showingNewBottle = true }) {
                    Label("New Bottle", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(engines.isEmpty)
                .padding(12)
            }
            .navigationTitle("Mac Wine Launcher")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            if engines.isEmpty {
                ContentUnavailableView {
                    Label("Install the Wine Runtime", systemImage: "shippingbox.and.arrow.backward")
                } description: {
                    Text("The free Sikarugir runtime runs Windows apps in your bottles. The download is about 250 MB and usually takes 2–8 minutes.")
                } actions: {
                    if let runtimeProgress {
                        LauncherProgressView(
                            title: runtimeProgress.stage.rawValue,
                            fraction: runtimeProgress.fraction,
                            detail: runtimeProgress.detail
                        )
                        .frame(width: 320)
                    }
                    Button(isInstallingRuntime ? "Installing…" : "Install Free Runtime") {
                        installFreeRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isInstallingRuntime)
                    Button("Refresh") { engines = EngineDiscovery.discover() }
                        .buttonStyle(.link)
                }
            } else if let bottle = selectedBottle {
                BottleDetail(
                    bottle: bottle,
                    engine: matchingEngine(for: bottle),
                    refreshEngines: { engines = EngineDiscovery.discover() },
                    uninstall: {
                        try await uninstallBottle(
                            bottle,
                            using: matchingEngine(for: bottle)
                        )
                    },
                    report: { message = $0 }
                )
                .id(bottle.id)
            } else {
                ContentUnavailableView {
                    Label(store.bottles.isEmpty ? "Create a Bottle" : "Choose a Bottle", systemImage: "shippingbox")
                } description: {
                    Text("A bottle keeps its Windows apps and settings in a separate environment.")
                } actions: {
                    Button("New Bottle…") { showingNewBottle = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            if selection == nil { selection = store.bottles.first?.id }
        }
        .onChange(of: store.bottles.map(\.id)) { _, ids in
            if selection == nil || !ids.contains(where: { $0 == selection }) {
                selection = ids.first
            }
        }
        .sheet(isPresented: $showingNewBottle) {
            NewBottleView(engines: engines) { name, kind in
                do {
                    let bottle = try store.create(name: name, engine: kind)
                    selection = bottle.id
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        .alert("Mac Wine Launcher", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func installFreeRuntime() {
        isInstallingRuntime = true
        Task {
            do {
                try await RuntimeInstaller.install { update in
                    runtimeProgress = update
                }
                engines = EngineDiscovery.discover()
                message = "Mac Wine Launcher Wine is installed. Create a bottle to install Windows Steam."
            } catch {
                message = error.localizedDescription
                runtimeProgress = nil
            }
            isInstallingRuntime = false
        }
    }

    private var selectedBottle: Bottle? {
        store.bottles.first { $0.id == selection }
    }

    private func matchingEngine(for bottle: Bottle) -> Engine? {
        engines.first { $0.kind == bottle.engine } ?? engines.first
    }

    private func uninstallBottle(_ bottle: Bottle, using engine: Engine?) async throws {
        if let engine, engine.kind != .crossover, engine.kind != .whisky {
            try Launcher.stopBottleProcesses(in: bottle, using: engine)
        }
        try await store.uninstall(bottle)
        if selection == bottle.id {
            selection = nil
        }
    }
}

private struct NewBottleView: View {
    let engines: [Engine]
    let onCreate: (String, EngineKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Windows Steam"
    @State private var engine: EngineKind

    init(engines: [Engine], onCreate: @escaping (String, EngineKind) -> Void) {
        self.engines = engines
        self.onCreate = onCreate
        _engine = State(initialValue: engines.first?.kind ?? .wine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("New Bottle", systemImage: "shippingbox")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 16) {
                TextField("Bottle name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Runtime", selection: $engine) {
                    ForEach(availableKinds) { kind in
                        Text("\(LauncherInterface.engineName(kind)) — \(kind.status)").tag(kind)
                    }
                }
                Text(engine == .crossover
                     ? "CrossOver’s installer creates and configures the Windows environment."
                     : "Each bottle has its own Windows apps and settings. The managed Wine runtime is free.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(name, engine)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var availableKinds: [EngineKind] {
        Array(Set(engines.map(\.kind))).sorted { $0.preferenceRank < $1.preferenceRank }
    }
}

private struct BottleDetail: View {
    let bottle: Bottle
    let engine: Engine?
    let refreshEngines: () -> Void
    let uninstall: () async throws -> Void
    let report: (String) -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var assessment: GameCompatibility?
    @State private var isWorking = false
    @State private var isUninstalling = false
    @State private var showingUninstallConfirmation = false
    @State private var showingStopConfirmation = false
    @State private var showingKnownGameFixDetails = false
    @State private var runtimeProgress: RuntimeInstaller.InstallProgress?
    @State private var steamProgress: Launcher.SteamInstallProgress?
    @State private var operationStatus: String?
    @State private var cleanupWarning: String?
    @State private var graphicsBackend: GraphicsBackend = .automatic
    @State private var displayProfile: DisplayProfile = .standard
    @State private var mouseCaptureProfile: MouseCaptureProfile = .menuSafe
    @State private var windowsArguments = ""
    @State private var recentWindowsApplications: [RecentWindowsApplication] = []
    @State private var page: BottlePage = .apps
    @AppStorage(MacWineLauncherAppDelegate.stopWineOnQuitKey)
    private var stopWineOnQuit = true
    @AppStorage("startSteamMinimized") private var startSteamMinimized = false

    var body: some View {
        // Keep status updates inside the split pane instead of growing the window's minimum size.
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let cleanupWarning {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(cleanupWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    switch page {
                    case .apps: appsPage
                    case .graphics: graphicsPage
                    case .troubleshooting: troubleshootingPage
                    case .bottle: bottlePage
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .id(page)
            .safeAreaInset(edge: .top, spacing: 0) {
                bottleHeader
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(bottle.name)
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: graphicsPreferenceKey),
               let backend = GraphicsBackend(rawValue: saved),
               availableGraphicsBackends.contains(backend) {
                graphicsBackend = backend
            }
            let displayMigrationKey = "screenResolutionDefault.\(bottle.id.uuidString)"
            if !UserDefaults.standard.bool(forKey: displayMigrationKey) {
                UserDefaults.standard.set(DisplayProfile.standard.rawValue, forKey: displayPreferenceKey)
                UserDefaults.standard.set(true, forKey: displayMigrationKey)
            }
            if let saved = UserDefaults.standard.string(forKey: displayPreferenceKey),
               let profile = DisplayProfile(rawValue: saved) {
                displayProfile = profile
            }
            if let saved = UserDefaults.standard.string(forKey: inputPreferenceKey),
               let profile = MouseCaptureProfile(rawValue: saved) {
                mouseCaptureProfile = profile
            }
            loadRecentWindowsApplications()
        }
        .task(id: bottle.id) {
            let exiting = await Task.detached { WineProcessLedger.unownedExitingWinePIDs() }.value
            if !exiting.isEmpty {
                cleanupWarning = "Older Wine processes are still trying to exit (\(exiting.map(String.init).joined(separator: ", "))). Their bottle cannot be verified. Save your work and restart the Mac to finish cleanup before gaming."
            }
        }
        .onChange(of: graphicsBackend) { _, newValue in
            guard UserDefaults.standard.string(forKey: graphicsPreferenceKey) != newValue.rawValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: graphicsPreferenceKey)
            operationStatus = "\(LauncherInterface.graphicsName(newValue)) will be used the next time Steam launches."
        }
        .onChange(of: displayProfile) { _, newValue in
            guard UserDefaults.standard.string(forKey: displayPreferenceKey) != newValue.rawValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: displayPreferenceKey)
            operationStatus = "\(LauncherInterface.displayName(newValue)) will be used the next time Steam launches."
        }
        .onChange(of: mouseCaptureProfile) { _, newValue in
            guard UserDefaults.standard.string(forKey: inputPreferenceKey) != newValue.rawValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: inputPreferenceKey)
            operationStatus = "\(newValue.title) will be used for the known-game mouse fix the next time Steam launches."
        }
        .alert("Uninstall “\(bottle.name)”?", isPresented: $showingUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall Bottle", role: .destructive) {
                uninstallBottle()
            }
        } message: {
            Text("This permanently deletes Windows Steam, installed games, saves stored only inside this bottle, and all other bottle files. The shared runtime is not removed.")
        }
        .confirmationDialog(
            "Stop every Windows app in this bottle?",
            isPresented: $showingStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Steam & Wine", role: .destructive) {
                stopSteamAndWine()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This closes Steam, games, SteaMidra, and every other Windows app currently running in this bottle.")
        }
    }

    private var bottleHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bottle.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text("\(engine.map { LauncherInterface.engineName($0.kind) } ?? "Runtime missing") · \(resolvedGraphicsBackend.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(action: openCDrive) {
                        Label("Open C: Drive", systemImage: "folder")
                    }
                    .help("Open this bottle’s Windows files in Finder")
                }
                Picker("Bottle section", selection: $page) {
                    ForEach(BottlePage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if isWorking || isUninstalling || runtimeProgress != nil || operationStatus != nil {
                    operationFeedback
                }
            }
            .padding(24)
            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var operationFeedback: some View {
        if let runtimeProgress {
            LauncherProgressView(
                title: runtimeProgress.stage.rawValue,
                fraction: runtimeProgress.fraction,
                detail: runtimeProgress.detail
            )
        } else if let steamProgress, isWorking {
            LauncherProgressView(
                title: steamProgress.stage.rawValue,
                fraction: steamProgress.fraction,
                detail: steamProgress.detail
            )
        } else if isWorking || isUninstalling {
            LauncherProgressView(
                title: isUninstalling ? "Uninstalling bottle…" : operationStatus ?? "Preparing…",
                fraction: nil,
                detail: ""
            )
        } else if let operationStatus {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text(operationStatus)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LauncherCard("Windows Steam", systemImage: "gamecontroller") {
                HStack(alignment: .center) {
                    Label(
                        Launcher.isSteamInstalled(in: bottle) ? "Installed in this bottle" : "Not installed in this bottle",
                        systemImage: Launcher.isSteamInstalled(in: bottle) ? "checkmark.circle" : "arrow.down.circle"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    if Launcher.isSteamInstalled(in: bottle) || engine?.kind == .crossover {
                        Button(engine?.kind == .crossover ? "Open CrossOver" : "Launch Steam", action: launch)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!canLaunchSteam)
                    } else {
                        Button(installButtonTitle, action: install)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(engine == nil || isWorking)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    if Launcher.isSteamInstalled(in: bottle) || engine?.kind == .crossover {
                        Button(installButtonTitle, action: install)
                            .disabled(engine == nil || isWorking)
                    }
                    if supportsManagedActions {
                        Button("Stop Steam & Wine…") { showingStopConfirmation = true }
                            .disabled(isWorking)
                    }
                }
            }
            LauncherCard("Windows Apps", systemImage: "app") {
                HStack(alignment: .top, spacing: 20) {
                    Text("Run an app or installer in this bottle.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Run App or Installer…", action: chooseWindowsApplication)
                        .help("Choose a Windows .exe, .msi, .com, .bat or .cmd file")
                        .disabled(engine == nil || isWorking || engine?.kind == .crossover || engine?.kind == .whisky)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Launch arguments").font(.subheadline)
                    TextField("Optional, e.g. --safe-mode \"My File\"", text: $windowsArguments)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Launch arguments")
                }
                Text("Supports .exe, .msi, .com, .bat and .cmd. Windows Installer handles .msi files automatically. Renderer: \(resolvedGraphicsBackend.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !recentWindowsApplications.isEmpty {
                    Divider()
                    HStack {
                        Text("Recent apps").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Clear") {
                            recentWindowsApplications = []
                            saveRecentWindowsApplications()
                        }
                        .buttonStyle(.link)
                        .help("Clear the recent-app list without deleting files")
                    }
                    ForEach(recentWindowsApplications.prefix(5)) { application in
                        HStack(spacing: 12) {
                            Image(systemName: "app.dashed")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(application.displayName).lineLimit(1)
                                Text(application.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Button("Run") {
                                runWindowsApplication(at: URL(fileURLWithPath: application.path))
                            }
                            .disabled(isWorking || !FileManager.default.fileExists(atPath: application.path))
                            .accessibilityLabel("Run \(application.displayName)")
                        }
                        .help(application.path)
                    }
                }
            }
        }
        .disabled(isUninstalling)
    }

    private var graphicsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LauncherCard("Graphics", systemImage: "cpu") {
                Picker("Renderer", selection: $graphicsBackend) {
                    ForEach(availableGraphicsBackends) { backend in
                        Text("\(LauncherInterface.graphicsName(backend)) — \(backend.coverage)").tag(backend)
                    }
                }
                LabeledContent("Active renderer", value: resolvedGraphicsBackend.title)
                Text(LauncherInterface.graphicsDescription(graphicsBackend))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Available DirectX support") {
                    Text(LauncherInterface.availableDirectXVersions(availableGraphicsBackends)
                        .map { String($0) }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                Text("Games inherit the selected renderer when Steam launches. If a game has graphics problems, try DXMT, then DXVK, then WineD3D.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LauncherCard("Display & Resolution", systemImage: "display") {
                Picker("Display mode", selection: $displayProfile) {
                    ForEach(DisplayProfile.allCases) { profile in
                        Text(LauncherInterface.displayName(profile)).tag(profile)
                    }
                }
                LabeledContent("Windows scaling", value: displayProfile.summary)
                if let retinaResolutionSummary {
                    LabeledContent("Mac render space", value: retinaResolutionSummary)
                        .monospacedDigit()
                }
                Text(LauncherInterface.displayDescription(displayProfile))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can still choose resolution in each game’s Display settings. Lower in-game resolutions reduce GPU load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Changes take effect on the next Steam launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply & Relaunch Steam", action: launch)
                    .disabled(!canLaunchSteam)
            }
        }
        .disabled(isUninstalling)
    }

    private var troubleshootingPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if supportsManagedActions {
                LauncherCard("Steam Interface", systemImage: "wrench.and.screwdriver") {
                    Text("If Steam opens as a black window, rebuild its web-interface cache and relaunch it with the compatibility settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Fix Black Steam Window", action: repairSteam)
                        .disabled(isWorking)
                    Text("Closes Steam and clears only its web-interface cache, not installed games or saves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            knownGameFixesSection
            LauncherCard("Compatibility Check", systemImage: "checkmark.shield") {
                TextField("Game title", text: $title).textFieldStyle(.roundedBorder)
                TextField("Notes, e.g. DX12 or Easy Anti-Cheat", text: $notes).textFieldStyle(.roundedBorder)
                Button("Assess") { assessment = GameCompatibility.assess(title: title, notes: notes) }
                if let assessment {
                    Divider()
                    LabeledContent("Rating", value: assessment.rating.rawValue)
                    Text(LauncherInterface.compatibilityExplanation(assessment))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if assessment.rating != .blocked {
                        Button("Use \(LauncherInterface.graphicsName(assessment.recommendedBackend))") {
                            graphicsBackend = assessment.recommendedBackend
                        }
                    }
                }
            }
            Text("Wine cannot bypass DRM or provide Windows kernel drivers. Games that require unsupported kernel anti-cheat may not run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(isUninstalling)
    }

    private var bottlePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LauncherCard("Bottle Details", systemImage: "shippingbox") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Runtime", value: engine.map { LauncherInterface.engineName($0.kind) } ?? "Missing")
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Location").font(.subheadline)
                        Text(bottle.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bottle.path)])
                    }
                }
                if engine?.kind == .managedWine {
                    Divider()
                    HStack {
                        if let engine, RuntimeInstaller.isCurrentRuntime(engine) {
                            Label("Runtime is up to date", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Updates before Steam launches", systemImage: "arrow.down.circle")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("Update Gaming Runtime", action: updateRuntime)
                            .disabled(isWorking)
                    }
                } else if engine?.kind == .crossover {
                    Text("This bottle uses the separately installed, commercial CrossOver runtime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if supportsManagedActions {
                LauncherCard("Steam & Shutdown", systemImage: "power") {
                    LauncherToggle(
                        title: "Start Steam minimized",
                        detail: "Reduces Steam interface work while gaming. Open Steam from its tray icon when needed.",
                        isOn: $startSteamMinimized
                    )
                    Divider()
                    LauncherToggle(
                        title: "Stop Wine when the launcher quits",
                        detail: "Requests a clean shutdown of Windows apps in all managed bottles, then checks for remaining processes.",
                        isOn: $stopWineOnQuit
                    )
                }
            }
            LauncherCard("Uninstall Bottle", systemImage: "trash") {
                Text("Deletes this bottle, its Windows apps, installed games and saves stored inside it. The launcher and shared Wine runtime stay installed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Uninstall Bottle…", role: .destructive) { showingUninstallConfirmation = true }
                    .disabled(isWorking || isUninstalling)
            }
        }
        .disabled(isUninstalling)
    }

    private var supportsManagedActions: Bool {
        engine?.kind == .managedWine || engine?.kind == .wine
    }

    private var canLaunchSteam: Bool {
        engine != nil && !isWorking && (engine?.kind == .crossover || Launcher.isSteamInstalled(in: bottle))
    }

    private func openCDrive() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: bottle.path, isDirectory: true)
                .appending(path: "drive_c", directoryHint: .isDirectory)
        )
    }

    @ViewBuilder
    private var knownGameFixesSection: some View {
        if knownGameFixCount > 0 {
            LauncherCard("Known Game Bugs & Fixes", systemImage: "puzzlepiece.extension") {
                Label(
                    "\(knownGameFixCount) automatic compatibility \(knownGameFixCount == 1 ? "fix" : "fixes") active",
                    systemImage: "checkmark.shield.fill"
                )
                .foregroundStyle(.secondary)
                Text("Applied only to affected games. Open the details if a problem returns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup(
                    "Troubleshooting details",
                    isExpanded: $showingKnownGameFixDetails
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        dontPanicFixDetails
                        cyberpunkFixDetails
                        baldursGate3FixDetails
                        marvelRivalsFixDetails
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var dontPanicFixDetails: some View {
        if Launcher.isDontPanicInstalled(in: bottle) {
            LabeledContent("Game", value: "Don’t Panic! It is Just Turbulence")
            LabeledContent(
                "Known bug",
                value: "Pointer can become trapped after leaving the menu"
            )
            LabeledContent("Fix status", value: "Applied automatically")
            Picker("Mouse mode", selection: $mouseCaptureProfile) {
                ForEach(MouseCaptureProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            Text(mouseCaptureProfile.summary)
                .foregroundStyle(.secondary)
            Button("Reapply Fix & Relaunch Steam") { launch() }
                .disabled(engine == nil || isWorking)
            Text("If the pointer becomes trapped again, press ⌥↩ to toggle window mode, then ⌘Tab back to Mac Wine Launcher and try another mouse mode here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cyberpunkFixDetails: some View {
        if Launcher.isCyberpunkInstalled(in: bottle) {
            if Launcher.isDontPanicInstalled(in: bottle) { Divider() }
            LabeledContent("Game", value: "Cyberpunk 2077")
            LabeledContent(
                "Known bug",
                value: "REDlauncher can fail to create an OpenGL context"
            )
            LabeledContent(
                "Fix status",
                value: "Applied automatically; manual launch available"
            )
            Button("Launch Cyberpunk 2077 (Skip REDlauncher)") { launchCyberpunk() }
                .disabled(engine == nil || isWorking)
            Text("Starts the Steam copy directly with its supported launcher-skip argument. The game still uses the selected DirectX renderer and display profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var baldursGate3FixDetails: some View {
        if Launcher.isBaldursGate3Installed(in: bottle) {
            if Launcher.isDontPanicInstalled(in: bottle) ||
                Launcher.isCyberpunkInstalled(in: bottle) { Divider() }
            LabeledContent("Game", value: "Baldur’s Gate 3")
            LabeledContent(
                "Known bug",
                value: "Larian Launcher can open black or crash under Wine"
            )
            LabeledContent(
                "Fix status",
                value: "Official launcher-skip option applied automatically"
            )
            Text("Steam starts the game directly while preserving existing launch options and the selected DirectX renderer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var marvelRivalsFixDetails: some View {
        if Launcher.isMarvelRivalsInstalled(in: bottle) {
            if Launcher.isDontPanicInstalled(in: bottle) ||
                Launcher.isCyberpunkInstalled(in: bottle) ||
                Launcher.isBaldursGate3Installed(in: bottle) { Divider() }
            LabeledContent("Game", value: "Marvel Rivals")
            LabeledContent(
                "Known bug",
                value: "Wine can trigger a false AMD D3D12 driver warning"
            )
            LabeledContent("Fix status", value: "Applied automatically")
            Text("Only the false Unreal Engine warning is disabled; the renderer, graphics settings, and game files are unchanged.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func install() {
        guard engine != nil else { return }
        steamProgress = nil
        operationStatus = nil
        isWorking = true
        Task {
            do {
                let readyEngine = try await prepareEngine()
                try await Launcher.installSteam(
                    in: bottle,
                    using: readyEngine
                ) { steamProgress = $0 }
                if readyEngine.kind == .crossover {
                    report("CrossOver opened. Select Steam, click Install, and let its supported recipe configure the bottle.")
                } else {
                    operationStatus = "Steam is installed. First launch may download ~570 MB of Steam updates before sign-in."
                }
            } catch {
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func launch() {
        guard engine != nil else { return }
        steamProgress = nil
        operationStatus = "Opening Steam…"
        isWorking = true
        Task {
            do {
                let readyEngine = try await prepareEngine()
                try Launcher.launchSteam(
                    in: bottle,
                    using: readyEngine,
                    graphicsBackend: graphicsBackend,
                    displayProfile: displayProfile,
                    mouseCaptureProfile: mouseCaptureProfile
                )
                operationStatus = "Steam started. Waiting for its interface…"
                try await Launcher.waitForSteamUI(
                    in: bottle,
                    using: readyEngine
                )
                let resolved = Launcher.resolvedGraphicsBackend(
                    graphicsBackend,
                    for: readyEngine
                )
                operationStatus =
                    "Steam’s interface is running with \(resolved.title) and \(displayProfile.title)."
            } catch {
                operationStatus = nil
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func launchCyberpunk() {
        guard engine != nil else { return }
        steamProgress = nil
        operationStatus = "Starting Cyberpunk 2077 without REDlauncher…"
        isWorking = true
        Task {
            do {
                let readyEngine = try await prepareEngine()
                try Launcher.launchCyberpunk(
                    in: bottle,
                    using: readyEngine,
                    graphicsBackend: graphicsBackend,
                    displayProfile: displayProfile
                )
                operationStatus = "Steam accepted the direct game launch. Waiting for Cyberpunk 2077…"
                try await Launcher.waitForCyberpunk(
                    in: bottle,
                    using: readyEngine
                )
                operationStatus =
                    "Cyberpunk 2077 is running with \(resolvedGraphicsBackend.title)."
            } catch {
                operationStatus = nil
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func chooseWindowsApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows App or Installer"
        panel.prompt = "Run with Wine"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Launcher.supportedWindowsApplicationExtensions
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runWindowsApplication(at: url)
    }

    private func runWindowsApplication(at url: URL) {
        guard engine != nil else { return }
        operationStatus = "Opening \(url.lastPathComponent)…"
        isWorking = true
        Task {
            do {
                let arguments = try WindowsCommandLine.parse(windowsArguments)
                let readyEngine = try await prepareEngine()
                try Launcher.launchWindowsApplication(
                    at: url,
                    arguments: arguments,
                    in: bottle,
                    using: readyEngine,
                    graphicsBackend: graphicsBackend,
                    displayProfile: displayProfile
                )
                rememberWindowsApplication(url)
                operationStatus =
                    "\(url.lastPathComponent) is opening with \(resolvedGraphicsBackend.title)."
            } catch {
                operationStatus = nil
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func rememberWindowsApplication(_ url: URL) {
        recentWindowsApplications.removeAll { $0.path == url.path }
        recentWindowsApplications.insert(
            .init(path: url.path, lastLaunchedAt: Date()),
            at: 0
        )
        recentWindowsApplications = Array(recentWindowsApplications.prefix(10))
        saveRecentWindowsApplications()
    }

    private func loadRecentWindowsApplications() {
        guard let data = UserDefaults.standard.data(forKey: recentApplicationsKey),
              let applications = try? JSONDecoder().decode(
                [RecentWindowsApplication].self,
                from: data
              ) else {
            recentWindowsApplications = []
            return
        }
        recentWindowsApplications = applications.sorted {
            $0.lastLaunchedAt > $1.lastLaunchedAt
        }
    }

    private func saveRecentWindowsApplications() {
        let data = try? JSONEncoder().encode(recentWindowsApplications)
        UserDefaults.standard.set(data, forKey: recentApplicationsKey)
    }

    private func repairSteam() {
        guard engine != nil else { return }
        steamProgress = nil
        operationStatus = nil
        isWorking = true
        Task {
            do {
                let readyEngine = try await prepareEngine()
                try Launcher.repairAndLaunchSteam(
                    in: bottle,
                    using: readyEngine,
                    graphicsBackend: graphicsBackend,
                    displayProfile: displayProfile,
                    mouseCaptureProfile: mouseCaptureProfile
                )
                report("Steam’s web cache was rebuilt and Steam was relaunched.")
            } catch {
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func updateRuntime() {
        steamProgress = nil
        operationStatus = nil
        isWorking = true
        Task {
            do {
                try await RuntimeInstaller.install { runtimeProgress = $0 }
                refreshEngines()
                report("The gaming runtime was updated. Launch Steam normally.")
            } catch {
                report(error.localizedDescription)
            }
            runtimeProgress = nil
            isWorking = false
        }
    }

    private func stopSteamAndWine() {
        guard let engine,
              engine.kind != .crossover,
              engine.kind != .whisky else { return }
        operationStatus = "Stopping Steam and Wine…"
        isWorking = true
        Task {
            do {
                try await Task.detached {
                    try Launcher.stopBottleProcesses(in: bottle, using: engine)
                }.value
                operationStatus = "Steam and every Wine process in this bottle are stopped."
            } catch {
                operationStatus = nil
                report(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func uninstallBottle() {
        isUninstalling = true
        Task {
            do {
                try await uninstall()
                report("“\(bottle.name)” was uninstalled. Mac Wine Launcher and its shared Wine runtime were kept.")
            } catch {
                report(error.localizedDescription)
            }
            isUninstalling = false
        }
    }

    private func prepareEngine() async throws -> Engine {
        guard let engine else {
            throw RuntimeInstaller.InstallError.runtimeNotFound
        }
        guard engine.kind == .managedWine else {
            return engine
        }
        if RuntimeInstaller.isCurrentRuntime(engine),
           RuntimeInstaller.isCurrentRuntimeInstalled() {
            return engine
        }

        try await RuntimeInstaller.install { runtimeProgress = $0 }
        refreshEngines()
        guard let updated = EngineDiscovery.discover().first(where: {
            $0.kind == .managedWine && RuntimeInstaller.isCurrentRuntime($0)
        }) else {
            throw RuntimeInstaller.InstallError.runtimeNotFound
        }
        return updated
    }

    private var installButtonTitle: String {
        if engine?.kind == .crossover {
            return "Open CrossOver Installer"
        }
        return Launcher.isSteamInstalled(in: bottle)
            ? "Reinstall Windows Steam"
            : "Install Windows Steam"
    }

    private var availableGraphicsBackends: [GraphicsBackend] {
        guard let engine else { return [.automatic, .wineD3D] }
        let available = Launcher.availableGraphicsBackends(for: engine)
        return GraphicsBackend.allCases.filter(available.contains)
    }

    private var knownGameFixCount: Int {
        var count = 0
        if Launcher.isDontPanicInstalled(in: bottle) { count += 1 }
        if Launcher.isCyberpunkInstalled(in: bottle) { count += 1 }
        if Launcher.isBaldursGate3Installed(in: bottle) { count += 1 }
        if Launcher.isMarvelRivalsInstalled(in: bottle) { count += 1 }
        return count
    }

    private var resolvedGraphicsBackend: GraphicsBackend {
        guard let engine else { return .wineD3D }
        return Launcher.resolvedGraphicsBackend(graphicsBackend, for: engine)
    }

    private var graphicsPreferenceKey: String {
        "graphicsBackend.\(bottle.id.uuidString)"
    }

    private var displayPreferenceKey: String {
        "displayProfile.\(bottle.id.uuidString)"
    }

    private var inputPreferenceKey: String {
        "mouseCaptureProfile.\(bottle.id.uuidString)"
    }

    private var recentApplicationsKey: String {
        "recentWindowsApplications.\(bottle.id.uuidString)"
    }

    private var retinaResolutionSummary: String? {
        guard let screen = NSScreen.main else { return nil }
        let scale = displayProfile == .standard ? 1 : screen.backingScaleFactor
        let width = Int(screen.frame.width * scale)
        let height = Int(screen.frame.height * scale)
        return "\(width) × \(height)"
    }
}
