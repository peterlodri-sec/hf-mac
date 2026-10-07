import Foundation

// MARK: - Toolchain (locate locally-installed companions)

/// Resolves the companion binaries hf.app drives as subprocesses — `entheai`,
/// `ayeosd`, `hf-mount`, `python3`, `accelerate`. They rarely live in
/// `/usr/local/bin`; on a real Mac they're in `~/.cargo/bin` (cargo install),
/// `/opt/homebrew/bin` (brew), or the Python framework. PATH is the source of
/// truth when the app runs unsandboxed, with a set of known-good fallbacks.
///
/// NOTE: under `app-sandbox` these paths are unreadable — the Developer-ID
/// build signs with `Packaging/hf-mac-devid.entitlements` (no sandbox) so the
/// subprocess lanes work; the sandbox stays for the App Store build.
enum Toolchain {
    /// Checked after `PATH`, in order. Covers cargo, brew (both prefixes),
    /// user-local, the Python.org framework, and the system.
    static let fallbackDirs: [String] = [
        "\(NSHomeDirectory())/.cargo/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.bun/bin",
        "/Library/Frameworks/Python.framework/Versions/3.12/bin",
    ]

    private static func isExec(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Resolve an executable by name.
    /// - Parameters:
    ///   - name: the binary name (e.g. `"entheai"`).
    ///   - override: an explicit path that wins if it exists.
    ///   - env: an environment variable that holds an explicit path.
    /// - Returns: the absolute path, or nil if not found.
    static func which(_ name: String, override: String? = nil, env: String? = nil) -> String? {
        if let override, !override.isEmpty, isExec(override) { return override }
        if let env, let v = ProcessInfo.processInfo.environment[env], !v.isEmpty, isExec(v) { return v }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = "\(dir)/\(name)"
                if isExec(candidate) { return candidate }
            }
        }
        for dir in fallbackDirs {
            let candidate = "\(dir)/\(name)"
            if isExec(candidate) { return candidate }
        }
        return nil
    }

    /// Resolve the first existing path from a list (for multi-name tools).
    static func which(_ names: [String]) -> String? {
        for n in names { if let p = which(n) { return p } }
        return nil
    }

    /// A human-readable dump of every companion the Ecosystem tab reports on.
    static func report() -> [(name: String, path: String)] {
        let probes: [(String, [String])] = [
            ("entheai", ["entheai"]),
            ("ayeosd", ["ayeosd", "ayeos"]),
            ("hf-mount", ["hf-mount", "hf_mount"]),
            ("python3", ["python3"]),
            ("accelerate", ["accelerate"]),
        ]
        return probes.map { (name, names) in
            (name, which(names) ?? "— not found")
        }
    }

    /// Print the report (used by `HFMac --check-tools`).
    static func printReport() {
        for row in report() {
            print("\(row.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(row.path)")
        }
    }
}

// MARK: - Errors

enum HubError: LocalizedError, Sendable {
    case invalidURL
    case networkError(HTTPURLResponse)
    case decodeError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid Hugging Face API URL."
        case .networkError(let resp): "Hugging Face API returned HTTP status \(resp.statusCode)."
        case .decodeError(let err): "Failed to parse Hugging Face data: \(err.localizedDescription)"
        }
    }
}

enum OsaurusError: LocalizedError, Sendable {
    case unreachable(String)
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unreachable(let msg): "Osaurus engine unreachable: \(msg)"
        case .httpError(let code): "Osaurus HTTP \(code) error."
        case .invalidResponse: "Invalid response from local model server."
        }
    }
}

// MARK: - Hugging Face Hub (models + spaces)

struct HubModel: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    var likes: Int?
    var downloads: Int?
    var pipeline_tag: String?
    var library_name: String?
}

/// A Hugging Face Space. `id` is "owner/name"; the live app is served at
/// https://<owner>-<name>.hf.space — which is exactly what we embed to make it
/// playable on the desktop (your quantum games, and any Gradio/static Space).
struct HFSpace: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    var likes: Int?
    var sdk: String?          // "gradio" | "streamlit" | "static" | "docker"
    var emoji: String?
    var host: String?         // authoritative embed host (from api/spaces/<id>); static → *.static.hf.space
    var subdomain: String?

    var owner: String { id.split(separator: "/").first.map(String.init) ?? id }
    var name: String { id.split(separator: "/").last.map(String.init) ?? id }

    /// Best embed URL from what we already have. Prefer the API `host` (correct
    /// for static vs gradio); else the subdomain; else a plain guess. The player
    /// resolves the authoritative host via `HubClient.spaceHost` before loading.
    var embedURL: URL {
        if let host, let u = URL(string: host) { return u }
        if let subdomain, !subdomain.isEmpty { return URL(string: "https://\(subdomain).hf.space")! }
        let guess = "\(owner)-\(name)".lowercased()
        return URL(string: "https://\(guess).hf.space")!
    }
}

