import SwiftUI

// hf.app — a native macOS Hugging Face client. Play Spaces on the desktop
// (your quantum games), read offline, and run models locally via Osaurus.
@main
struct HFMacApp: App {
    @State private var state = AppState()

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

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .local: "macbook"
        case .remote: "antenna.radiowaves.left.and.right"
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

    func bootstrap() async {
        hfToken = Keychain.get("hf_token") ?? ""
        osaurusKey = Keychain.get("osaurus_key") ?? ""
        memory = EntheaiMemory.load()
        await refreshOsaurus()
        await refreshVaked()
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
        let availableModels = inferenceSource == .local ? osaurusModels : vakedModels
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
        if inferenceSource == .local {
            stream = osaurus.chatStream(model: selectedModel, messages: fullMessages)
        } else {
            stream = vaked.chatStream(model: selectedModel, messages: fullMessages)
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
        do {
            try Keychain.set(hfToken, for: "hf_token")
            try Keychain.set(osaurusKey, for: "osaurus_key")
        } catch {
            settingsSavedNote = "Could not save all credentials. " + error.localizedDescription
            return
        }
        settingsSavedNote = "Saved to macOS Keychain ✓"
        Task {
            try? await Task.sleep(for: .seconds(3))
            if settingsSavedNote == "Saved to macOS Keychain ✓" {
                settingsSavedNote = nil
            }
        }
    }
}
