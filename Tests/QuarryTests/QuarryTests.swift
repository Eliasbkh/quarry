import Foundation
import Testing
@testable import Quarry

let base = URL(filePath: "/tmp/inst")

@Test(arguments: ["../evil.jar", "/etc/passwd", "mods/../../x", "mods//a.jar", ""])
func `unsafe modpack paths are rejected`(path: String) {
    #expect(throws: QuarryError.self) { try Paths.safeDestination(base: base, path: path) }
}

@Test func `normal paths stay inside the instance`() throws {
    #expect(try Paths.safeDestination(base: base, path: "mods/sodium.jar").path == "/tmp/inst/mods/sodium.jar")
}

@Test func `project id is read from the Modrinth CDN url`() {
    #expect(Paths.modrinthProjectId(URL(string: "https://cdn.modrinth.com/data/AANobbMI/versions/x/sodium.jar")!) == "AANobbMI")
    #expect(Paths.modrinthProjectId(URL(string: "https://github.com/a/b/c.jar")!) == nil)
}

@Test(arguments: [(UInt64(4) << 30, "-Xmx2G"), (UInt64(16) << 30, "-Xmx8G"), (UInt64(64) << 30, "-Xmx8G"), (UInt64(8) << 30, "-Xmx4G")])
func `java memory is half the RAM, 2–8 GB`(ram: UInt64, expected: String) {
    #expect(Paths.javaArgs(physicalMemory: ram).contains(expected))
}

@Test(arguments: [("v0.2", "0.1", true), ("v0.10", "0.9", true), ("v0.1", "0.1", false), ("0.1", "0.2", false), ("v1.0.1", "1.0", true)])
func `update is offered only for newer versions`(tag: String, current: String, newer: Bool) {
    #expect(Updater.isNewer(tag, than: current) == newer)
}

@Test func `sha1 matches the known value`() {
    #expect(sha1Hex(Data("abc".utf8)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
}