struct HubClient: Sendable {
    var token: String?

    private func authed(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    func searchModels(_ query: String, limit: Int = 30) async throws -> [HubModel] {
        var c = URLComponents(string: "https://huggingface.co/api/models")!
        c.queryItems = [.init(name: "search", value: query), .init(name: "limit", value: String(limit)),
                        .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1")]
        guard let url = c.url else { throw HubError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(for: authed(url))
        guard let httpResp = resp as? HTTPURLResponse else { throw HubError.invalidURL }
        guard httpResp.statusCode == 200 else { throw HubError.networkError(httpResp) }
        do {
            return try JSONDecoder().decode([HubModel].self, from: data)
        } catch {
            throw HubError.decodeError(error)
        }
    }

    func searchSpaces(_ query: String, limit: Int = 40) async throws -> [HFSpace] {
        var c = URLComponents(string: "https://huggingface.co/api/spaces")!
        c.queryItems = [.init(name: "search", value: query), .init(name: "limit", value: String(limit)),
                        .init(name: "sort", value: "likes"), .init(name: "direction", value: "-1")]
        guard let url = c.url else { throw HubError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(for: authed(url))
        guard let httpResp = resp as? HTTPURLResponse else { throw HubError.invalidURL }
        guard httpResp.statusCode == 200 else { throw HubError.networkError(httpResp) }
        do {
            return try JSONDecoder().decode([HFSpace].self, from: data)
        } catch {
            throw HubError.decodeError(error)
        }
    }

    func spaces(author: String, limit: Int = 60) async throws -> [HFSpace] {
        var c = URLComponents(string: "https://huggingface.co/api/spaces")!
        c.queryItems = [.init(name: "author", value: author), .init(name: "limit", value: String(limit))]
        guard let url = c.url else { throw HubError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(for: authed(url))
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            if let httpResp = resp as? HTTPURLResponse { throw HubError.networkError(httpResp) }
            throw HubError.invalidURL
        }
        return try JSONDecoder().decode([HFSpace].self, from: data)
    }

    func models(author: String, limit: Int = 60) async throws -> [HubModel] {
        var c = URLComponents(string: "https://huggingface.co/api/models")!
        c.queryItems = [.init(name: "author", value: author), .init(name: "limit", value: String(limit)),
                        .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1")]
        guard let url = c.url else { throw HubError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(for: authed(url))
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            if let httpResp = resp as? HTTPURLResponse { throw HubError.networkError(httpResp) }
            throw HubError.invalidURL
        }
        return try JSONDecoder().decode([HubModel].self, from: data)
    }

    /// Fetch a Space's authoritative embed host (correct for static vs gradio).
    func spaceHost(_ id: String) async -> URL? {
        guard let (data, resp) = try? await URLSession.shared.data(for: authed(URL(string: "https://huggingface.co/api/spaces/\(id)")!)),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let host = obj["host"] as? String, let u = URL(string: host) { return u }
        if let sub = obj["subdomain"] as? String { return URL(string: "https://\(sub).hf.space") }
        return nil
    }

    /// List a Space's files (for offline snapshot). Static spaces = plain files.
    func spaceFiles(_ id: String) async throws -> [String] {
        guard let url = URL(string: "https://huggingface.co/api/spaces/\(id)/tree/main?recursive=true") else { return [] }
        let (data, resp) = try await URLSession.shared.data(for: authed(url))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return arr.compactMap { ($0["type"] as? String) == "file" ? $0["path"] as? String : nil }
    }

    /// Download a Space's full file tree into the offline store → playable offline.
    /// Returns the number of files written. (Best for `static` Spaces.)
    func downloadSpace(_ id: String) async throws -> Int {
        let files = try await spaceFiles(id)
        let dir = OfflineStore.spaceDir(id)
        var written = 0
        for path in files {
            guard let safePath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let src = URL(string: "https://huggingface.co/spaces/\(id)/resolve/main/\(safePath)") else { continue }
            let (data, resp) = try await URLSession.shared.data(for: authed(src))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            try OfflineStore.write(data, to: dir.appending(path: path))
            written += 1
        }
        return written
    }

    /// token -> your username (nil if no/invalid token).
    func whoami() async throws -> String? {
        guard token?.isEmpty == false else { return nil }
        let (data, resp) = try await URLSession.shared.data(for: authed(URL(string: "https://huggingface.co/api/whoami-v2")!))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["name"] as? String
    }
}

// MARK: - Osaurus (local inference)

struct OsaurusModel: Identifiable, Decodable, Hashable, Sendable { let id: String }
private struct OsaurusModelList: Decodable { let data: [OsaurusModel] }

struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var role: String
    var content: String
}

/// Osaurus local API (localhost:1337). OpenAI-compatible for chat + models,
/// Ollama-compatible /api/pull for pulling. API key optional (sent if set).
struct OsaurusClient: Sendable {
    var base = URL(string: "http://127.0.0.1:1337")!
    var apiKey: String?

    private func req(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: base.appending(path: path))
        r.httpMethod = method
        if let apiKey, !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return r
    }

    func models() async throws -> [OsaurusModel] {
        let (data, resp) = try await URLSession.shared.data(for: req("/v1/models"))
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            throw OsaurusError.httpError(code)
        }
        return try JSONDecoder().decode(OsaurusModelList.self, from: data).data
    }

    func chat(model: String, messages: [ChatMessage]) async throws -> String {
        var r = req("/v1/chat/completions", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
        ])
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard let httpResp = resp as? HTTPURLResponse else { throw OsaurusError.invalidResponse }
            guard httpResp.statusCode == 200 else { throw OsaurusError.httpError(httpResp.statusCode) }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = obj?["choices"] as? [[String: Any]]
            let msg = choices?.first?["message"] as? [String: Any]
            let output = (msg?["content"] as? String) ?? "(no content)"
            trace(model: model, output: output, durationMs: Date().timeIntervalSince(start) * 1000, errorDescription: nil)
            return output
        } catch {
            trace(model: model, output: nil, durationMs: Date().timeIntervalSince(start) * 1000, errorDescription: error.localizedDescription)
            throw error
        }
    }

