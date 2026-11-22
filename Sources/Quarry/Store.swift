import AppKit
import CryptoKit
import Foundation

struct Instance: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let gameVersion: String
    let loaderVersion: String
    var mods: [String: String] = [:] // Modrinth-Projekt-ID → Dateiname in mods/
}

/// Wird bei jeder neuen Instanz automatisch installiert (alles Fabric, Client-seitig).
let macPerformancePack: [(slug: String, name: String, why: String)] = [
    ("sodium", "Sodium", "Neuer Renderer, meist 2–3× mehr FPS – wichtigster Mod auf dem Mac"),
    ("iris", "Iris Shaders", "Shader (z. B. Complementary) mit Sodium-Tempo"),
    ("moreculling", "MoreCulling", "Blendet verdeckte Blockflächen aus – extra FPS, v. a. mit Shadern"),
    ("lithium", "Lithium", "Schnellere Spiel-Logik (Ticks)"),
    ("ferrite-core", "FerriteCore", "Weniger RAM – wichtig bei 8/16 GB Unified Memory"),
    ("modernfix", "ModernFix", "Schnellerer Start, weniger RAM"),
    ("immediatelyfast", "ImmediatelyFast", "Schnelleres Zeichnen von HUD, Text, Items"),
    ("entityculling", "Entity Culling", "Unsichtbare Tiere/Truhen werden nicht gerendert"),
    ("dynamic-fps", "Dynamic FPS", "Drosselt im Hintergrund – Akku und Lüfter"),
    ("macos-input-fixes", "MacOS Input Fixes", "Trackpad-Scrollen und Ctrl-Klick reparieren"),
]

enum Paths {
    static let root = URL.applicationSupportDirectory.appending(path: "Quarry/instances")
    /// Testbar über QUARRY_MC_DIR, sonst der Ordner des offiziellen Launchers.
    static var minecraft: URL {
        ProcessInfo.processInfo.environment["QUARRY_MC_DIR"].map { URL(filePath: $0) }
            ?? URL.applicationSupportDirectory.appending(path: "minecraft")
    }

    /// Lehnt absolute Pfade und „..“ ab, damit Modpacks nichts außerhalb der Instanz schreiben.
    static func safeDestination(base: URL, path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.isEmpty, !parts.contains(".."), !parts.contains(""), !parts.contains("."),
              path.lowercased() != "instance.json" else { // APFS ignoriert Groß/Klein
            throw QuarryError.unsafePath(path)
        }
        return base.appending(path: path)
    }

    static func isValidInstanceId(_ id: String) -> Bool {
        id.wholeMatch(of: /quarry-[0-9a-f]{8}/) != nil
    }

    static func rejectSymlinks(in dir: URL) throws {
        let items = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let url = items?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw QuarryError.unsafePath(url.lastPathComponent)
            }
        }
    }

    /// cdn.modrinth.com/data/<projektID>/versions/… → projektID
    static func modrinthProjectId(_ url: URL) -> String? {
        let c = url.pathComponents
        guard url.host == "cdn.modrinth.com", c.count > 2, c[1] == "data" else { return nil }
        return c[2]
    }

    /// Aikar-Flags (G1GC) + halber Arbeitsspeicher, 2–8 GB. Mehr als 8 GB macht Minecraft nur langsamer (GC-Pausen).
    static func javaArgs(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let gb = min(8, max(2, Int(physicalMemory / 1_073_741_824) / 2))
        return "-Xms\(gb)G -Xmx\(gb)G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 "
            + "-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch "
            + "-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M "
            + "-XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15"
    }
}

private let fm = FileManager.default

@Observable final class Store {
    var instances: [Instance] = []
    var gameVersions: [String] = []
    var status: String?
    var alert: String?
    var update: Updater.Release?
    var launcherInstalled = Store.detectLauncher()

    init() { load() }

    func dir(_ i: Instance) -> URL { Paths.root.appending(path: i.id) }

