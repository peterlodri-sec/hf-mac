import SwiftUI

// hf.app — a native macOS Hugging Face client. Play Spaces on the desktop
// (your quantum games), read offline, and run models locally via Osaurus.
@main
struct HFMacApp: App {
    @State private var state = AppState()

    init() {
        // `HFMac --check-tools` — headless companion health check: resolve the
        // binaries, probe the ayeOS daemon over its socket, and preview the
        // entheai argv. Exits before the run loop, so it runs from a terminal
        // or CI.
        if CommandLine.arguments.contains("--check-tools") {
            SelfTest.run()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .task { await state.bootstrap() }
        }
        .defaultSize(width: 1140, height: 760)

        MenuBarExtra("HF-MAC", systemImage: "brain.head.profile") {
            MenuBarView().environment(state).tint(Theme.accent).preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(state).tint(Theme.accent).preferredColorScheme(.dark)
        }
    }
}

/// Which inference backend to use for chat.
enum InferenceSource: String, CaseIterable, Identifiable, Sendable {
    case local = "Osaurus (local)"
    case remote = "coder.vaked.dev (free)"
    case projectZero = "Project Zero (CPU)"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .local: "macbook"
        case .remote: "antenna.radiowaves.left.and.right"
        case .projectZero: "cpu"
        }
    }
    /// Short label for the status pill.
    var statusLabel: String {
        switch self {
        case .local: "on-device · Osaurus"
        case .remote: "coder.vaked.dev · free"
        case .projectZero: "on-device · Project Zero (C99)"
        }
    }
    /// Placeholder shown in the empty chat view when no model is selected.
    var emptyHint: String {
        switch self {
        case .local: "Pull a model in the Models tab, then talk to it here — nothing leaves your Mac."
        case .remote: "coder.vaked.dev should list models automatically. Try Refresh if empty."
        case .projectZero: "Start the engine first: adaptive_ai_engine --model <gguf> --server --port 8090 (see scripts/setup-project-zero.sh)."
        }
    }
}

@MainActor
@Observable
final class AppState {
    // Spaces (the focus — playable on desktop)
    var spaceQuery = ""
    var spaces: [HFSpace] = []
    var spacesLoading = false
    var openSpace: HFSpace?

    // Models
    var modelQuery = ""
    var models: [HubModel] = []
    var modelsLoading = false
    var pullingModel: String?

    // Yours (creator)
    var username: String?
    var mySpaces: [HFSpace] = []
    var myModels: [HubModel] = []

    // Run — inference source selector
    var inferenceSource: InferenceSource = .local
    // Osaurus (local)
    var osaurusModels: [OsaurusModel] = []
    var osaurusReachable = true
    var osaurusNote: String?
    // Vaked (remote)
    var vakedModels: [OsaurusModel] = []
    var vakedReachable = false
    var vakedNote: String?
    // Project Zero (local CPU ternary — shifulegend/project-zero)
    var projectZeroModels: [OsaurusModel] = []
    var projectZeroReachable = false
    var projectZeroNote: String?
    // MiroFish (local swarm-intelligence prediction — 666ghj/MiroFish, over HTTP)
    var miroFishReachable = false
    var miroFishProjects: [MiroFishProject] = []
    var miroFishNote: String?
    // Shared
    var selectedModel = ""
    var chat: [ChatMessage] = []
    var prompt = ""
    var generating = false
    var genTask: Task<Void, Never>?

    // MoE Optimizer Layer
    var moeEnabled = true
    var activeDomain: ExpertDomain = .general
    private var moeSeededSystem: String?

    // MEM8 memory — wave recall engine (port of 8b-is MEM8 wave interference)
    var memoryEnabled = true
    var memory = EntheaiMemory()
    var lastRecallCount = 0

    // Voice — preview engine (on-device Apple-native speech; ROADMAP: liquid-rust/kokoro sidecars)
    let voice = VoiceEngine()