    /// Fire-and-forget opt-in Langfuse trace — no-op unless env vars are set.
    private func trace(model: String, output: String?, durationMs: Double, errorDescription: String?) {
        guard LangfuseTracer.isEnabled else { return }
        Task {
            await LangfuseTracer.traceChat(model: model, inputTokens: nil, output: output, durationMs: durationMs, errorDescription: errorDescription)
        }
    }

    /// Streaming chat — yields content deltas as the model generates them
    /// (OpenAI-compatible SSE). Lets the UI fill token-by-token at the model's
    /// real tokens/sec instead of blocking on the whole reply.
    func chatStream(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var r = req("/v1/chat/completions", method: "POST")
                    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    r.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                    ])
                    let (bytes, resp) = try await URLSession.shared.bytes(for: r)
                    guard let http = resp as? HTTPURLResponse else { throw OsaurusError.invalidResponse }
                    guard http.statusCode == 200 else { throw OsaurusError.httpError(http.statusCode) }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let piece = delta["content"] as? String, !piece.isEmpty
                        else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Best-effort Ollama-style pull. Returns the HTTP status line for honesty.
    func pull(_ model: String) async throws -> String {
        var r = req("/api/pull", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": false])
        let (_, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return code == 200 ? "pulling \(model)…" : "Osaurus returned HTTP \(code) (needs an API key? set it in Settings)"
    }
}

// MARK: - Vaked (coder.vaked.dev free inference)

enum VakedError: LocalizedError, Sendable {
    case httpError(Int)
    case invalidResponse
    case decodeError(Error)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "coder.vaked.dev HTTP \(code)."
        case .invalidResponse: "Invalid response from coder.vaked.dev."
        case .decodeError(let err): "Failed to parse coder.vaked.dev response: \(err.localizedDescription)"
        }
    }
}

let vakedBaseURL = URL(string: "https://coder.vaked.dev/v1")!

/// coder.vaked.dev free inference — OpenAI-compatible, no key required.
/// Serves Qwen3-Coder-30B and Qwen2.5-Coder-14B on CPU (free tier).
struct VakedClient: Sendable {
    var base: URL = vakedBaseURL

    private func req(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: base.appending(path: path))
        r.httpMethod = method
        r.timeoutInterval = 60
        return r
    }

    /// List available models on the remote node.
    func models() async throws -> [OsaurusModel] {
        let (data, resp) = try await URLSession.shared.data(for: req("/models"))
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            throw VakedError.httpError(code)
        }
        // OpenAI-compatible model list: { object: "list", data: [{ id, object, created, owned_by }] }
        struct VakedModelList: Decodable {
            let data: [OsaurusModel]
        }
        do {
            return try JSONDecoder().decode(VakedModelList.self, from: data).data
        } catch {
            throw VakedError.decodeError(error)
        }
    }

    /// Non-streaming chat.
    func chat(model: String, messages: [ChatMessage]) async throws -> String {
        var r = req("/chat/completions", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
        ])
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let httpResp = resp as? HTTPURLResponse else { throw VakedError.invalidResponse }
        guard httpResp.statusCode == 200 else { throw VakedError.httpError(httpResp.statusCode) }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = obj?["choices"] as? [[String: Any]]
        let msg = choices?.first?["message"] as? [String: Any]
        return (msg?["content"] as? String) ?? "(no content)"
    }

    /// Streaming chat — SSE-compatible, same pattern as OsaurusClient.
    func chatStream(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var r = req("/chat/completions", method: "POST")
                    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    r.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                    ])
                    let (bytes, resp) = try await URLSession.shared.bytes(for: r)
                    guard let http = resp as? HTTPURLResponse else { throw VakedError.invalidResponse }
                    guard http.statusCode == 200 else { throw VakedError.httpError(http.statusCode) }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let piece = delta["content"] as? String, !piece.isEmpty
                        else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Project Zero (local CPU ternary inference)

