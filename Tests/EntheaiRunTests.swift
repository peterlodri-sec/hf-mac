import Testing
import Foundation

@testable import HFMac

/// Regression tests for the v0.12.0 background crash: `EntheaiClient.run`
/// could resume its checked continuation twice when the timeout fired and
/// `terminate()` unblocked `waitUntilExit()` — Swift then traps with
/// "continuation resumed more than once" (EXC_BREAKPOINT, Services.swift
/// `closure #1 in EntheaiClient.run`).
struct EntheaiRunTests {

    @Test("ContinuationGate lets exactly the first resume through")
    func gateResumesOnce() {
        let gate = EntheaiClient.ContinuationGate()
        var count = 0
        gate.resumeOnce { count += 1 }
        gate.resumeOnce { count += 1 }
        gate.resumeOnce { count += 1 }
        #expect(count == 1)
    }

    @Test("A timeout produces one .timeout error — no double-resume trap")
    func timeoutResumesExactlyOnce() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfmac-slow-\(UUID().uuidString).sh")
        try "#!/bin/sh\nsleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }

        var client = EntheaiClient()
        client.binaryPath = script.path
        client.timeoutSecs = 1

        do {
            _ = try await client.run(prompt: "ignored by the script")
            Issue.record("expected a timeout, got a result")
        } catch let error as EntheaiError {
            guard case .timeout = error else {
                Issue.record("expected .timeout, got \(error)")
                return
            }
        }
    }

    @Test("A fast, well-behaved process still returns its output")
    func happyPathStillResolves() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("hfmac-fast-\(UUID().uuidString).sh")
        try "#!/bin/sh\necho hello-from-the-test\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }

        var client = EntheaiClient()
        client.binaryPath = script.path
        client.timeoutSecs = 10

        let result = try await client.run(prompt: "ignored")
        #expect(result.output.contains("hello-from-the-test"))
    }
}
