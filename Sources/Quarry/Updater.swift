import AppKit
import Foundation

/// Selbst-Update über GitHub Releases. Das Repo („besitzer/quarry“) setzt build-app.sh in die Info.plist.
enum Updater {
    struct Release: Decodable, Identifiable {
        struct Asset: Decodable { let name: String; let browserDownloadUrl: URL }
        let tagName: String
        let body: String?
        let assets: [Asset]
        var id: String { tagName }
        var version: String { String(tagName.trimmingPrefix("v")) }
    }

    static let repo = Bundle.main.object(forInfoDictionaryKey: "QuarryUpdateRepo") as? String
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    static func isNewer(_ tag: String, than current: String) -> Bool {
        String(tag.trimmingPrefix("v")).compare(current, options: .numeric) == .orderedDescending
    }

    /// nil = Quarry ist aktuell.
    static func latest() async throws -> Release? {
        guard let repo, !repo.isEmpty else { throw QuarryError.noUpdateServer }
        let data = try await Modrinth.fetch(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        let r = try Modrinth.decoder.decode(Release.self, from: data)
        return isNewer(r.tagName, than: current) ? r : nil
    }

    /// Lädt Quarry.zip, tauscht das App-Bundle nach dem Beenden aus und startet neu.
    static func install(_ r: Release) async throws {
        guard let asset = r.assets.first(where: { $0.name == "Quarry.zip" }),
              asset.browserDownloadUrl.scheme == "https", asset.browserDownloadUrl.host == "github.com" else {
            throw QuarryError.badFile("Update-Paket")
        }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "quarry-update-\(UUID().uuidString)")
        let (zip, resp) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuarryError.http(asset.browserDownloadUrl.absoluteString) }
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        let newApp = tmp.appending(path: "Quarry.app")
        // Nur ein echtes, unbeschädigtes Quarry-Bundle einsetzen.
        guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw QuarryError.badFile("Update-Paket") }
        try runTool("/usr/bin/codesign", ["--verify", "--deep", newApp.path])

        let target = Bundle.main.bundleURL.path
        // Altes Bundle erst wegschieben; klappt das Einsetzen nicht, kommt es zurück.
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        mv "$1" "$3" && { mv "$2" "$1" || mv "$3" "$1"; }
        rm -rf "$3"; open "$1"
        """
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = ["-c", script, "sh", target, newApp.path, target + ".old"]
        try p.run()
        NSApp.terminate(nil)
    }
}

func runTool(_ path: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(filePath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw QuarryError.tool((path as NSString).lastPathComponent) }
}