enum ProjectZeroError: LocalizedError, Sendable {
    case httpError(Int)
    case invalidResponse
    case decodeError(Error)

    var errorDescription: String? {
        switch self {
        case .httpError(let code): "Project Zero HTTP \(code)."
        case .invalidResponse: "Invalid response from the Project Zero engine."
        case .decodeError(let err): "Failed to parse the Project Zero response: \(err.localizedDescription)"
        }
    }
}

/// Default port for the local engine. `8080` is taken on this Mac (litellm
/// caddy), so Project Zero is seated on `8090` — matching `bridge/setup-project-zero.sh`.
let projectZeroDefaultPort: UInt16 = 8090

/// `shifulegend/project-zero` — a dependency-free C99 ternary (BitNet b1.58)
/// CPU inference engine, served locally by `adaptive_ai_engine --model X.gguf
/// --server --port 8090`. OpenAI-compatible, no key. The **C cousin** of the
/// 8b-is stack: weights stay ternary the whole way, one scale at the end
/// (see `docs/project-zero.md` and `8b-is-engine/docs/project-zero-bridge.md`).
struct ProjectZeroClient: Sendable {
    var base: URL

    init(port: UInt16 = projectZeroDefaultPort, host: String = "127.0.0.1") {
        self.base = URL(string: "http://\(host):\(port)/v1")!
    }

    private func req(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: base.appending(path: path))
        r.httpMethod = method
        r.timeoutInterval = 120          // CPU decode is slow; be patient, not wrong
        return r
    }

    /// List models the running engine exposes (usually one: the loaded GGUF).
    func models() async throws -> [OsaurusModel] {
        let (data, resp) = try await URLSession.shared.data(for: req("/models"))
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 500
            throw ProjectZeroError.httpError(code)
        }
        struct ZeroModelList: Decodable { let data: [OsaurusModel] }
        do {
            return try JSONDecoder().decode(ZeroModelList.self, from: data).data
        } catch {
            throw ProjectZeroError.decodeError(error)
        }
    }

    /// Non-streaming chat (OpenAI-compatible `/v1/chat/completions`).
    func chat(model: String, messages: [ChatMessage]) async throws -> String {
        var r = req("/chat/completions", method: "POST")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
        ])
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            guard let httpResp = resp as? HTTPURLResponse else { throw ProjectZeroError.invalidResponse }
            guard httpResp.statusCode == 200 else { throw ProjectZeroError.httpError(httpResp.statusCode) }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = obj?["choices"] as? [[String: Any]]
            let msg = choices?.first?["message"] as? [String: Any]
            let output = (msg?["content"] as? String) ?? "(no content)"
            trace(model: model, output: output, durationMs: Date().timeIntervalSince(start) * 1000, errorDescription: nil)
            return output
        } catch {
            trace(model: model, output: nil, durationMs: Date().timeIntervalSince(start) * 1000, errorDescription: error.localizedDescription)
            throw error
        }
    }

    /// Fire-and-forget opt-in Langfuse trace — no-op unless env vars are set.
    private func trace(model: String, output: String?, durationMs: Double, errorDescription: String?) {
        guard LangfuseTracer.isEnabled else { return }
        Task {
            await LangfuseTracer.traceChat(model: model, inputTokens: nil, output: output, durationMs: durationMs, errorDescription: errorDescription)
        }
    }

    /// Streaming chat — same SSE shape as `OsaurusClient`/`VakedClient`.
    func chatStream(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var r = req("/chat/completions", method: "POST")
                    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    r.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                    ])
                    let (bytes, resp) = try await URLSession.shared.bytes(for: r)
                    guard let http = resp as? HTTPURLResponse else { throw ProjectZeroError.invalidResponse }
                    guard http.statusCode == 200 else { throw ProjectZeroError.httpError(http.statusCode) }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let piece = delta["content"] as? String, !piece.isEmpty
                        else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Where the built engine lands after `make release` in the repo. Returns
    /// the first executable found under the usual build paths (nil if unbuilt).
    static func engineBinary(in repoPath: String = "\(NSHomeDirectory())/project-zero") -> String? {
        let root = URL(fileURLWithPath: repoPath)
        let candidates = [
            root.appending(path: "adaptive_ai_engine"),
            root.appending(path: "build/adaptive_ai_engine"),
            root.appending(path: "bin/adaptive_ai_engine"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }?.path
    }
}

// MARK: - Articles (offline-first reader)

struct Article: Identifiable, Hashable, Sendable {
    let title: String
    let link: String
    let summary: String
    var source: String
    var id: String { link }
}

