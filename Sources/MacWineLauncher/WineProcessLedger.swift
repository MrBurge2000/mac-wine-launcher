import Darwin
import Foundation

// A PID alone is not an identity: macOS can reuse it after a process exits.
struct WineProcessIdentity: Codable, Hashable, Sendable {
    let pid: Int32
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    static func current(_ pid: Int32) -> WineProcessIdentity? {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info,
                        Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size {
            guard info.pbi_uid == getuid(), info.pbi_status != SZOMB else { return nil }
            return .init(pid: pid, startedSeconds: info.pbi_start_tvsec,
                         startedMicroseconds: info.pbi_start_tvusec)
        }
        // libproc stops returning task info during kernel exit. KERN_PROC_PID
        // still exposes the birth time until the process has really disappeared.
        guard let kernel = kernelInfo(pid), kernel.kp_eproc.e_ucred.cr_uid == getuid(),
              kernel.kp_proc.p_stat != SZOMB else { return nil }
        return .init(pid: pid, startedSeconds: UInt64(kernel.kp_proc.p_starttime.tv_sec),
                     startedMicroseconds: UInt64(kernel.kp_proc.p_starttime.tv_usec))
    }

    static func kernelInfo(_ pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size else { return nil }
        return info
    }

    var isCurrent: Bool { Self.current(pid) == self }

    static func isExiting(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info,
                        Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 {
            return info.pbi_flags & UInt32(PROC_FLAG_INEXIT) != 0
        }
        return (kernelInfo(pid)?.kp_proc.p_flag ?? 0) & P_WEXIT != 0
    }
}

final class WineProcessLedger: @unchecked Sendable {
    static let shared = WineProcessLedger(
        storage: AppDataPaths.supportRoot().appending(path: "process-ledger.json")
    )
    private struct Record: Codable, Hashable {
        let bottle: String
        let engine: String
        let identity: WineProcessIdentity
    }
    private let lock = NSLock()
    private var records: Set<Record>
    private let storage: URL?
    private let queue = DispatchQueue(label: "MacWineLauncher.process-monitor", qos: .utility)
    private var watches: [String: (Bottle, Engine)] = [:]
    private var timer: DispatchSourceTimer?

