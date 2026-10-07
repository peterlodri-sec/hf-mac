import Testing
import Foundation

@testable import HFMac

struct MiroFishTests {

    @Test("Default ports match MiroFish's Flask backend + Vue frontend")
    func defaultPorts() {
        #expect(miroFishDefaultPort == 5001)
        #expect(miroFishFrontendPort == 3000)
    }

    @Test("Client builds a localhost base URL over HTTP")
    func baseURL() {
        #expect(MiroFishClient().base.absoluteString == "http://127.0.0.1:5001")
        #expect(MiroFishClient(port: 5099).base.absoluteString == "http://127.0.0.1:5099")
    }

    @Test("Error descriptions are present")
    func errorDescriptions() {
        #expect(MiroFishError.httpError(503).errorDescription?.contains("503") == true)
        #expect(MiroFishError.invalidResponse.errorDescription != nil)
        #expect(MiroFishError.decodeError(URLError(.badServerResponse)).errorDescription != nil)
    }

    @Test("decodeList handles a bare array")
    func decodeBareArray() throws {
        let json = #"[{"id":"p1","name":"MiroFish demo"},{"project_id":"p2"}]"#
        let projects = MiroFishProject.decodeList(Data(json.utf8))
        #expect(projects.count == 2)
        #expect(projects[0].id == "p1")
        #expect(projects[0].name == "MiroFish demo")
        #expect(projects[1].id == "p2")
    }

    @Test("decodeList handles a nested object (projects/data/items)")
    func decodeNested() throws {
        let json = #"{"projects":[{"graph_id":"g1","title":"seed: wuhan"}]}"#
        let projects = MiroFishProject.decodeList(Data(json.utf8))
        #expect(projects.count == 1)
        #expect(projects[0].id == "g1")
        #expect(projects[0].name == "seed: wuhan")
    }

    @Test("decodeList tolerates junk without throwing")
    func decodeJunk() {
        #expect(MiroFishProject.decodeList(Data("not json".utf8)).isEmpty)
        #expect(MiroFishProject.decodeList(Data()).isEmpty)
    }
}