/// Aggregates article feeds and caches their HTML for offline reading. Uses each
/// site's `llms.txt` (a clean `- [title](url): desc` markdown list) rather than
/// XML — simpler and robust. Starts with your pocoo essays; add sources freely.
struct ArticleService: Sendable {
    static let sources: [(name: String, llms: URL)] = [
        ("pocoo", URL(string: "https://pocoo.vaked.dev/llms.txt")!),
        ("8b public docs", URL(string: "https://8b.is/llms.txt")!),
        ("entheai docs", URL(string: "https://entheai.com/llms.txt")!),
        ("vaked docs", URL(string: "https://vaked.dev/llms.txt")!),
    ]

    func fetch() async -> [Article] {
        var out: [Article] = []
        for src in Self.sources {
            guard let (data, resp) = try? await URLSession.shared.data(from: src.llms),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { continue }
            for raw in text.split(separator: "\n") {
                let line = String(raw)
                guard line.hasPrefix("- ["),
                      let t0 = line.firstIndex(of: "["), let t1 = line.firstIndex(of: "]"),
                      let u0 = line.firstIndex(of: "("), let u1 = line.firstIndex(of: ")"),
                      line.index(after: t0) < t1, line.index(after: u0) < u1 else { continue }
                let title = String(line[line.index(after: t0)..<t1])
                let link = String(line[line.index(after: u0)..<u1])
                guard link.contains("/posts/") else { continue }
                var summary = ""
                if let colon = line.range(of: "): ") { summary = String(line[colon.upperBound...]) }
                out.append(Article(title: title, link: link, summary: summary, source: src.name))
            }
        }
        return out
    }

    /// Download + cache an article's HTML for offline reading. Returns the local file.
    @discardableResult
    func cache(_ article: Article) async -> URL? {
        guard let url = URL(string: article.link),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let dest = OfflineStore.articleFile(article.link)
        try? OfflineStore.write(data, to: dest)
        return dest
    }
}

// MARK: - ayeOS (ternary inference daemon — MEMNET protocol)

/// Error types for ayeOS MEMNET communication.
enum AyeosError: LocalizedError, Sendable {
    case unreachable(String)
    case invalidResponse
    case protocolError(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let msg): "ayeOS daemon unreachable: \(msg)"
        case .invalidResponse: "Invalid response from ayeOS MEMNET."
        case .protocolError(let msg): "ayeOS protocol error: \(msg)"
        }
    }
}

/// MEMNET capsule response from ayeOS.
struct AyeosCapsule: Decodable, Sendable {
    let capsule_id: String
    let payload_type: String
    let relevance_score: Float
    let timestamp: UInt64
}

/// ayeOS daemon client — MEMNET over the daemon's local **UNIX socket**
/// (`/tmp/ayeosd.sock`, override `AYEOSD_SOCK`). The AyeFire covenant means
/// there is no IP listener; `ayeosd` binds a local socket (no backdoor).
/// Commands: ping, stats, capsule, get matrix.
struct AyeosClient: Sendable {
    /// The daemon's UNIX socket. ayeOS honours `AYEOSD_SOCK`; we mirror it.
    /// (The AyeFire covenant means there is **no IP listener** — dialing
    /// TCP:9876 is always "unreachable".)
    var socketPath: String

    init(socketPath: String? = nil) {
        self.socketPath = socketPath
            ?? ProcessInfo.processInfo.environment["AYEOSD_SOCK"]
            ?? "/tmp/ayeosd.sock"
    }

    /// Send a newline-terminated command over the daemon's UNIX socket and read
    /// until it closes the connection (it writes the whole response, then drops
    /// the stream). Unix domain sockets need a POSIX `AF_UNIX` connect —
    /// `CFStream`'s host pair only does TCP.
    func sendCommand(_ cmd: String) async throws -> String {
        let path = socketPath
        let command = cmd
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            DispatchQueue.global().async {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    c.resume(throwing: AyeosError.unreachable("socket() failed"))
                    return
                }
                defer { close(fd) }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = Array(path.utf8)
                guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
                    c.resume(throwing: AyeosError.unreachable("socket path too long: \(path)"))
                    return
                }
                pathBytes.withUnsafeBufferPointer { src in
                    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                        ptr.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count) { dst in
                            dst.update(from: src.baseAddress!, count: pathBytes.count)
                        }
                    }
                }

                let rc = withUnsafePointer(to: &addr) { a in
                    a.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard rc == 0 else {
                    c.resume(throwing: AyeosError.unreachable(String(cString: strerror(errno))))
                    return
                }

                var payload = Array((command + "\n").utf8)
                _ = payload.withUnsafeMutableBytes { write(fd, $0.baseAddress, $0.count) }

                var response = Data()
                var buf = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = read(fd, &buf, buf.count)
                    if n <= 0 { break }
                    response.append(contentsOf: buf[0..<n])
                }
                c.resume(returning: String(data: response, encoding: .utf8) ?? "")
            }
        }
    }

    /// Check if the ayeOS daemon is reachable.
    var isReachable: Bool {
        get async {
            (try? await sendCommand("ping"))?.contains("pong") ?? false
        }
    }

    /// Fetch a MEMNET capsule by name (default: genesis).
    func capsule(named name: String = "genesis") async throws -> AyeosCapsule {
        let resp = try await sendCommand("capsule \(name)")
        guard let data = resp.data(using: .utf8),
              let capsule = try? JSONDecoder().decode(AyeosCapsule.self, from: data)
        else { throw AyeosError.invalidResponse }
        return capsule
    }

    /// List all loaded capsules.
    func listCapsules() async throws -> [String] {
        let resp = try await sendCommand("list")
        guard let data = resp.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
        else { throw AyeosError.invalidResponse }
        return obj["capsules"] ?? []
    }

    /// Fetch system stats.
    func stats() async throws -> String {
        try await sendCommand("stats")
    }
}

