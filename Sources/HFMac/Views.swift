import SwiftUI
import AppKit

enum Tab: String, CaseIterable, Identifiable {
    case spaces = "Spaces"
    case articles = "Articles"
    case models = "Models"
    case run = "Run"
    case yours = "Yours"
    case ecosystem = "Ecosystem"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .spaces: "gamecontroller"
        case .articles: "book"
        case .models: "cube.box"
        case .run: "bubble.left.and.text.bubble.right"
        case .yours: "person.crop.circle"
        case .ecosystem: "circle.hexagongrid"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var tab: Tab = .spaces

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { t in
                Label(t.rawValue, systemImage: t.icon)
                    .tag(t)
                    .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .navigationTitle("HF-MAC")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .background(Theme.glassMaterial)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(state.osaurusReachable || state.vakedReachable ? Theme.green : Theme.warn).frame(width: 7, height: 7)
                        Text(state.username.map { "@\($0)" } ?? "not signed in")
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.dim)
                        Spacer()
                    }
                    Text("{-1, 0, +1}")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.dim.opacity(0.7))
                }
                .padding(12)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.glassBorder))
                .padding(10)
            }
        } detail: {
            Group {
                switch tab {
                case .spaces: SpacesView()
                case .articles: ArticlesView()
                case .models: ModelsView()
                case .run: RunView()
                case .yours: YoursView()
                case .ecosystem: EcosystemView()
                }
            }
            .toolbarBackground(Theme.glassBarMaterial, for: .windowToolbar)
        }
        // ⌘1–⌘5 tab navigation (native macOS convention)
        .background {
            ForEach(Array(Tab.allCases.enumerated()), id: \.offset) { i, t in
                Button("") { tab = t }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Spaces (the focus — playable on desktop)

struct SpacesView: View {
    @Environment(AppState.self) private var state
    private let cols = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        @Bindable var s = state
        NavigationStack {
            ScrollView {
                if state.spacesLoading {
                    ProgressView("Searching Hugging Face Spaces…")
                        .padding(40)
                }
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(state.spaces) { space in
                        NavigationLink(value: space) { SpaceCard(space: space) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationDestination(for: HFSpace.self) { SpacePlayerView(space: $0) }
            .navigationTitle("Spaces")
            .searchable(text: $s.spaceQuery, prompt: "Search Spaces (try: quantum, PeetPedro, gradio)")
            .onSubmit(of: .search) { Task { await state.searchSpaces() } }
            .overlay {
                if state.spaces.isEmpty && !state.spacesLoading {
                    ContentUnavailableView {
                        Label("Play a Space", systemImage: "gamecontroller")
                    } description: {
                        Text("Search Hugging Face Hub — Gradio demos, static apps, and quantum games run directly on macOS glass desktop.")
                    } actions: {
                        Button("Explore Featured") {
                            state.spaceQuery = "PeetPedro"
                            Task { await state.searchSpaces() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct SpaceCard: View {
    let space: HFSpace
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(space.emoji ?? "🚀").font(.system(size: 32))
                Spacer()
                if OfflineStore.isSpaceDownloaded(space.id) {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                        .help("Downloaded for offline play")
                }
            }
            Text(space.name)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
            Text(space.owner)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if let sdk = space.sdk { Label(sdk, systemImage: "square.stack.3d.up") }
                if let l = space.likes { Label(l.formatted(), systemImage: "heart") }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .padding(16)
        .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.glassBorder))
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct SpacePlayerView: View {
    @Environment(AppState.self) private var state
    let space: HFSpace
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                SpaceWebView(url: url).ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Loading \(space.name)…")
            }
        }
        .navigationTitle(space.name)
        .toolbar {
            ToolbarItem {
                if state.downloadingSpace == space.id {
                    ProgressView().controlSize(.small)
                } else if OfflineStore.isSpaceDownloaded(space.id) {
                    Image(systemName: "checkmark.icloud").foregroundStyle(Theme.green).help("Available offline")
                } else {
                    Button {
                        Task {
                            await state.downloadSpaceOffline(space)
                            state.refreshOffline()
                            url = await state.resolveHost(space)
                        }
                    } label: { Image(systemName: "arrow.down.circle") }
                    .help("Download for offline play")
                }
            }
            ToolbarItem {
                Link(destination: URL(string: "https://huggingface.co/spaces/\(space.id)")!) {
                    Image(systemName: "safari")
                }.help("Open on huggingface.co")
            }
        }
        .task(id: space.id) { url = await state.resolveHost(space) }
    }
}

// MARK: - Articles (offline-first reader)

struct ArticlesView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        NavigationStack {
            List(state.articles) { a in
                NavigationLink(value: a) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.title).font(.headline)
                            if state.articleIsCached(a) {
                                Image(systemName: "checkmark.icloud").font(.caption).foregroundStyle(Theme.green)
                            }
                        }
                        if !a.summary.isEmpty { Text(a.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Text(a.source).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 4)
                }
                .swipeActions { Button("Save") { Task { await state.cacheArticle(a) } } }
            }
            .listStyle(.inset)
            .navigationDestination(for: Article.self) { ArticleReaderView(article: $0) }
            .navigationTitle("Articles")
            .overlay {
                if state.articles.isEmpty {
                    if state.articlesLoading { ProgressView() }
                    else { ContentUnavailableView("Offline-first reading", systemImage: "book",
                        description: Text("Your pocoo essays — read on the plane. Open one and it's cached for offline.")) }
                }
            }
            .task { if state.articles.isEmpty { await state.loadArticles() } }
        }
    }
}

struct ArticleReaderView: View {
    @Environment(AppState.self) private var state
    let article: Article
    var body: some View {
        SpaceWebView(url: state.articleURL(article))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(article.title)
            .toolbar {
                ToolbarItem {
                    Button { Task { await state.cacheArticle(article) } } label: {
                        Image(systemName: state.articleIsCached(article) ? "checkmark.icloud" : "arrow.down.circle")
                    }.help("Save for offline")
                }
            }
            .task { if !state.articleIsCached(article) { await state.cacheArticle(article) } }
    }
}

// MARK: - Models

struct ModelsView: View {
    @Environment(AppState.self) private var state
    @ViewBuilder private func fastChip(_ label: String, _ query: String) -> some View {
        Button(label) { state.modelQuery = query; Task { await state.searchModels() } }
            .buttonStyle(.bordered).controlSize(.small).tint(Theme.green)
    }

    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("⚡ Faster = fewer bits").font(.caption).foregroundStyle(Theme.dim)
                    fastChip("MLX 4-bit", "mlx 4bit")
                    fastChip("MLX", "mlx")
                    fastChip("🜂 Ternary · BitNet", "bitnet")
                    fastChip("GGUF", "gguf")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(Theme.glassBarMaterial)
            Divider()
            List(state.models) { m in
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.id).font(.system(.headline, design: .monospaced))
                    HStack(spacing: 14) {
                        let sp = ModelSpeed.of(m.id, library: m.library_name)
                        if !sp.label.isEmpty {
                            Text(sp.label).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background((sp.isFast ? Theme.green : Theme.dim).opacity(0.16), in: Capsule())
                                .foregroundStyle(sp.isFast ? Theme.green : Theme.dim)
                        }
                        if let t = m.pipeline_tag { Label(t, systemImage: "tag") }
                        if let d = m.downloads { Label(d.formatted(), systemImage: "arrow.down.circle") }
                        if let l = m.likes { Label(l.formatted(), systemImage: "heart") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.pullingModel == m.id {
                    ProgressView("Pulling…").controlSize(.small)
                } else {
                    Button("Pull") { Task { await state.pull(m.id) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 6)
            .contextMenu {
                Button("Copy Model ID") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(m.id, forType: .string)
                }
                Button("Pull into Osaurus") { Task { await state.pull(m.id) } }
                Divider()
                Link("Open on huggingface.co", destination: URL(string: "https://huggingface.co/\(m.id)")!)
            }
        }
        .listStyle(.inset)
        .searchable(text: $s.modelQuery, prompt: "Search models (e.g., Llama, Qwen, Mistral)")
        .onSubmit(of: .search) { Task { await state.searchModels() } }
        .overlay { if state.models.isEmpty { ContentUnavailableView("Find a model", systemImage: "cube.box", description: Text("Search open-weight models, then pull into Osaurus. Prefer MLX 4-bit — it runs 2–4× faster on Apple Silicon.")) } }
        }
    }
}

// MARK: - Chat Bubble Component

/// Renders text with fenced code blocks + inline markdown. Streaming-safe: an
/// unclosed ``` fence renders its tail as a (still-growing) code block.
struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.segments(text).enumerated()), id: \.offset) { _, seg in
                if seg.code {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(seg.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.glassBorder))
                } else if !seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(Self.inline(seg.text)).textSelection(.enabled)
                }
            }
        }
    }
    static func segments(_ s: String) -> [(text: String, code: Bool)] {
        s.components(separatedBy: "```").enumerated().map { i, part in
            if i % 2 == 1 {   // between fences → code; drop an optional language line
                var p = part
                if let nl = p.firstIndex(of: "\n") { p = String(p[p.index(after: nl)...]) }
                return (p, true)
            }
            return (part, false)
        }
    }
    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let isUser = message.role == "user"
        let bg = isUser ? Theme.accent.opacity(0.18) : Color.gray.opacity(0.15)
        let border = isUser ? Theme.glassBorderHighlight : Theme.glassBorder

        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 60) }
            MarkdownText(text: message.content)
                .padding(12)
                .background(bg, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border))
                .overlay(alignment: .topTrailing) {
                    if hovering, !message.content.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption2).padding(6)
                                .background(Theme.glassMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.glassBorder))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(copied ? Theme.green : Theme.dim)
                        .offset(x: 9, y: -9)
                        .help("Copy")
                    }
                }
            if !isUser { Spacer(minLength: 60) }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Run (Osaurus local chat)

