import Testing
import Foundation

@testable import HFMac

struct CompanionLaunchTests {

    // MARK: entheai — the prompt is positional, never `--prompt`

    @Test("Prompt is positional and last")
    func promptIsPositional() {
        let args = EntheaiClient.arguments(prompt: "hello world")
        #expect(args == ["--no-companion", "hello world"])
        #expect(!args.contains("--prompt"), "--prompt does not exist in entheai's CLI")
        #expect(args.last == "hello world")
    }

    @Test("All flags land before the positional prompt")
    func flagsBeforePrompt() {
        let args = EntheaiClient.arguments(prompt: "do it", model: "qwen", yolo: true, fanout: true, companion: true)
        #expect(args == ["--model", "qwen", "--yolo", "--fanout", "do it"])
        #expect(args.last == "do it")
    }

    @Test("Companion window is off by default, on when asked")
    func companionToggle() {
        #expect(EntheaiClient.arguments(prompt: "x").contains("--no-companion"))
        #expect(!EntheaiClient.arguments(prompt: "x", companion: true).contains("--no-companion"))
    }

    @Test("fanout() requests the --fanout flag")
    func fanoutFlag() {
        let args = EntheaiClient.arguments(prompt: "p", yolo: true, fanout: true)
        #expect(args.contains("--fanout"))
    }

    // MARK: ayeOS — the daemon is a UNIX socket, never TCP

    @Test("AyeosClient speaks over the daemon's UNIX socket")
    func ayeosUsesUnixSocket() {
        let socket = AyeosClient().socketPath
        #expect(socket.contains("ayeosd"))
        #expect(!socket.contains("9876"), "ayeOS binds a local socket, not TCP:9876")
    }

    @Test("An explicit socket path wins (no env mutation)")
    func ayeosSocketExplicit() {
        let custom = "/tmp/ayeosd-test-\(UUID().uuidString).sock"
        #expect(AyeosClient(socketPath: custom).socketPath == custom)
    }

    @Test("Live: the running daemon answers ping + list over its socket")
    func ayeosLivePing() async throws {
        let socket = AyeosClient().socketPath
        // Skip when the daemon isn't running (keeps the suite hermetic).
        guard FileManager.default.fileExists(atPath: socket) else { return }
        let client = AyeosClient(socketPath: socket)
        #expect(await client.isReachable)
        #expect(try await client.listCapsules().contains("genesis"))
    }
}