// MARK: - entheai (agent subprocess)

/// Error types for entheai agent communication.
enum EntheaiError: LocalizedError, Sendable {
    case notFound(String)
    case executionError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notFound(let path): "entheai binary not found at \(path)"
        case .executionError(let msg): "entheai error: \(msg)"
        case .timeout: "entheai agent timed out"
        }
    }
}

/// entheai agent result.
struct EntheaiResult: Decodable, Sendable {
    let output: String
    let tool_calls: Int?
    let duration_ms: UInt64?
}

/// Client that runs entheai as a subprocess for agent tasks.
/// Communicates via CLI args (one-shot mode) or stdin/stdout JSON-RPC.
struct EntheaiClient: Sendable {
    var binaryPath: String = Toolchain.which("entheai", env: "ENTHEAI_BIN") ?? "/usr/local/bin/entheai"
    var timeoutSecs: UInt64 = 120

    /// Build the entheai argv. The prompt is **positional** (last); `--prompt`
    /// does not exist. `--fanout` is a flag. Kept pure so it is unit-testable.
    static func arguments(prompt: String, model: String? = nil, yolo: Bool = false, fanout: Bool = false, companion: Bool = false) -> [String] {
        var args: [String] = []
        if let model { args += ["--model", model] }
        if yolo { args += ["--yolo"] }
        if fanout { args += ["--fanout"] }
        if !companion { args += ["--no-companion"] }
        args.append(prompt)
        return args
    }

    /// Gate for `run()`'s checked continuation: the timeout path and the
    /// completion path race — `terminate()` unblocks `waitUntilExit()`, so
    /// both would resume and trip Swift's "continuation resumed twice" trap
    /// (the v0.12.0 background crash). First signal wins; the second is
    /// dropped.
    final class ContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func resumeOnce(_ action: () -> Void) {
            lock.lock()
            if used {
                lock.unlock()
                return
            }
            used = true
            lock.unlock()
            action()
        }
    }

    /// Run entheai with a prompt and optional flags.
    ///
    /// entheai takes the prompt **positionally** (`entheai [OPTIONS] [PROMPT]`),
    /// not via `--prompt` — passing `--prompt` was the launch error. `--fanout`
    /// is a flag, not a subcommand. `--no-companion` keeps the agent headless
    /// (no WezTerm/Ghostty window) since we spawn it from the app.
    func run(prompt: String, model: String? = nil, yolo: Bool = false, fanout: Bool = false, companion: Bool = false) async throws -> EntheaiResult {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw EntheaiError.notFound(binaryPath)
        }
        let capturedArgs = EntheaiClient.arguments(prompt: prompt, model: model, yolo: yolo, fanout: fanout, companion: companion)
        return try await withCheckedThrowingContinuation { c in
            let gate = ContinuationGate()
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = capturedArgs

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    let deadline = DispatchTime.now() + .seconds(Int(timeoutSecs))
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            process.terminate()
                            gate.resumeOnce { c.resume(throwing: EntheaiError.timeout) }
                        }
                    }
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outData, encoding: .utf8) ?? ""
                    let error = String(data: errData, encoding: .utf8) ?? ""
                    if !error.isEmpty {
                        let combined = output + "\n(stderr: \(error))"
                        gate.resumeOnce { c.resume(returning: EntheaiResult(output: combined, tool_calls: nil, duration_ms: nil)) }
                    } else {
                        gate.resumeOnce { c.resume(returning: EntheaiResult(output: output, tool_calls: nil, duration_ms: nil)) }
                    }
                } catch {
                    gate.resumeOnce { c.resume(throwing: EntheaiError.executionError(error.localizedDescription)) }
                }
            }
        }
    }

    /// Run entheai with fan-out decomposition.
    func fanout(prompt: String) async throws -> EntheaiResult {
        try await run(prompt: prompt, yolo: true, fanout: true)
    }
}

