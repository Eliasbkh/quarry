import Foundation

struct Hit: Decodable, Identifiable, Hashable {
    let projectId: String
    let slug: String
    let title: String
    let description: String
    let iconUrl: String?
    let downloads: Int
    let author: String
    let categories: [String]
    var id: String { projectId }
}

struct Project: Decodable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let iconUrl: String?
}

/// Die vier Inhaltsarten von Modrinth, die Quarry installieren kann.
enum Kind: String, CaseIterable, Identifiable, Hashable {
    case mod, modpack, resourcepack, shader
    var id: String { rawValue }

    var title: String {
        switch self { case .mod: "Mods"; case .modpack: "Modpacks"; case .resourcepack: "Ressourcenpakete"; case .shader: "Shader" }
    }
    var symbol: String {
        switch self { case .mod: "puzzlepiece.extension"; case .modpack: "shippingbox"; case .resourcepack: "paintpalette"; case .shader: "sun.max" }
    }
    var explanation: String {
        switch self {
        case .mod: "Mods fügen neue Inhalte hinzu oder machen das Spiel schneller. Sie landen in einer deiner Instanzen."
        case .modpack: "Fertige Sammlungen aus vielen Mods. Jedes Modpack wird als eigene neue Instanz installiert."
        case .resourcepack: "Ändern Texturen, Sounds und Schrift. Im Spiel aktivieren: Optionen → Ressourcenpakete."
        case .shader: "Echtes Licht, Schatten und Wasser. Im Spiel aktivieren: Optionen → Grafik → Shader-Pakete."
        }
    }
    /// Modrinth-Loader für Versionen dieser Art.
    var loader: String {
        switch self { case .mod, .modpack: "fabric"; case .resourcepack: "minecraft"; case .shader: "iris" }
    }
    /// Unterordner der Instanz.
    var folder: String {
        switch self { case .mod: "mods"; case .modpack: ""; case .resourcepack: "resourcepacks"; case .shader: "shaderpacks" }
    }
}

struct ModVersion: Decodable {
    let projectId: String
    let files: [ModFile]
    let dependencies: [Dependency]
}

struct ModFile: Decodable {
    let url: URL
    let filename: String
    let primary: Bool
    let hashes: [String: String]
}

struct Dependency: Decodable {
    let projectId: String?
    let dependencyType: String
}

enum QuarryError: LocalizedError {
    case http(String), noLauncher, noFabric(String), incompatible(String, String)
    case hashMismatch(String), unsafePath(String), notFabricPack, tool(String), badFile(String), noUpdateServer

    var errorDescription: String? {
        switch self {
        case .http(let url): "Server antwortet nicht richtig: \(url)"
        case .noLauncher: "Minecraft Launcher ist noch nicht eingerichtet. Installiere ihn auf der Übersicht in Quarry und öffne ihn einmal zum Anmelden."
        case .noUpdateServer: "Für diese Quarry-Version ist kein Update-Server eingerichtet."
        case .noFabric(let v): "Fabric gibt es (noch) nicht für Minecraft \(v)."
        case .incompatible(let p, let v): "„\(p)“ gibt es nicht für Fabric \(v)."
        case .hashMismatch(let f): "Download beschädigt: \(f)"
        case .unsafePath(let p): "Unsicherer Dateipfad im Modpack abgelehnt: \(p)"
        case .notFabricPack: "Nur Fabric-Modpacks werden unterstützt."
        case .tool(let t): "Systemwerkzeug fehlgeschlagen: \(t)"
        case .badFile(let f): "Datei unlesbar: \(f)"
        }
    }
}

enum Modrinth {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func fetch(_ url: URL, body: Any? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Quarry/\(Updater.current) (macOS launcher)", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuarryError.http(url.absoluteString) }
        return data
    }

    static func get<T: Decodable>(_ path: String, _ query: [String: Any] = [:]) async throws -> T {
        var c = URLComponents(string: "https://api.modrinth.com/v2/\(path)")!
        if !query.isEmpty {
            c.queryItems = query.map { key, value in
                let text = value as? String ?? String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
                return URLQueryItem(name: key, value: text)
            }
        }
        return try decoder.decode(T.self, from: try await fetch(c.url!))
    }

    static func search(_ text: String, kind: Kind, gameVersion: String?) async throws -> [Hit] {
        struct Result: Decodable { let hits: [Hit] }
        var facets = [["project_type:\(kind.rawValue)"]]
        if kind != .resourcepack { facets.append(["categories:\(kind.loader)"]) }
        if let gameVersion { facets.append(["versions:\(gameVersion)"]) }
        let r: Result = try await get("search", ["query": text, "facets": facets, "limit": "40"])
        return r.hits
    }

    /// Neueste Versionen zuerst (so liefert Modrinth sie).
    static func versions(_ project: String, loader: String = "fabric", gameVersion: String?) async throws -> [ModVersion] {
        var q: [String: Any] = ["loaders": [loader]]
        if let gameVersion { q["game_versions"] = [gameVersion] }
        return try await get("project/\(project)/version", q)
    }

    static func projects(_ ids: [String]) async throws -> [Project] {
        ids.isEmpty ? [] : try await get("projects", ["ids": ids])
    }

    static func releaseVersions() async throws -> [String] {
        struct GV: Decodable { let version: String; let versionType: String }
        let all: [GV] = try await get("tag/game_version")
        return all.filter { $0.versionType == "release" }.map(\.version)
    }

    static func fabricLoader(for mc: String) async throws -> String {
        struct Entry: Decodable { struct L: Decodable { let version: String; let stable: Bool }; let loader: L }
        let data = try await fetch(URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(mc)")!)
        let list = try decoder.decode([Entry].self, from: data)
        guard let l = list.first(where: { $0.loader.stable }) ?? list.first else { throw QuarryError.noFabric(mc) }
        return l.loader.version
    }
}
