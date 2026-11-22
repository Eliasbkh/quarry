// Update-Signatur (Ed25519). Der private Schlüssel liegt nur in ~/.quarry-update-key – nie ins Repo!
//   swift scripts/sign-update.swift pubkey          → öffentlicher Schlüssel (kommt in die App)
//   swift scripts/sign-update.swift sign <datei>    → Signatur für ein Release
import CryptoKit
import Foundation

let keyURL = URL(filePath: NSHomeDirectory()).appending(path: ".quarry-update-key")
let key: Curve25519.Signing.PrivateKey
if let data = try? Data(contentsOf: keyURL) {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.write(to: keyURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "pubkey":
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign" where args.count == 3:
    print(try key.signature(for: Data(contentsOf: URL(filePath: args[2]))).base64EncodedString())
default:
    FileHandle.standardError.write(Data("Benutzung: pubkey | sign <datei>\n".utf8))
    exit(1)
}