// MARK: - hf-mount (Hugging Face FUSE/NFS filesystem)

/// Error types for hf-mount operations.
enum HFMountError: LocalizedError, Sendable {
    case notFound(String)
    case mountFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path): "hf-mount not found at \(path)"
        case .mountFailed(let msg): "mount failed: \(msg)"
        case .unmountFailed(let msg): "unmount failed: \(msg)"
        }
    }
}

/// Status of a hf-mount mount point.
struct HFMountStatus: Codable, Sendable {
    let mount_point: String
    let source: String
    let backend: String  // "nfs" | "fuse"
    let pid: Int?
}

/// Wraps the `hf-mount` CLI binary — mounts HF repos/buckets as local
/// filesystems via FUSE or NFS. Lazily fetches files on first read.
///
/// Install: `brew install hf-mount` or download from GitHub Releases.
struct HFMountClient: Sendable {
    var binaryPath: String = Toolchain.which("hf-mount", env: "HF_MOUNT_BIN") ?? "/opt/homebrew/bin/hf-mount"
    var hfToken: String = ""

    /// Check if hf-mount is installed (PATH + known dirs).
    var isAvailable: Bool {
        Toolchain.which("hf-mount", override: binaryPath) != nil
    }

    /// Resolve the binary path.
    private func resolveBinary() -> String? {
        Toolchain.which("hf-mount", override: binaryPath)
    }

    /// Mount a HF repo as a local filesystem.
    /// - Parameters:
    ///   - repo: "owner/name" or "bucket owner/name"
    ///   - mountPoint: local path to mount at
    ///   - type: "repo" (read-only) or "bucket" (read-write)
    ///   - backend: "nfs" (default) or "fuse"
    /// - Returns: true if mount succeeded
    func mount(repo: String, mountPoint: String, type: String = "repo", backend: String = "nfs") async throws -> Bool {
        guard let bin = resolveBinary() else { throw HFMountError.notFound("hf-mount") }
        var args = ["start", type, repo, mountPoint, "--backend", backend]
        if !hfToken.isEmpty { args += ["--hf-token", hfToken] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        let outPipe = Pipe()
        process.standardOutput = outPipe

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Unmount a previously mounted path.
    func unmount(mountPoint: String) async throws {
        guard let bin = resolveBinary() else { throw HFMountError.notFound("hf-mount") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["stop", mountPoint]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw HFMountError.unmountFailed("exit code \(process.terminationStatus)")
        }
    }

    /// List active mount points.
    func listMounts() async -> [HFMountStatus] {
        guard let bin = resolveBinary() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["status"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // Parse "mount_point  source  backend  pid" lines
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 3 else { return nil }
            return HFMountStatus(
                mount_point: parts[0],
                source: parts[1],
                backend: parts[2],
                pid: parts.count > 3 ? Int(parts[3]) : nil
            )
        }
    }
}

// MARK: - Hugging Face Accelerate (distributed training/mixed precision)

/// Error types for accelerate operations.
enum AccelerateError: LocalizedError, Sendable {
    case notFound
    case executionError(String)

    var errorDescription: String? {
        switch self {
        case .notFound: "accelerate not found. pip install accelerate"
        case .executionError(let msg): "accelerate error: \(msg)"
        }
    }
}

/// Accelerate device configuration.
enum AccelerateDevice: String, Sendable {
    case auto = "auto"
    case cpu = "cpu"
    case mps = "mps"       // Apple Metal Performance Shaders
    case cuda = "cuda"
}

/// Wraps Hugging Face Accelerate (Python) for device-aware training/inference.
/// Bridges Swift → Python subprocess → Metal via MPS backend.
///
/// Accelerate automatically handles:
/// - Device placement (CPU / MPS / CUDA)
/// - Mixed precision (fp16, bf16, fp8)
/// - FSDP / DeepSpeed for multi-device
/// - Gradient accumulation
///
/// Invoked as `python3 -m accelerate ...` with JSON serialization.
struct AccelerateClient: Sendable {
    var pythonPath: String = Toolchain.which("python3", env: "PYTHON_BIN") ?? "/usr/bin/python3"
    /// The `accelerate` console script, resolved directly when present — lets
    /// `isAvailable` answer without spawning a probe subprocess.
    var acceleratePath: String? = Toolchain.which("accelerate", env: "ACCELERATE_BIN")
    var device: AccelerateDevice = .mps

    /// Check if accelerate is installed (the direct script, else `python -m`).
    var isAvailable: Bool {
        if acceleratePath != nil { return true }
        return pythonHasAccelerate
    }

    private var pythonHasAccelerate: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "accelerate", "--help"]
        let pipe = Pipe()
        process.standardError = pipe
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Run a training/inference script under accelerate.
    /// - Parameters:
    ///   - script: Python script path
    ///   - args: Additional arguments passed to the script
    ///   - config: Accelerate config overrides (device_placement, mixed_precision, etc.)
    /// - Returns: stdout from the accelerate run
    func run(script: String, args: [String] = [], config: [String: String] = [:]) async throws -> String {
        guard isAvailable else { throw AccelerateError.notFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)

        var accelerateArgs = ["-m", "accelerate", "launch"]
        // Default to MPS on Apple Silicon
        if device == .mps {
            accelerateArgs += ["--cpu", "false", "--num_processes", "1"]
        }
        accelerateArgs += [script] + args
        process.arguments = accelerateArgs

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let error = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw AccelerateError.executionError(error.isEmpty ? output : error)
        }
        return output
    }
}