    // Process manager — entheai + ayeOS lifecycle
    let processManager = ProcessManager()
    // hf-mount (HF repo filesystem mount)
    let hfMount = HFMountClient()
    // HF Accelerate (distributed training/mixed precision via MPS)
    let accelerate = AccelerateClient()

    // Credentials (Keychain)
    var hfToken = ""
    var osaurusKey = ""
    var settingsSavedNote: String?

    // Offline / Articles
    var offlineSpaces: Set<String> = []
    var downloadingSpace: String?
    var downloadNote: String?
    var articles: [Article] = []
    var articlesLoading = false
    private let articleService = ArticleService()

    private var hub: HubClient { HubClient(token: hfToken.isEmpty ? nil : hfToken) }
    private var osaurus: OsaurusClient { OsaurusClient(apiKey: osaurusKey.isEmpty ? nil : osaurusKey) }
    private let vaked = VakedClient()
    private let projectZero = ProjectZeroClient()
    private let miroFish = MiroFishClient()

    /// Models for the active inference source — one place, so the UI never
    /// repeats the `switch` across sources.
    var activeModels: [OsaurusModel] {
        switch inferenceSource {
        case .local: osaurusModels
        case .remote: vakedModels
        case .projectZero: projectZeroModels
        }
    }

    /// The active source's status note (nil when healthy).
    var activeNote: String? {
        switch inferenceSource {
        case .local: osaurusNote
        case .remote: vakedNote
        case .projectZero: projectZeroNote
        }
    }

    /// Whether the active source answered its last probe.
    var activeReachable: Bool {
        switch inferenceSource {
        case .local: osaurusReachable
        case .remote: vakedReachable
        case .projectZero: projectZeroReachable
        }
    }

    /// Refresh the models of whichever source is active.
    func refreshActive() async {
        switch inferenceSource {
        case .local: await refreshOsaurus()
        case .remote: await refreshVaked()
        case .projectZero: await refreshProjectZero()
        }
    }

    func bootstrap() async {
        hfToken = Keychain.get("hf_token") ?? ""
        osaurusKey = Keychain.get("osaurus_key") ?? ""
        memory = EntheaiMemory.load()
        await refreshOsaurus()
        await refreshVaked()
        await refreshProjectZero()
        await refreshMiroFish()
        await loadMine()
        // A friendly default: show the featured author's Spaces if empty.
        if spaces.isEmpty {
            spaceQuery = "PeetPedro"
            await searchSpaces()
        }
        refreshOffline()
        await loadArticles()
    }

    func searchSpaces() async {
        let q = spaceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        spacesLoading = true; defer { spacesLoading = false }
        spaces = (try? await hub.searchSpaces(q)) ?? []
    }

    func searchModels() async {
        let q = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        modelsLoading = true; defer { modelsLoading = false }
        models = (try? await hub.searchModels(q)) ?? []
    }

    func loadMine() async {
        guard let name = try? await hub.whoami() else { username = nil; return }
        username = name
        mySpaces = (try? await hub.spaces(author: name)) ?? []
        myModels = (try? await hub.models(author: name)) ?? []
    }

    func refreshOsaurus() async {
        do {
            osaurusModels = try await osaurus.models()
            osaurusReachable = true; osaurusNote = nil
            if selectedModel.isEmpty { selectedModel = osaurusModels.first?.id ?? "" }
        } catch {
            osaurusModels = []; osaurusReachable = false
            osaurusNote = "Osaurus not reachable on :1337 (set an API key in Settings if it requires one)."
        }
    }

    func refreshVaked() async {
        do {
            vakedModels = try await vaked.models()
            vakedReachable = true; vakedNote = nil
            if selectedModel.isEmpty, !vakedModels.isEmpty {
                selectedModel = vakedModels.first?.id ?? ""
                // Default new users to the free remote tier
                if !osaurusReachable { inferenceSource = .remote }
            }
        } catch {
            vakedModels = []; vakedReachable = false
            vakedNote = "coder.vaked.dev unreachable — you may be offline."
        }
    }