    func load() {
        let dirs = (try? fm.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? []
        instances = dirs.compactMap { d -> Instance? in
            guard let i = try? JSONDecoder().decode(Instance.self, from: Data(contentsOf: d.appending(path: "instance.json"))),
                  Paths.isValidInstanceId(i.id), i.id == d.lastPathComponent else { return nil } // untergeschobene IDs wie „../..“ ignorieren
            return i
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ i: Instance) throws {
        try fm.createDirectory(at: dir(i).appending(path: "mods"), withIntermediateDirectories: true)
        try JSONEncoder().encode(i).write(to: dir(i).appending(path: "instance.json"), options: .atomic)
        if let idx = instances.firstIndex(where: { $0.id == i.id }) { instances[idx] = i } else { load() }
    }

    /// Eine Aktion zur Zeit – die UI sperrt Knöpfe, solange `status` gesetzt ist.
    func run(_ label: String, _ work: @escaping () async throws -> Void) {
        guard status == nil else { return }
        status = label
        Task {
            defer { status = nil }
            do { try await work() } catch { alert = error.localizedDescription }
        }
    }

    func loadGameVersions() async {
        guard gameVersions.isEmpty else { return }
        do { gameVersions = try await Modrinth.releaseVersions() } catch { alert = error.localizedDescription }
    }

    // MARK: Instanzen

    func createInstance(name: String, gameVersion: String, loaderVersion: String? = nil) async throws -> Instance {
        guard fm.fileExists(atPath: Paths.minecraft.appending(path: "launcher_profiles.json").path) else {
            throw QuarryError.noLauncher
        }
        let loader = if let loaderVersion { loaderVersion } else { try await Modrinth.fabricLoader(for: gameVersion) }
        let inst = Instance(id: "quarry-" + UUID().uuidString.prefix(8).lowercased(), name: name,
                            gameVersion: gameVersion, loaderVersion: loader)
        try save(inst)
        try writeMacOptions(inst)
        try await registerWithLauncher(inst)
        return inst
    }

    /// Neue Instanz + Leistungspaket; meldet, was es für diese Version nicht gibt.
    func createWithPack(name: String, gameVersion: String) async throws -> String {
        var inst = try await createInstance(name: name, gameVersion: gameVersion)
        await applyPerformancePack(&inst)
        return inst.id
    }

    func applyPerformancePack(_ inst: inout Instance) async {
        var missing: [String] = []
        for mod in macPerformancePack {
            status = "Leistungspaket: \(mod.name) …"
            do { try await installMod(mod.slug, into: &inst) } catch { missing.append(mod.name) }
        }
        if !missing.isEmpty {
            alert = "Für Minecraft \(inst.gameVersion) nicht verfügbar und übersprungen: \(missing.joined(separator: ", "))"
        }
    }

    func deleteInstance(_ inst: Instance) {
        try? editProfiles { $0[inst.id] = nil }
        do { try fm.removeItem(at: dir(inst)) } catch { alert = error.localizedDescription }
        load()
    }

    func modFiles(_ inst: Instance) -> [String] {
        let files = (try? fm.contentsOfDirectory(atPath: dir(inst).appending(path: "mods").path)) ?? []
        return files.filter { $0.hasSuffix(".jar") || $0.hasSuffix(".jar.disabled") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func removeMod(_ file: String, from inst: Instance) {
        var inst = inst
        do {
            try fm.removeItem(at: dir(inst).appending(path: "mods/\(file)"))
            inst.mods = inst.mods.filter { $0.value != file }
            try save(inst)
        } catch { alert = error.localizedDescription }
    }

    func play() {
        let ws = NSWorkspace.shared
        if let app = ws.urlForApplication(withBundleIdentifier: "com.mojang.minecraftlauncher") {
            ws.openApplication(at: app, configuration: .init())
        } else if fm.fileExists(atPath: "/Applications/Minecraft.app") {
            ws.open(URL(filePath: "/Applications/Minecraft.app"))
        } else {
            alert = QuarryError.noLauncher.errorDescription
        }
    }

    // MARK: Updates & Launcher

    func checkForUpdates(manual: Bool) async {
        do {
            update = try await Updater.latest()
            if manual && update == nil { alert = "Quarry \(Updater.current) ist die neueste Version." }
        } catch {
            if manual { alert = error.localizedDescription }
        }
    }

    /// Bringt alle Mods einer Instanz per Modrinth-Hash-Abgleich auf den neuesten Stand (auch Modpack-Mods).
    func updateMods(_ inst: Instance) async throws {
        var inst = inst
        let modsDir = dir(inst).appending(path: "mods")
        var byHash: [String: String] = [:] // sha1 → Dateiname
        for f in modFiles(inst) where f.hasSuffix(".jar") {
            byHash[sha1Hex(try Data(contentsOf: modsDir.appending(path: f)))] = f
        }
        guard !byHash.isEmpty else { alert = "Keine Mods zum Aktualisieren."; return }
        let data = try await Modrinth.fetch(URL(string: "https://api.modrinth.com/v2/version_files/update")!, body: [
            "hashes": Array(byHash.keys), "algorithm": "sha1", "loaders": ["fabric"], "game_versions": [inst.gameVersion],
        ])
        let latest = try Modrinth.decoder.decode([String: ModVersion].self, from: data)
        var updated: [String] = []
        for (hash, v) in latest {
            guard let old = byHash[hash], let file = v.files.first(where: \.primary) ?? v.files.first,
                  file.hashes["sha1"]?.lowercased() != hash else { continue }
            status = "Aktualisiere \(file.filename) …"
            try await download(file.url, sha1: file.hashes["sha1"], to: try Paths.safeDestination(base: modsDir, path: file.filename))
            if old != file.filename { try? fm.removeItem(at: modsDir.appending(path: old)) }
            inst.mods = inst.mods.filter { $0.value != old }
            inst.mods[v.projectId] = file.filename
            updated.append(file.filename)
        }
        try save(inst)
        alert = updated.isEmpty ? "Alle Mods sind aktuell." : "\(updated.count) Mods aktualisiert:\n" + updated.sorted().joined(separator: "\n")
    }

    static func detectLauncher() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mojang.minecraftlauncher") != nil
            || fm.fileExists(atPath: "/Applications/Minecraft.app")
    }

    /// Lädt den offiziellen Launcher von Mojang, prüft dessen Signatur und kopiert ihn nach /Applications.
    func installLauncher() async throws {
        let tmp = fm.temporaryDirectory.appending(path: "quarry-launcher-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let dmg = tmp.appending(path: "Minecraft.dmg"), mount = tmp.appending(path: "mnt")
        try await download(URL(string: "https://launcher.mojang.com/download/Minecraft.dmg")!, sha1: nil, to: dmg)
        try runTool("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        defer { try? runTool("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let app = mount.appending(path: "Minecraft.app")
        // Nur installieren, wenn wirklich Mojang (Team UBF8T346G9) signiert hat.
        try runTool("/usr/bin/codesign", ["--verify", "--deep", "-R=anchor apple generic and certificate leaf[subject.OU] = \"UBF8T346G9\"", app.path])
        try runTool("/usr/bin/ditto", [app.path, "/Applications/Minecraft.app"])
        launcherInstalled = true
        play()
        alert = "Minecraft Launcher ist installiert. Melde dich dort einmal an – danach kannst du hier Instanzen anlegen."
    }

    // MARK: Mods

    func installMod(_ project: String, into inst: inout Instance) async throws {
        guard let v = try await Modrinth.versions(project, gameVersion: inst.gameVersion).first else {
            throw QuarryError.incompatible(project, inst.gameVersion)
        }
        if inst.mods[v.projectId] != nil { return }
        guard let file = v.files.first(where: \.primary) ?? v.files.first else { throw QuarryError.incompatible(project, inst.gameVersion) }
        let dest = try Paths.safeDestination(base: dir(inst).appending(path: "mods"), path: file.filename)
        try await download(file.url, sha1: file.hashes["sha1"], to: dest)
        inst.mods[v.projectId] = file.filename
        try save(inst)
        for dep in v.dependencies where dep.dependencyType == "required" {
            if let id = dep.projectId, inst.mods[id] == nil { try await installMod(id, into: &inst) }
        }
    }

    func download(_ url: URL, sha1: String?, to dest: URL) async throws {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuarryError.http(url.absoluteString) }
        if let sha1 {
            guard sha1Hex(try Data(contentsOf: tmp)) == sha1.lowercased() else { try? fm.removeItem(at: tmp); throw QuarryError.hashMismatch(dest.lastPathComponent) }
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmp, to: dest)
    }

    // MARK: Modpacks (.mrpack)

    struct PackFile: Decodable, Sendable {
        let path: String
        let hashes: [String: String]
        let downloads: [URL]
        let env: [String: String]?
    }

    func installModpack(_ hit: Hit) async throws {
        struct Index: Decodable { let name: String; let dependencies: [String: String]; let files: [PackFile] }
        guard let v = try await Modrinth.versions(hit.projectId, gameVersion: nil).first,
              let file = v.files.first(where: \.primary) ?? v.files.first else { throw QuarryError.notFabricPack }

        let tmp = fm.temporaryDirectory.appending(path: "quarry-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let archive = tmp.appending(path: "pack.mrpack"), unpacked = tmp.appending(path: "x")
        try await download(file.url, sha1: file.hashes["sha1"], to: archive)
        try runTool("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        guard let data = try? Data(contentsOf: unpacked.appending(path: "modrinth.index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { throw QuarryError.badFile("modrinth.index.json") }
        guard let mc = index.dependencies["minecraft"], let loader = index.dependencies["fabric-loader"] else {
            throw QuarryError.notFabricPack
        }

        var inst = try await createInstance(name: index.name, gameVersion: mc, loaderVersion: loader)
        let base = dir(inst)
        let files = index.files.filter { $0.env?["client"] != "unsupported" }
        var queue = files[...], done = 0
        try await withThrowingTaskGroup(of: PackFile.self) { group in
            func start() {
                guard let f = queue.popFirst() else { return }
                group.addTask { try await self.fetchPackFile(f, base: base); return f }
            }
            for _ in 0..<6 { start() } // max. 6 Downloads gleichzeitig
            while let f = try await group.next() {
                done += 1
                status = "Modpack: \(done)/\(files.count) Dateien"
                if f.path.hasPrefix("mods/"), let url = f.downloads.first, let id = Paths.modrinthProjectId(url) {
                    inst.mods[id] = String(f.path.dropFirst(5))
                }
                start()
            }
        }
        try Paths.rejectSymlinks(in: unpacked) // ein Symlink in overrides könnte sonst außerhalb der Instanz schreiben
        for folder in ["overrides", "client-overrides"] where fm.fileExists(atPath: unpacked.appending(path: folder).path) {
            try runTool("/usr/bin/ditto", [unpacked.appending(path: folder).path, base.path])
        }
        try save(inst)
        await applyPerformancePack(&inst) // überspringt, was das Pack schon mitbringt
    }

    private func fetchPackFile(_ f: PackFile, base: URL) async throws {
        let allowed: Set = ["cdn.modrinth.com", "github.com", "raw.githubusercontent.com", "gitlab.com"]
        guard let url = f.downloads.first(where: { allowed.contains($0.host ?? "") }) else { throw QuarryError.unsafePath(f.path) }
        try await download(url, sha1: f.hashes["sha1"], to: try Paths.safeDestination(base: base, path: f.path))
    }

    // MARK: Offizieller Launcher

    private func registerWithLauncher(_ inst: Instance) async throws {
        let json = try await Modrinth.fetch(URL(string:
            "https://meta.fabricmc.net/v2/versions/loader/\(inst.gameVersion)/\(inst.loaderVersion)/profile/json")!)
        guard let versionId = (try JSONSerialization.jsonObject(with: json) as? [String: Any])?["id"] as? String,
              !versionId.contains("/"), !versionId.contains("..") else { throw QuarryError.badFile("Fabric-Profil") }
        let vdir = Paths.minecraft.appending(path: "versions/\(versionId)")
        try fm.createDirectory(at: vdir, withIntermediateDirectories: true)
        try json.write(to: vdir.appending(path: "\(versionId).json"), options: .atomic)
        let jar = vdir.appending(path: "\(versionId).jar") // leere Jar wie beim offiziellen Fabric-Installer
        if !fm.fileExists(atPath: jar.path) { fm.createFile(atPath: jar.path, contents: Data()) }

        let now = ISO8601DateFormatter().string(from: .now)
        try editProfiles {
            $0[inst.id] = [
                "name": inst.name, "type": "custom", "icon": "Furnace",
                "created": now, "lastUsed": now, "lastVersionId": versionId,
                "gameDir": dir(inst).path, "javaArgs": Paths.javaArgs(),
            ]
        }
    }

    private func editProfiles(_ change: (inout [String: Any]) -> Void) throws {
        let url = Paths.minecraft.appending(path: "launcher_profiles.json")
        guard fm.fileExists(atPath: url.path) else { throw QuarryError.noLauncher }
        let backup = url.appendingPathExtension("quarry-backup")
        if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: url, to: backup) }
        // Kaputte Datei nie überschreiben – sonst wären alle Launcher-Profile weg.
        guard var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw QuarryError.badFile("launcher_profiles.json")
        }
        var profiles = root["profiles"] as? [String: Any] ?? [:]
        change(&profiles)
        root["profiles"] = profiles
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]).write(to: url, options: .atomic)
    }

    /// Startwerte für FPS auf dem Mac – nur wenn die Instanz noch keine options.txt hat.
    private func writeMacOptions(_ inst: Instance) throws {
        let url = dir(inst).appending(path: "options.txt")
        guard !fm.fileExists(atPath: url.path) else { return }
        let options = """
        renderDistance:10
        simulationDistance:8
        maxFps:120
        enableVsync:false
        entityShadows:false
        graphicsMode:0
        """
        try options.write(to: url, atomically: true, encoding: .utf8)
    }
}

func sha1Hex(_ data: Data) -> String {
    Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