// MARK: - Process lifecycle manager

/// Manages lifecycle of companion subprocesses (entheai, ayeOS).
/// Launches, monitors, and reports availability to the UI.
@MainActor
@Observable
final class ProcessManager {
    /// Whether entheai agent binary is available.
    var entheaiAvailable = false
    /// Whether ayeOS daemon binary is available.
    var ayeosAvailable = false
    /// Whether ayeOS is reachable on its TCP port.
    var ayeosReachable = false
    /// Status notes for the UI.
    var note: String?

    private let ayeosClient = AyeosClient()
    private let entheaiClient: EntheaiClient

    init(entheaiPath: String = Toolchain.which("entheai", env: "ENTHEAI_BIN") ?? "/usr/local/bin/entheai") {
        self.entheaiClient = EntheaiClient(binaryPath: entheaiPath)
        checkAvailability()
    }

    /// Resolved paths, for the Ecosystem tab (nil when the tool is absent).
    var entheaiPath: String? { Toolchain.which("entheai", override: entheaiClient.binaryPath) }
    var ayeosPath: String? { Toolchain.which(["ayeosd", "ayeos"]) }

    /// Check which binaries are available on disk — resolved through PATH and
    /// the usual local install dirs (~/.cargo/bin, /opt/homebrew/bin, …), not a
    /// hardcoded /usr/local/bin.
    func checkAvailability() {
        entheaiAvailable = entheaiPath != nil
        ayeosAvailable = ayeosPath != nil
    }

    /// Check ayeOS reachability over MEMNET.
    func checkAyeosReachability() async {
        ayeosReachable = await ayeosClient.isReachable
    }

    /// Run entheai agent with a prompt.
    func runEntheai(prompt: String, model: String? = nil) async -> String? {
        guard entheaiAvailable else { note = "entheai binary not found"; return nil }
        do {
            let result = try await entheaiClient.run(prompt: prompt, model: model)
            return result.output
        } catch {
            note = "entheai: \(error.localizedDescription)"
            return nil
        }
    }

    /// Run entheai with fan-out decomposition.
    func fanout(prompt: String) async -> String? {
        guard entheaiAvailable else { note = "entheai binary not found"; return nil }
        do {
            let result = try await entheaiClient.fanout(prompt: prompt)
            return result.output
        } catch {
            note = "entheai fanout: \(error.localizedDescription)"
            return nil
        }
    }

    /// Fetch ayeOS capsule metadata.
    func ayeosCapsule(named name: String = "genesis") async -> AyeosCapsule? {
        guard ayeosReachable else { return nil }
        return try? await ayeosClient.capsule(named: name)
    }

    /// List all loaded ayeOS capsules.
    func ayeosCapsules() async -> [String] {
        guard ayeosReachable else { return [] }
        return (try? await ayeosClient.listCapsules()) ?? []
    }
}

// MARK: - Google Drive (the cloud lane)

/// Google Drive client — list / download files via the Drive v3 API.
/// Token held in Keychain ("google_drive_token"), never on disk in the clear.
/// Read-only in v1 (list + fetch metadata); the upload lane is a follow-up.
struct GoogleDriveClient: Sendable {
    var token: String = ""

    /// True when a Drive token is present (user connected the lane).
    var isConnected: Bool { !token.isEmpty }

    /// List the first `limit` files in the Drive root, name + mime + id.
    func listFiles(limit: Int = 50) async throws -> [DriveFile] {
        guard !token.isEmpty else { throw DriveError.notConnected }
        var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        url.queryItems = [
            URLQueryItem(name: "pageSize", value: String(limit)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
        ]
        var req = URLRequest(url: url.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw DriveError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct List: Decodable { let files: [DriveFile] }
        return try JSONDecoder().decode(List.self, from: data).files
    }

    /// Resolve the Drive token from the Keychain.
    static func loadToken() -> String {
        Keychain.get("google_drive_token") ?? ""
    }
}

struct DriveFile: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let mimeType: String?
    let size: String?
}

enum DriveError: LocalizedError {
    case notConnected
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .notConnected: "Google Drive not connected — set a token in Keychain."
        case .http(let code): "Google Drive API returned HTTP \(code)."
        }
    }
}