    /// Probe the local Project Zero engine (`adaptive_ai_engine --server`,
    /// usually :8090). Absence is normal — the engine is optional — so the
    /// note is a hint, not an error.
    func refreshProjectZero() async {
        do {
            projectZeroModels = try await projectZero.models()
            projectZeroReachable = true; projectZeroNote = nil
            if selectedModel.isEmpty, let first = projectZeroModels.first?.id {
                selectedModel = first
                if !osaurusReachable && !vakedReachable { inferenceSource = .projectZero }
            }
        } catch {
            projectZeroModels = []; projectZeroReachable = false
            if ProjectZeroClient.engineBinary() == nil {
                projectZeroNote = "Project Zero engine not built — run scripts/setup-project-zero.sh, then `adaptive_ai_engine --model <gguf> --server --port 8090`."
            } else {
                projectZeroNote = "Engine built but not serving on :8090 — start it with `adaptive_ai_engine --model <gguf> --server --port 8090`."
            }
        }
    }

    /// Probe the local MiroFish backend (Flask, usually :5001). Absence is
    /// normal — MiroFish is optional — so the note points at how to start it.
    func refreshMiroFish() async {
        do {
            miroFishProjects = try await miroFish.projects()
            miroFishReachable = true; miroFishNote = nil
        } catch {
            miroFishProjects = []; miroFishReachable = false
            if (try? await miroFish.status()) != nil {
                miroFishReachable = true
                miroFishNote = "MiroFish backend reachable on :\(miroFishDefaultPort) but the project list didn't parse."
            } else {
                miroFishNote = "MiroFish not running — `cd MiroFish && npm run dev` (backend :\(miroFishDefaultPort), frontend :\(miroFishFrontendPort))."
            }
        }
    }

    func pull(_ model: String) async {
        pullingModel = model
        defer { pullingModel = nil }
        osaurusNote = (try? await osaurus.pull(model)) ?? "pull failed"
        await refreshOsaurus()
    }

    /// Authoritative embed URL — prefer an offline snapshot, else the live host.
    func resolveHost(_ space: HFSpace) async -> URL {
        if let local = OfflineStore.spaceIndex(space.id) { return local }
        return await hub.spaceHost(space.id) ?? space.embedURL
    }

    func refreshOffline() {
        offlineSpaces = Set(spaces.filter { OfflineStore.isSpaceDownloaded($0.id) }.map(\.id))
    }

    func downloadSpaceOffline(_ space: HFSpace) async {
        downloadingSpace = space.id; downloadNote = nil
        defer { downloadingSpace = nil }
        do {
            let n = try await hub.downloadSpace(space.id)
            downloadNote = "\(space.name): \(n) files cached — playable offline"
            if OfflineStore.isSpaceDownloaded(space.id) { offlineSpaces.insert(space.id) }
        } catch {
            downloadNote = "download failed: \(error.localizedDescription)"
        }
    }

    func loadArticles() async {
        articlesLoading = true; defer { articlesLoading = false }
        articles = await articleService.fetch()
    }

    func cacheArticle(_ a: Article) async { await articleService.cache(a) }

    func articleURL(_ a: Article) -> URL {
        OfflineStore.isArticleCached(a.link) ? OfflineStore.articleFile(a.link) : (URL(string: a.link) ?? OfflineStore.articleFile(a.link))
    }
    func articleIsCached(_ a: Article) -> Bool { OfflineStore.isArticleCached(a.link) }

    func send() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generating, !text.isEmpty, !selectedModel.isEmpty else { return }
        generating = true; defer { generating = false }

        let route: MoERouteResult
        let availableModels = activeModels
        if moeEnabled {
            route = MoEOptimizer.optimize(prompt: text, chatHistory: chat, availableModels: availableModels)
            activeDomain = route.domain
            if let best = route.recommendedModelID, availableModels.contains(where: { $0.id == best }) {
                selectedModel = best
            }
        } else {
            route = MoERouteResult(domain: .general, recommendedModelID: selectedModel, formattedMessages: chat)
        }

        chat.append(ChatMessage(role: "user", content: text))
        prompt = ""

