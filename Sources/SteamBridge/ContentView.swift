import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = BottleStore()
    @State private var engines = EngineDiscovery.discover()
    @State private var selection: Bottle.ID?
    @State private var showingNewBottle = false
    @State private var message: String?
    @State private var isInstallingRuntime = false
    @State private var runtimeProgress: RuntimeInstaller.InstallProgress?

    var body: some View {
        NavigationSplitView {
            List(store.bottles, selection: $selection) { bottle in
                Label(bottle.name, systemImage: "shippingbox")
                    .tag(bottle.id)
            }
            .navigationTitle("SteamBridge")
            .toolbar {
                Button(action: { showingNewBottle = true }) {
                    Label("New Bottle", systemImage: "plus")
                }
                .disabled(engines.isEmpty)
            }
        } detail: {
            if engines.isEmpty {
                ContentUnavailableView {
                    Label("Free Runtime Needed", systemImage: "shippingbox.and.arrow.backward")
                } description: {
                    Text("Install the free Sikarugir Wine gaming runtime. The two-part download is about 250 MB and usually takes 2–8 minutes.")
                } actions: {
                    if let runtimeProgress {
                        VStack(spacing: 6) {
                            if let fraction = runtimeProgress.fraction {
                                ProgressView(value: fraction)
                                    .frame(width: 280)
                                Text("\(Int(fraction * 100))% · \(runtimeProgress.stage.rawValue)")
                                    .monospacedDigit()
                            } else {
                                ProgressView()
                            }
                            Text(runtimeProgress.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(isInstallingRuntime ? "Installing…" : "Install Free Runtime") {
                        installFreeRuntime()
                    }
                    .disabled(isInstallingRuntime)
                    Button("Refresh") { engines = EngineDiscovery.discover() }
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
            } else {
                ContentUnavailableView("Choose a Bottle", systemImage: "gamecontroller")
            }
        }
        .frame(minWidth: 780, minHeight: 500)
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
        .alert("SteamBridge", isPresented: Binding(
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
                message = "SteamBridge Wine is installed. Create a bottle to install Windows Steam."
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
        Form {
            TextField("Bottle name", text: $name)
            Picker("Engine", selection: $engine) {
                ForEach(availableKinds) { kind in
                    Text("\(kind.rawValue) — \(kind.status)").tag(kind)
                }
            }
            Text(engine == .crossover
                 ? "SteamBridge will open CrossOver, whose installer creates and tunes the real Windows bottle."
                 : "A bottle is an isolated Windows environment. SteamBridge Wine is free and managed by this app.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 430)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onCreate(name, engine)
                    dismiss()
                }
            }
        }
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
    @State private var runtimeProgress: RuntimeInstaller.InstallProgress?
    @State private var steamProgress: Launcher.SteamInstallProgress?
    @State private var operationStatus: String?
    @State private var graphicsBackend: GraphicsBackend = .automatic
    @State private var displayProfile: DisplayProfile = .retinaRecommended
    @State private var mouseCaptureProfile: MouseCaptureProfile = .menuSafe
    @State private var windowsArguments = ""
    @State private var recentWindowsApplications: [RecentWindowsApplication] = []

    var body: some View {
        Form {
            Section("Bottle") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Engine", value: engine?.kind.rawValue ?? "Missing")
                if engine?.kind == .crossover {
                    Label("Commercial engine", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if engine?.kind == .steamBridge {
                    if let engine, RuntimeInstaller.isCurrentRuntime(engine) {
                        Label("Current free gaming runtime", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Upgrade installs automatically before Steam launches", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Update Gaming Runtime") { updateRuntime() }
                        .disabled(isWorking)
                }
                LabeledContent("Location", value: bottle.path)
            }

            Section("Steam") {
                if Launcher.isSteamInstalled(in: bottle) {
                    Label("Windows Steam is installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Windows Steam is not installed yet", systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(installButtonTitle) {
                        install()
                    }
                    .disabled(engine == nil || isWorking)
                    Button(engine?.kind == .crossover ? "Open CrossOver" : "Launch Steam") {
                        launch()
                    }
                    .disabled(
                        engine == nil ||
                            isWorking ||
                            (engine?.kind != .crossover && !Launcher.isSteamInstalled(in: bottle))
                    )
                }
                if isWorking, steamProgress == nil, runtimeProgress == nil {
                    ProgressView("Preparing…")
                }
                if let steamProgress {
                    if let fraction = steamProgress.fraction {
                        ProgressView(value: fraction)
                        Text("\(Int(fraction * 100))% · \(steamProgress.stage.rawValue)")
                            .font(.caption)
                            .monospacedDigit()
                    } else {
                        ProgressView()
                    }
                    Text(steamProgress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let runtimeProgress {
                    if let fraction = runtimeProgress.fraction {
                        ProgressView(value: fraction)
                    }
                    Text("\(runtimeProgress.stage.rawValue): \(runtimeProgress.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let operationStatus {
                    Label(operationStatus, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if engine?.kind == .steamBridge || engine?.kind == .wine {
                    Button("Fix Black Steam Window") { repairSteam() }
                        .disabled(isWorking)
                    Text("Closes Steam, clears its web-interface cache, and relaunches with software-rendered UI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Windows Apps") {
                HStack {
                    Button("Run Windows App or Installer…") {
                        chooseWindowsApplication()
                    }
                    .disabled(
                        engine == nil ||
                            isWorking ||
                            engine?.kind == .crossover ||
                            engine?.kind == .whisky
                    )
                    Button("Open C: Drive") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: bottle.path, isDirectory: true)
                                .appending(path: "drive_c", directoryHint: .isDirectory)
                        )
                    }
                }
                TextField(
                    "Optional launch arguments, e.g. --safe-mode \"My File\"",
                    text: $windowsArguments
                )
                Text("Choose a Windows .exe, .msi, .com, .bat, or .cmd file. It launches inside this bottle using \(resolvedGraphicsBackend.title); installers automatically run through Windows Installer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !recentWindowsApplications.isEmpty {
                    LabeledContent("Recent") {
                        Button("Clear") {
                            recentWindowsApplications = []
                            saveRecentWindowsApplications()
                        }
                        .buttonStyle(.link)
                    }
                    ForEach(recentWindowsApplications.prefix(5)) { application in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(application.displayName)
                                Text(application.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Run") {
                                runWindowsApplication(
                                    at: URL(fileURLWithPath: application.path)
                                )
                            }
                            .disabled(
                                isWorking ||
                                    !FileManager.default.fileExists(atPath: application.path)
                            )
                        }
                    }
                }
            }

            Section("AAA Game Graphics") {
                Picker("Graphics mode", selection: $graphicsBackend) {
                    ForEach(availableGraphicsBackends) { backend in
                        Text("\(backend.title) — \(backend.coverage)")
                            .tag(backend)
                    }
                }
                LabeledContent(
                    "Active renderer",
                    value: resolvedGraphicsBackend.title
                )
                Text(graphicsBackend.explanation)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Available renderer coverage:")
                    Label("DX9", systemImage: "checkmark.circle.fill")
                    Label("DX10", systemImage: "checkmark.circle.fill")
                    Label("DX11", systemImage: "checkmark.circle.fill")
                    Label("DX12", systemImage: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.green)
                Button("Apply Mode & Relaunch Steam") {
                    launch()
                }
                .disabled(
                    engine == nil ||
                        isWorking ||
                        (engine?.kind != .crossover && !Launcher.isSteamInstalled(in: bottle))
                )
                Text("Games launched by this Steam session inherit the selected DirectX renderer. If one game glitches, try DXMT, then DXVK, then WineD3D.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display & Resolution") {
                Picker("Display quality", selection: $displayProfile) {
                    ForEach(DisplayProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                LabeledContent("Render mode", value: displayProfile.summary)
                Text(displayProfile.explanation)
                    .foregroundStyle(.secondary)
                if let retinaResolutionSummary {
                    LabeledContent("Current Mac render space", value: retinaResolutionSummary)
                }
                Button("Apply Display & Relaunch Steam") {
                    launch()
                }
                .disabled(
                    engine == nil ||
                        isWorking ||
                        (engine?.kind != .crossover && !Launcher.isSteamInstalled(in: bottle))
                )
                Text("After enabling Retina, open each game’s Display settings and choose a higher resolution. Native Retina is sharpest; lowering the in-game resolution improves frame rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if Launcher.isDontPanicInstalled(in: bottle) {
                Section("Don’t Panic! Mouse Fix") {
                    Label(
                        "Installed game detected",
                        systemImage: "cursorarrow.motionlines"
                    )
                    .foregroundStyle(.green)
                    Picker("Mouse mode", selection: $mouseCaptureProfile) {
                        ForEach(MouseCaptureProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    Text(mouseCaptureProfile.summary)
                        .foregroundStyle(.secondary)
                    Button("Apply Mouse Fix & Relaunch Steam") {
                        launch()
                    }
                    .disabled(engine == nil || isWorking)
                    Text("SteamBridge applies this only to Don’t Panic—not to your other games. Menu-safe mode is applied automatically on every Steam launch. If the game ever captures the pointer again, press ⌥↩ to toggle window mode, then ⌘Tab back to SteamBridge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Game Profile Helper") {
                TextField("Game title", text: $title)
                TextField("Notes, e.g. DX12 or Easy Anti-Cheat", text: $notes)
                Button("Assess") {
                    assessment = GameCompatibility.assess(title: title, notes: notes)
                }
                if let assessment {
                    LabeledContent("Rating", value: assessment.rating.rawValue)
                    Text(assessment.explanation).foregroundStyle(.secondary)
                    if assessment.rating != .blocked {
                        Button("Use \(assessment.recommendedBackend.title)") {
                            graphicsBackend = assessment.recommendedBackend
                        }
                    }
                }
            }

            Section("Compatibility limits") {
                Text("SteamBridge now activates dedicated DirectX 9, 10, 11, and 12 renderers. It cannot bypass DRM or supply Windows kernel drivers; games that require unsupported kernel anti-cheat can still be blocked.")
                    .foregroundStyle(.secondary)
            }

            Section("Uninstall") {
                Button("Uninstall Bottle…", role: .destructive) {
                    showingUninstallConfirmation = true
                }
                .disabled(isWorking || isUninstalling)
                if isUninstalling {
                    ProgressView("Uninstalling bottle…")
                }
                Text("Deletes this bottle, Windows Steam, and every game installed inside it. The SteamBridge app and shared Wine runtime stay installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: graphicsPreferenceKey),
               let backend = GraphicsBackend(rawValue: saved),
               availableGraphicsBackends.contains(backend) {
                graphicsBackend = backend
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
        .onChange(of: graphicsBackend) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: graphicsPreferenceKey)
            operationStatus = "\(newValue.title) will be used the next time Steam launches."
        }
        .onChange(of: displayProfile) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: displayPreferenceKey)
            operationStatus = "\(newValue.title) will be used the next time Steam launches."
        }
        .onChange(of: mouseCaptureProfile) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: inputPreferenceKey)
            operationStatus = "\(newValue.title) will be used for Don’t Panic the next time Steam launches."
        }
        .alert("Uninstall “\(bottle.name)”?", isPresented: $showingUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall Bottle", role: .destructive) {
                uninstallBottle()
            }
        } message: {
            Text("This permanently deletes Windows Steam, installed games, saves stored only inside this bottle, and all other bottle files. The shared runtime is not removed.")
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
                let inputStatus = Launcher.isDontPanicInstalled(in: bottle)
                    ? " Don’t Panic is using \(mouseCaptureProfile.title)."
                    : ""
                operationStatus =
                    "Steam’s interface is running with \(resolved.title) and \(displayProfile.title).\(inputStatus)"
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

    private func uninstallBottle() {
        isUninstalling = true
        Task {
            do {
                try await uninstall()
                report("“\(bottle.name)” was uninstalled. SteamBridge and its shared Wine runtime were kept.")
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
        guard engine.kind == .steamBridge else {
            return engine
        }
        if RuntimeInstaller.isCurrentRuntime(engine),
           RuntimeInstaller.isCurrentRuntimeInstalled() {
            return engine
        }

        try await RuntimeInstaller.install { runtimeProgress = $0 }
        refreshEngines()
        guard let updated = EngineDiscovery.discover().first(where: {
            $0.kind == .steamBridge && RuntimeInstaller.isCurrentRuntime($0)
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
