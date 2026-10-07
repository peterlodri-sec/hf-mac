import Testing
import Foundation

@testable import HFMac

struct ProjectZeroTests {

    @Test("Default engine port is 8090 (8080 is taken by litellm)")
    func defaultPort() {
        #expect(projectZeroDefaultPort == 8090)
    }

    @Test("Client builds an OpenAI-compatible localhost base URL")
    func baseURL() {
        let client = ProjectZeroClient()
        #expect(client.base.absoluteString == "http://127.0.0.1:8090/v1")
    }

    @Test("Client honours a custom port")
    func customPort() {
        let client = ProjectZeroClient(port: 8099)
        #expect(client.base.absoluteString == "http://127.0.0.1:8099/v1")
    }

    @Test("Error descriptions are present for every case")
    func errorDescriptions() {
        #expect(ProjectZeroError.httpError(500).errorDescription?.contains("500") == true)
        #expect(ProjectZeroError.invalidResponse.errorDescription != nil)
        #expect(ProjectZeroError.decodeError(URLError(.badServerResponse)).errorDescription != nil)
    }

    @Test("engineBinary is nil when the repo is not built")
    func engineBinaryMissing() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pz-absent-\(UUID().uuidString)")
        #expect(ProjectZeroClient.engineBinary(in: tmp.path) == nil)
    }

    @Test("engineBinary finds an executable adaptive_ai_engine")
    func engineBinaryFound() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pz-present-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let bin = tmp.appendingPathComponent("adaptive_ai_engine")
        try Data("#!/bin/sh\n".utf8).write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(ProjectZeroClient.engineBinary(in: tmp.path) == bin.path)
    }

    @Test("InferenceSource exposes Project Zero with a CPU icon and a hint")
    func inferenceSourceWiring() {
        #expect(InferenceSource.allCases.contains(.projectZero))
        #expect(InferenceSource.projectZero.icon == "cpu")
        #expect(InferenceSource.projectZero.rawValue.contains("Project Zero"))
        #expect(InferenceSource.projectZero.emptyHint.contains("8090"))
    }
}