struct RunView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var s = state
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Inference source selector — local Osaurus or remote coder.vaked.dev
                Picker("", selection: $s.inferenceSource) {
                    ForEach(InferenceSource.allCases) { src in
                        Label(src.rawValue, systemImage: src.icon).tag(src)
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200)

                let models = state.activeModels
                Picker("", selection: $s.selectedModel) {
                    ForEach(models) { Text($0.id).tag($0.id) }
                }
                    .labelsHidden().frame(maxWidth: 280)
                let sp = ModelSpeed.of(state.selectedModel)
                if !state.selectedModel.isEmpty, !sp.label.isEmpty {
                    Text(sp.label).font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(sp.isFast ? Theme.green : Theme.dim)
                }
                Button { Task { await state.refreshActive() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh models (⌘R)")
                    .keyboardShortcut("r", modifiers: [.command])
                
                if !state.chat.isEmpty {
                    Button { state.clearChat() } label: { Image(systemName: "trash") }
                        .help("Clear conversation (⌘K)")
                        .keyboardShortcut("k", modifiers: [.command])
                }

                Spacer()

                // MoE Optimizer Badge
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(state.moeEnabled ? Theme.accent : Theme.dim)
                    Toggle("MoE Router", isOn: $s.moeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.glassMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(state.moeEnabled ? Theme.glassBorderHighlight : Theme.glassBorder))

                // MEM8 memory (wave recall)
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundStyle(state.memoryEnabled ? Theme.green : Theme.dim)
                    Toggle("Memory", isOn: $s.memoryEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.glassMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(state.memoryEnabled ? Theme.green.opacity(0.4) : Theme.glassBorder))
                .help("MEM8 memory · wave recall (\(state.memory.count) spans stored)")

                if state.memoryEnabled, state.lastRecallCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle.magnifyingglass").font(.caption2)
                        Text("↺\(state.lastRecallCount)")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(Theme.green)
                    .background(Theme.green.opacity(0.12), in: Capsule())
                    .help("\(state.lastRecallCount) memories recalled into the last prompt")
                }

                if state.moeEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: state.activeDomain.icon)
                            .font(.caption2)
                        Text(state.activeDomain.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                }

                if !state.activeReachable {
                    Button("Retry Connection") { Task { await state.refreshActive() } }
                        .buttonStyle(.bordered)
                        .tint(Theme.warn)
                        .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(state.inferenceSource == .remote ? Theme.accent : Theme.green)
                            .frame(width: 7, height: 7)
                        Text(state.inferenceSource.statusLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.glassMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.glassBorder))
                }
            }
            .padding(14)
            .background(Theme.glassBarMaterial)

            if let n = state.activeNote {
                HStack {
                    Text(n).font(.caption).foregroundStyle(Theme.warn)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Theme.glassBarMaterial)
            }
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(state.chat) { m in
                            ChatBubbleView(message: m)
                                .id(m.id)
                        }
                        // "thinking" only until the first streamed token lands
                        if state.generating, (state.chat.last?.content.isEmpty ?? true) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("thinking (\(state.activeDomain.rawValue))…").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Theme.glassMaterial, in: Capsule())
                            .id("thinking_indicator")
                        }
                    }
                    .padding(16)
                }
                .overlay {
                    if state.chat.isEmpty, !state.generating {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 40)).foregroundStyle(Theme.dim.opacity(0.7))
                            Text("Chat, locally").font(.title3.weight(.semibold)).foregroundStyle(Theme.fg)
                            if state.selectedModel.isEmpty {
                            Text(state.inferenceSource.emptyHint)
                                .font(.callout).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                        } else {
                                let sp = ModelSpeed.of(state.selectedModel)
                                Text(state.selectedModel + (sp.label.isEmpty ? "" : " · \(sp.label)"))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(sp.isFast ? Theme.green : Theme.dim)
                                Text("Ask anything — replies stream in at the model's real speed.")
                                    .font(.callout).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: 360).padding()
                    }
                }
                .onChange(of: state.chat.count) { _, _ in
                    if let lastId = state.chat.last?.id {
                        withAnimation(.easeInOut) { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onChange(of: state.chat.last?.content) { _, _ in   // follow the streaming reply
                    if let lastId = state.chat.last?.id { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
            Divider()

            if let vn = state.voice.note {
                HStack { Text(vn).font(.caption).foregroundStyle(Theme.warn); Spacer() }
                    .padding(.horizontal, 16).padding(.bottom, 4).background(Theme.glassBarMaterial)
            }
            HStack(alignment: .bottom, spacing: 10) {
                // Voice · preview — dictate a prompt on-device
                Button { state.voice.toggleDictation() } label: {
                    Image(systemName: state.voice.isDictating ? "mic.fill" : "mic")
                        .foregroundStyle(state.voice.isDictating ? Theme.warn : Theme.dim)
                }
                .buttonStyle(.bordered)
                .help(state.voice.isDictating ? "Stop dictation" : "Dictate a prompt (on-device)")

                TextField("Message the model…", text: $s.prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .onSubmit { state.startSend() }

                // Voice · preview — speak replies aloud
                Button {
                    state.voice.speakReplies.toggle()
                    if !state.voice.speakReplies { state.voice.stopSpeaking() }
                } label: {
                    Image(systemName: state.voice.speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
                        .foregroundStyle(state.voice.speakReplies ? Theme.green : Theme.dim)
                }
                .buttonStyle(.bordered)
                .help(state.voice.speakReplies ? "Speaking replies aloud — click to mute" : "Speak replies aloud")

                if state.generating {
                    Button(role: .cancel) { state.stopGenerating() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.warn)
                    .keyboardShortcut(".", modifiers: [.command])
                } else {
                    Button { state.startSend() } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(state.selectedModel.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(14)
            .background(Theme.glassBarMaterial)
            .onChange(of: state.voice.transcript) { _, t in
                if !t.isEmpty { s.prompt = t }
            }
        }
    }
}

// MARK: - Yours (creator)

struct YoursView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        if state.username == nil {
            ContentUnavailableView {
                Label("Sign in", systemImage: "person.crop.circle")
            } description: {
                Text("Add a Hugging Face token in Settings (⌘,) to see your Spaces and models here.")
            }
        } else {
            List {
                Section("Your Spaces (\(state.mySpaces.count))") {
                    ForEach(state.mySpaces) { sp in
                        NavigationLink { SpacePlayerView(space: sp) } label: {
                            Label("\(sp.emoji ?? "🚀")  \(sp.name)", systemImage: "")
                        }
                    }
                }
                Section("Your models (\(state.myModels.count))") {
                    ForEach(state.myModels) { m in
                        HStack { Text(m.id); Spacer(); if let d = m.downloads { Text(d.formatted()).foregroundStyle(.secondary) } }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var s = state
        Form {
            Section("Hugging Face") {
                SecureField("Token (hf_…)", text: $s.hfToken)
                Text("Read access. Stored in your macOS Keychain. Used for your Spaces/models and private content.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Osaurus (local inference)") {
                SecureField("API key (if Osaurus requires one)", text: $s.osaurusKey)
                Text("Only needed if Osaurus has auth enabled. Talks to localhost:1337.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("coder.vaked.dev (remote free tier)") {
                Text("No key needed — free community inference at coder.vaked.dev. Serves Qwen3-Coder-30B on CPU.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Circle().fill(state.vakedReachable ? Theme.green : Theme.warn).frame(width: 6, height: 6)
                    Text(state.vakedReachable ? "reachable" : "offline").font(.caption)
                }
            }
            Section("Mixture of Experts (MoE)") {
                Toggle("Enable MoE Intent Classifier & Auto-Router", isOn: $s.moeEnabled)
                Text("Automatically detects code, math, summary, or creative prompts and routes to specialized local models.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("MEM8 memory · wave recall") {
                Toggle("Recall relevant past exchanges (on-device)", isOn: $s.memoryEnabled)
                Text("A Swift port of MEM8 — wave interference recall. \(state.memory.count) spans stored; never leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear memory (\(state.memory.count) spans)") { state.clearMemory() }
                    .disabled(state.memory.count == 0)
            }
            if let note = state.settingsSavedNote {
                Text(note).font(.caption).foregroundStyle(Theme.green)
            }
            Button("Save Credentials") {
                state.saveCredentials()
                Task { await state.loadMine(); await state.refreshOsaurus() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(24).frame(width: 480)
    }
}

// MARK: - Ecosystem (entheai + ayeOS)

struct EcosystemView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let pm = state.processManager
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("HF-MAC {-1, 0, +1}").font(.title2.weight(.semibold))
                    Text("hf-mac as the unified surface — ternary, quantal, aligned")
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }

                // entheai agent
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(pm.entheaiAvailable ? Theme.green : Theme.dim)
                        Text("entheai agent").font(.headline)
                        Spacer()
                        StatusBadge(available: pm.entheaiAvailable)
                    }
                    Text(pm.entheaiAvailable
                         ? "Binary available at \(pm.entheaiPath ?? "entheai"). Fan-out decomposition ready."
                         : "Install entheai to enable agent decomposition (cargo install --path bin/entheai).")
                        .font(.caption).foregroundStyle(.secondary)

                    if pm.entheaiAvailable {
                        HStack(spacing: 12) {
                            Button("Run Agent") {
                                Task {
                                    let prompt = "analyze the current project structure"
                                    if let result = await pm.runEntheai(prompt: prompt) {
                                        pm.note = result.prefix(200) + "..."
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                            Button("Fan-out") {
                                Task {
                                    let prompt = "review and improve code quality"
                                    if let result = await pm.fanout(prompt: prompt) {
                                        pm.note = result.prefix(200) + "..."
                                    }
                                }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // ayeOS ternary daemon
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "triangle")
                            .foregroundStyle(pm.ayeosReachable ? Theme.green : .orange)
                        Text("ayeOS ternary daemon").font(.headline)
                        Spacer()
                        StatusBadge(available: pm.ayeosAvailable, online: pm.ayeosReachable)
                    }
                    Text(pm.ayeosReachable
                         ? "MEMNET reachable on the local socket (/tmp/ayeosd.sock). LINOSV-seeded ternary matrices ready."
                         : pm.ayeosAvailable
                         ? "Binary available at \(pm.ayeosPath ?? "ayeosd") but daemon not running. Start with `ayeosd`."
                         : "Install ayeOS (cargo install --path ../ayeos) for ternary inference.")
                        .font(.caption).foregroundStyle(.secondary)

                    if pm.ayeosReachable {
                        Button("Fetch Capsule") {
                            Task {
                                if let capsule = await pm.ayeosCapsule() {
                                    pm.note = "ayeOS: \(capsule.capsule_id) · \(capsule.payload_type) · score \(capsule.relevance_score)"
                                }
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        // Show loaded capsules
                        CapsuleListView()
                            .environment(state)
                    } else if pm.ayeosAvailable {
                        Button("Launch ayeOS") {
                            Task {
                                let process = Process()
                                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ayeosd")
                                try? process.run()
                                try? await Task.sleep(for: .seconds(1))
                                await pm.checkAyeosReachability()
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                    }

                    if let note = pm.note {
                        Text(note).font(.caption2).foregroundStyle(Theme.warn)
                    }
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // hf-mount (HF repos as local filesystem)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .foregroundStyle(state.hfMount.isAvailable ? Theme.green : Theme.dim)
                        Text("hf-mount").font(.headline)
                        Spacer()
                        StatusBadge(available: state.hfMount.isAvailable, online: nil)
                    }
                    Text(state.hfMount.isAvailable
                         ? "Mount HF repos as local filesystems — zero download, lazy reads."
                         : "Install hf-mount (brew install hf-mount) to mount repos as local filesystems.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // HF Accelerate (MPS-accelerated training)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "bolt.shield")
                            .foregroundStyle(state.accelerate.isAvailable ? Theme.green : Theme.dim)
                        Text("HF Accelerate").font(.headline)
                        Spacer()
                        StatusBadge(available: state.accelerate.isAvailable, online: nil)
                    }
                    Text(state.accelerate.isAvailable
                         ? "MPS-accelerated training on Apple Silicon. Mixed precision, device placement, FSDP."
                         : "Install: pip install accelerate")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // MiroFish (swarm-intelligence prediction engine, over HTTP)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundStyle(state.miroFishReachable ? Theme.green : Theme.dim)
                        Text("MiroFish").font(.headline)
                        Spacer()
                        StatusBadge(available: state.miroFishReachable, online: state.miroFishReachable)
                    }
                    Text(state.miroFishReachable
                         ? "Swarm-intelligence prediction engine on :\(miroFishDefaultPort) — \(state.miroFishProjects.count) project\(state.miroFishProjects.count == 1 ? "" : "s"). Separate process (AGPL), spoken to over HTTP."
                         : "Run `cd MiroFish && npm run dev` — a swarm-intelligence prediction engine (multi-agent simulation + knowledge graphs). hf.app talks to its backend on :\(miroFishDefaultPort) over HTTP.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Refresh") { Task { await state.refreshMiroFish() } }
                            .buttonStyle(.bordered).controlSize(.small)
                        if state.miroFishReachable {
                            Button("Open MiroFish") {
                                if let url = URL(string: "http://127.0.0.1:\(miroFishFrontendPort)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                        }
                    }
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // MOE-ptimizer (transparent OpenAI proxy — context optimization)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(state.moeptimizerReachable ? Theme.green : Theme.dim)
                        Text("MOE-ptimizer").font(.headline)
                        Spacer()
                        StatusBadge(available: state.moeptimizerReachable, online: state.moeptimizerReachable)
                    }
                    Text(state.moeptimizerReachable
                         ? "OpenAI-compatible context-optimizing proxy — \(state.moeptimizerModels.count) model\(state.moeptimizerModels.count == 1 ? "" : "s"). Byte-stable prefixes keep the backend's prefix cache warm."
                         : "Run the proxy (`moeptimizer`, OpenAI-compatible on :8080 → your backend) for token savings in multi-turn agentic tasks. Select it as the Run source once up.")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Refresh") { Task { await state.refreshMoeptimizer() } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))

                // Integration map
                VStack(alignment: .leading, spacing: 8) {
                    Text("integration map").font(.headline)
                    IntegrationRow(icon: "bubble.left.and.text.bubble.right", name: "Osaurus", desc: "Local inference engine", status: state.osaurusReachable)
                    IntegrationRow(icon: "brain.head.profile", name: "entheai MEM8", desc: "Wave interference recall", status: pm.entheaiAvailable)
                    IntegrationRow(icon: "triangle", name: "ayeOS", desc: "Ternary matmul (12.80×)", status: pm.ayeosReachable)
                    IntegrationRow(icon: "brain", name: "MiroFish", desc: "Swarm prediction (HTTP)", status: state.miroFishReachable)
                    IntegrationRow(icon: "arrow.triangle.branch", name: "MOE-ptimizer", desc: "Context-optimizing proxy", status: state.moeptimizerReachable)
                    IntegrationRow(icon: "antenna.radiowaves.left.and.right", name: "FLUG-OS", desc: "802.11 packet-wave sampler", status: false)
                    IntegrationRow(icon: "cube.box", name: "MLX-QUANT", desc: "Metal GPU ternary kernels", status: true)
                    IntegrationRow(icon: "antenna.radiowaves.left.and.right", name: "coder.vaked.dev", desc: "Free remote inference", status: state.vakedReachable)
                    IntegrationRow(icon: "waveform.path", name: "MEM8 memory", desc: "\(state.memory.count) spans stored", status: state.memoryEnabled)
                    IntegrationRow(icon: "externaldrive.connected.to.line.below", name: "hf-mount", desc: "HF repos as local FS", status: state.hfMount.isAvailable)
                    IntegrationRow(icon: "bolt.shield", name: "HF Accelerate", desc: "MPS training/inference", status: state.accelerate.isAvailable)
                }
                .padding(16)
                .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.glassBorder))
            }
            .padding(20)
        }
        .task {
            await pm.checkAyeosReachability()
        }
    }
}

/// Lists loaded ayeOS capsules fetched from the MEMNET daemon.
struct CapsuleListView: View {
    @Environment(AppState.self) private var state
    @State private var capsules: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("loaded capsules").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    Task {
                        capsules = await state.processManager.ayeosCapsules()
                    }
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
            }
            if capsules.isEmpty {
                Text("no trained capsules loaded").font(.caption).foregroundStyle(Theme.dim)
            } else {
                ForEach(capsules, id: \.self) { name in
                    HStack {
                        Image(systemName: "triangle").font(.caption).foregroundStyle(Theme.green)
                        Text(name).font(.system(.caption, design: .monospaced))
                        Spacer()
                    }
                    .padding(6)
                    .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .task { capsules = await state.processManager.ayeosCapsules() }
    }
}

struct StatusBadge: View {
    let available: Bool
    var online: Bool?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(online ?? available ? Theme.green : .orange).frame(width: 6, height: 6)
            Text(online == true ? "online"
                 : available ? "installed"
                 : "missing")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(online ?? available ? Theme.green : .orange)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((online ?? available ? Theme.green : .orange).opacity(0.12), in: Capsule())
    }
}

struct IntegrationRow: View {
    let icon: String
    let name: String
    let desc: String
    let status: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(status ? Theme.green : Theme.dim)
                .frame(width: 20)
            Text(name).font(.system(.subheadline, design: .monospaced))
            Spacer()
            Text(desc).font(.caption).foregroundStyle(Theme.dim)
            Circle().fill(status ? Theme.green : Theme.warn).frame(width: 5, height: 5)
        }
    }
}

// MARK: - Menu-bar agent

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var s = state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HF-MAC {-1, 0, +1}").font(.headline)
                Spacer()
                Picker("", selection: $s.selectedModel) { ForEach(state.osaurusModels) { Text($0.id).tag($0.id) } }
                    .labelsHidden().frame(maxWidth: 150)
                if !state.chat.isEmpty {
                    Button { state.clearChat() } label: { Image(systemName: "trash").font(.caption) }
                        .buttonStyle(.plain)
                        .help("Clear chat")
                }
            }
            TextField("Quick prompt…", text: $s.prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { Task { await state.send() } }
            if let last = state.chat.last(where: { $0.role == "assistant" }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(last.content, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                    ScrollView {
                        Text(last.content)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Theme.glassMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxHeight: 170)
                }
            }
            HStack {
                Button("Send") { Task { await state.send() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(state.generating || state.selectedModel.isEmpty)
                Spacer()
                if state.generating { ProgressView().controlSize(.small) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Theme.glassMaterial)
    }
}