        // Build the full message array without duplicating the system prompt.
        // Keep the system prompt in a separate slot so it's not rendered in chat.
        var fullMessages: [ChatMessage] = []
        if moeEnabled, route.domain.systemPrompt != moeSeededSystem {
            fullMessages.append(ChatMessage(role: "system", content: route.domain.systemPrompt))
            moeSeededSystem = route.domain.systemPrompt
        } else if let seeded = moeSeededSystem {
            fullMessages.append(ChatMessage(role: "system", content: seeded))
        }
        fullMessages.append(contentsOf: chat)

        // MEM8 memory: recall relevant past spans via wave interference.
        if memoryEnabled, let (ctx, hits) = memory.contextMessage(for: text) {
            fullMessages.append(ctx)
            lastRecallCount = hits.count
        } else {
            lastRecallCount = 0
        }
        fullMessages.append(ChatMessage(role: "user", content: text))

        // Streaming assistant bubble — fills token-by-token at the model's real speed.
        let assistant = ChatMessage(role: "assistant", content: "")
        chat.append(assistant)
        let msgId = assistant.id
        func writeBack(_ s: String) {
            if let i = chat.lastIndex(where: { $0.id == msgId }) { chat[i].content = s }
        }
        var acc = ""
        let stream: AsyncThrowingStream<String, Error>
        switch inferenceSource {
        case .local:      stream = osaurus.chatStream(model: selectedModel, messages: fullMessages)
        case .remote:     stream = vaked.chatStream(model: selectedModel, messages: fullMessages)
        case .projectZero: stream = projectZero.chatStream(model: selectedModel, messages: fullMessages)
        }
        do {
            for try await piece in stream {
                acc += piece
                writeBack(acc)
            }
            if acc.isEmpty { writeBack("(no content)") }
            voice.speak(acc)   // spoken aloud when the speaker toggle is on
            // Keep the past raw — record the exchange for future recall.
            if memoryEnabled {
                memory.record(kind: "user", text: text)
                memory.record(kind: "assistant", text: acc)
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                if acc.isEmpty { writeBack("(stopped)") }   // keep whatever streamed so far
                if memoryEnabled, !acc.isEmpty {
                    memory.record(kind: "user", text: text)
                    memory.record(kind: "assistant", text: acc)
                }
            } else {
                writeBack(acc.isEmpty ? "⚠️ \(error.localizedDescription)" : acc + "\n\n⚠️ \(error.localizedDescription)")
            }
        }
    }

    /// Fire a send as a cancellable task so a Stop button can interrupt a stream.
    func startSend() {
        genTask?.cancel()
        genTask = Task { await send() }
    }
    func stopGenerating() { genTask?.cancel() }

    func clearChat() {
        chat.removeAll()
        moeSeededSystem = nil
    }

    func clearMemory() {
        memory.clear()
        lastRecallCount = 0
    }

    func saveCredentials() {
        Keychain.set(hfToken, for: "hf_token")
        Keychain.set(osaurusKey, for: "osaurus_key")
        settingsSavedNote = "Saved to macOS Keychain ✓"
        Task {
            try? await Task.sleep(for: .seconds(3))
            settingsSavedNote = nil
        }
    }
}

// MARK: - Self-test (`HFMac --check-tools`)

/// Headless companion health check for CI and terminal use. Resolves the
/// binaries, probes the ayeOS daemon over its UNIX socket, and previews the
/// entheai argv — the three things the Ecosystem tab reports on.
enum SelfTest {
    static func run() -> Never {
        print("companions")
        for row in Toolchain.report() {
            print("  \(row.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(row.path)")
        }

        print("\nayeOS daemon")
        let daemon = AyeosClient()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let reachable = await daemon.isReachable
            print("  \(reachable ? "reachable" : "not running") @ \(daemon.socketPath)")
            done.signal()
        }
        done.wait()

        print("\nentheai argv (fanout)")
        let argv = EntheaiClient.arguments(prompt: "<prompt>", fanout: true)
        print("  \(argv.joined(separator: " "))")

        exit(0)
    }
}
