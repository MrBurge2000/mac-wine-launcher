import AppKit
import SwiftUI

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
                    Text("Install SteamBridge Wine, a free runtime based on the open-source Wine project. The current download is about 177 MB and usually takes 2–8 minutes.")
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

    var body: some View {
        Form {
            Section("Bottle") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Engine", value: engine?.kind.rawValue ?? "Missing")
                if engine?.kind == .crossover {
                    Label("Commercial engine", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if engine?.kind == .steamBridge {
                    Label("Free built-in runtime", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Button("Update Gaming Runtime") { updateRuntime() }
                        .disabled(isWorking)
                }
                LabeledContent("Location", value: bottle.path)
            }

            Section("Steam") {
                HStack {
                    Button(engine?.kind == .crossover ? "Open CrossOver Installer" : "Install Windows Steam") {
                        install()
                    }
                    Button(engine?.kind == .crossover ? "Open CrossOver" : "Launch Steam") {
                        launch()
                    }
                }
                .disabled(engine == nil || isWorking)
                if isWorking { ProgressView() }
                if let runtimeProgress {
                    if let fraction = runtimeProgress.fraction {
                        ProgressView(value: fraction)
                    }
                    Text("\(runtimeProgress.stage.rawValue): \(runtimeProgress.detail)")
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

            Section("Compatibility Check") {
                TextField("Game title", text: $title)
                TextField("Notes, e.g. DX12 or Easy Anti-Cheat", text: $notes)
                Button("Assess") {
                    assessment = GameCompatibility.assess(title: title, notes: notes)
                }
                if let assessment {
                    LabeledContent("Rating", value: assessment.rating.rawValue)
                    Text(assessment.explanation).foregroundStyle(.secondary)
                }
            }

            Section("Important limits") {
                Text("This does not emulate a PC or bypass DRM. Kernel anti-cheat, unsupported launchers, AVX-only games, and some DirectX 12 titles may not run.")
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
        guard let engine else { return }
        isWorking = true
        Task {
            do {
                try await Launcher.installSteam(in: bottle, using: engine)
                if engine.kind == .crossover {
                    report("CrossOver opened. Select Steam, click Install, and let its supported recipe configure the bottle.")
                } else {
                    report("Steam installed successfully and is updating toward the sign-in page.")
                }
            } catch {
                report(error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func launch() {
        guard let engine else { return }
        do {
            try Launcher.launchSteam(in: bottle, using: engine)
        } catch {
            report(error.localizedDescription)
        }
    }

    private func repairSteam() {
        guard let engine else { return }
        do {
            try Launcher.repairAndLaunchSteam(in: bottle, using: engine)
            report("Steam was relaunched with GPU rendering disabled for its interface.")
        } catch {
            report(error.localizedDescription)
        }
    }

    private func updateRuntime() {
        isWorking = true
        Task {
            do {
                try await RuntimeInstaller.install { runtimeProgress = $0 }
                refreshEngines()
                report("The gaming runtime was updated. Use Fix Black Steam Window to relaunch Steam.")
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
}
