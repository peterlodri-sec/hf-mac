import Testing
import Foundation

@testable import HFMac

struct ToolchainTests {

    @Test("Resolves a system binary from PATH")
    func resolvesSystemBinary() {
        // `ls` is present on every macOS PATH.
        let ls = Toolchain.which("ls")
        #expect(ls != nil)
        #expect(FileManager.default.isExecutableFile(atPath: ls!))
    }

    @Test("Returns nil for an absent binary")
    func absentBinary() {
        #expect(Toolchain.which("hf-mac-definitely-not-installed-xyz") == nil)
    }

    @Test("An explicit override wins when it exists")
    func overrideWins() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(Toolchain.which("ls", override: tmp.path) == tmp.path)
    }

    @Test("Falls through names until one resolves")
    func multiNameFallsThrough() {
        #expect(Toolchain.which(["definitely-absent-xyz", "ls"]) != nil)
        #expect(Toolchain.which(["definitely-absent-xyz", "also-absent-abc"]) == nil)
    }

    @Test("Report covers every companion the Ecosystem tab shows")
    func reportCoverage() {
        let names = Set(Toolchain.report().map { $0.name })
        #expect(names == ["entheai", "ayeosd", "hf-mount", "python3", "accelerate"])
    }
}