    init(storage: URL? = nil) {
        self.storage = storage
        if let storage, let data = try? Data(contentsOf: storage),
           let saved = try? JSONDecoder().decode(Set<Record>.self, from: data) {
            records = Set(saved.filter { $0.identity.isCurrent })
        } else { records = [] }
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // The environment is inspected locally and discarded. No arguments, tokens,
    // Steam account information, or other environment values are persisted.
    static func prefix(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        // The size-only PROCARGS2 query can omit the environment. Reserve
        // KERN_ARGMAX instead, so short command lines still expose WINEPREFIX.
        var size = argumentBufferSize
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < size && bytes[index] != 0 { index += 1 } // executable
        while index < size && bytes[index] == 0 { index += 1 }
        for _ in 0..<argc {
            while index < size && bytes[index] != 0 { index += 1 }
            index += 1
        }
        while index < size {
            let start = index
            while index < size && bytes[index] != 0 { index += 1 }
            let entry = String(decoding: bytes[start..<index], as: UTF8.self)
            if entry.hasPrefix("WINEPREFIX=") { return String(entry.dropFirst(11)) }
            index += 1
        }
        return nil
    }

    private static let argumentBufferSize: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, UInt32(mib.count), &maximum, &size, nil, 0) == 0,
              maximum > 0, maximum < 4_194_304 else { return 262_144 }
        return Int(maximum)
    }()

    static func executable(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func allPIDs() -> [Int32] {
        let size = proc_listallpids(nil, 0)
        guard size > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(size) + 128)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 1 && $0 != getpid() }
    }

    func remember(_ identities: Set<WineProcessIdentity>, in bottle: Bottle, using engine: Engine) {
        lock.lock()
        defer { lock.unlock() }
        let previous = records
        records = Set(records.filter { $0.identity.isCurrent })
        let prefix = Self.canonical(bottle.path)
        let executable = Self.canonical(engine.executableURL.path)
        for identity in identities where identity.isCurrent {
            records.insert(.init(bottle: prefix, engine: executable, identity: identity))
        }
        if records != previous, let storage {
            do {
                try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(records).write(to: storage, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storage.path)
            } catch { NSLog("Wine process tracking could not be saved: %@", error.localizedDescription) }
        }
    }

    func identities(in bottle: Bottle, using engine: Engine) -> Set<WineProcessIdentity> {
        let prefix = Self.canonical(bottle.path)
        let executable = Self.canonical(engine.executableURL.path)
        let server = Self.canonical(engine.executableURL.deletingLastPathComponent().appending(path: "wineserver").path)
        var found = Set<WineProcessIdentity>()
        var candidatesWithoutPrefix = Set<WineProcessIdentity>()
        for pid in Self.allPIDs() {
            guard let identity = WineProcessIdentity.current(pid),
                  let path = Self.executable(of: pid),
                  [executable, server].contains(Self.canonical(path)) else { continue }
            if let processPrefix = Self.prefix(of: pid) {
                if Self.canonical(processPrefix) == prefix { found.insert(identity) }
            } else {
                candidatesWithoutPrefix.insert(identity)
            }
        }
        found.formUnion(Self.identitiesWithOpenFiles(candidatesWithoutPrefix, prefix: prefix))
        remember(found, in: bottle, using: engine)
        lock.lock()
        defer { lock.unlock() }
        return Set(records.filter { $0.bottle == prefix && $0.engine == executable && $0.identity.isCurrent }
            .map(\.identity))
    }

    private static func identitiesWithOpenFiles(_ candidates: Set<WineProcessIdentity>, prefix: String) -> Set<WineProcessIdentity> {
        guard !candidates.isEmpty else { return [] }
        // Inspect just these processes, never traverse every file in a large
        // Steam library. A file-backed output avoids filling a pipe and hanging.
        let temporary = FileManager.default.temporaryDirectory.appending(path: "mwl-lsof-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]),
              let output = try? FileHandle(forWritingTo: temporary) else { return [] }
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-n", "-P", "-a", "-p", candidates.map { String($0.pid) }.joined(separator: ","), "-Fpn"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard !process.isRunning else {
            Darwin.kill(process.processIdentifier, SIGKILL)
            return []
        }
        guard let data = try? String(contentsOf: temporary, encoding: .utf8) else { return [] }
        var pid: Int32?
        var matched = Set<Int32>()
        for line in data.split(whereSeparator: \.isNewline) {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            if line.first == "n", let pid {
                let path = canonical(String(line.dropFirst()))
                if path == prefix || path.hasPrefix(prefix + "/") { matched.insert(pid) }
            }
        }
        return Set(candidates.filter { matched.contains($0.pid) && $0.isCurrent })
    }

    func watch(_ bottle: Bottle, using engine: Engine) {
        queue.async { [self] in
            watches[Self.canonical(bottle.path)] = (bottle, engine)
            _ = identities(in: bottle, using: engine)
            if timer == nil {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now() + 2, repeating: 5, leeway: .seconds(1))
                source.setEventHandler { [weak self] in
                    guard let self else { return }
                    for (bottle, engine) in self.watches.values { _ = self.identities(in: bottle, using: engine) }
                }
                source.resume()
                timer = source
            }
        }
    }

    // Older orphaned processes may have lost all ownership evidence before this
    // version was installed. Surface them without assigning them to a bottle.
    static func unownedExitingWinePIDs() -> [Int32] {
        allPIDs().filter { pid in
            guard WineProcessIdentity.isExiting(pid), WineProcessIdentity.current(pid) != nil,
                  var info = WineProcessIdentity.kernelInfo(pid) else { return false }
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            return name == "wine" && prefix(of: pid) == nil
        }.sorted()
    }
}
