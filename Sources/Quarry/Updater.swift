import AppKit
import CryptoKit
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
    static let publicKey = Bundle.main.object(forInfoDictionaryKey: "QuarryUpdateKey") as? String
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    static func isNewer(_ tag: String, than current: String) -> Bool {
        String(tag.trimmingPrefix("v")).compare(current, options: .numeric) == .orderedDescending
    }

    /// nil = Quarry ist aktuell.
    static func latest() async throws -> Release? {
        guard let repo, !repo.isEmpty else { throw QuarryError.noUpdateServer }
        // Ohne Cache: GitHub erlaubt 60 s Zwischenspeicher, sonst sieht „Nach Updates suchen“ neue Versionen nicht.
        let data = try await Modrinth.fetch(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, fresh: true)
        let r = try Modrinth.decoder.decode(Release.self, from: data)
        return isNewer(r.tagName, than: current) ? r : nil
    }

    /// Lädt Quarry.zip, tauscht das App-Bundle nach dem Beenden aus und startet neu.
    static func install(_ r: Release) async throws {
        let fromGitHub = { (a: Release.Asset) in a.browserDownloadUrl.scheme == "https" && a.browserDownloadUrl.host == "github.com" }
        guard let asset = r.assets.first(where: { $0.name == "Quarry.zip" }), fromGitHub(asset),
              let sigAsset = r.assets.first(where: { $0.name == "Quarry.zip.sig" }), fromGitHub(sigAsset),
              let keyText = publicKey, let keyData = Data(base64Encoded: keyText),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw QuarryError.badFile("Update-Paket")
        }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "quarry-update-\(UUID().uuidString)")
        let (zip, resp) = try await URLSession.shared.download(from: asset.browserDownloadUrl)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuarryError.http(asset.browserDownloadUrl.absoluteString) }
        // Nur Updates annehmen, die mit dem privaten Release-Schlüssel signiert sind – schützt auch bei gekapertem GitHub-Konto.
        let sigText = String(decoding: try await Modrinth.fetch(sigAsset.browserDownloadUrl), as: UTF8.self)
        guard let sig = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(sig, for: try Data(contentsOf: zip)) else { throw QuarryError.badFile("Update-Signatur") }
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        let newApp = tmp.appending(path: "Quarry.app")
        // Nur ein echtes, unbeschädigtes Quarry-Bundle einsetzen.
        let newBundle = Bundle(url: newApp)
        let newVersion = newBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        // Kein Downgrade auf eine ältere (evtl. lückenhafte) signierte Version.
        guard newBundle?.bundleIdentifier == Bundle.main.bundleIdentifier, newVersion == r.version,
              isNewer(newVersion, than: current) else { throw QuarryError.badFile("Update-Paket") }
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
