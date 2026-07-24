import FastWordsCore
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarPopoverView: View {
    @ObservedObject var store: WordStore
    let actions: AppActions
    @State private var revealedDefinitionWordID: UUID?
    /// Bottom search bar: icon expands into a text field; Enter submits.
    @State private var isSearchExpanded = false
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isDropTargeted = false
    /// Confirmation before removing a single word from the current book.
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            // Native menu-bar translucency (frosted glass), not a flat color.
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                Divider().overlay(Theme.accent(for: store.settings.accentColor).opacity(0.18))

                if let preview = store.importPreview {
                    importPreviewPanel(preview)
                } else if let miss = store.searchMiss {
                    searchMissPanel(miss)
                } else if let pending = store.pendingSearch {
                    pendingSearchPanel(pending)
                } else if let word = store.currentWord {
                    // Fixed title area (headword + phonetics) — independent of the
                    // scrolling content, so its position never changes per word.
                    titleArea(word)
                        .id("title-\(word.id)")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 8)), removal: .opacity.combined(with: .offset(x: -8))))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    if store.isShowingTemporaryPreview {
                        temporaryBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)
                    }

                    // The content area always fills the remaining height, so the
                    // controls stay pinned to the bottom no matter how much
                    // content a word has. Long content scrolls inside this region.
                    ScrollView {
                        wordDetail(word)
                            .id("detail-\(word.id)")
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 8)), removal: .opacity.combined(with: .offset(x: -8))))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Divider().overlay(Theme.accent(for: store.settings.accentColor).opacity(0.10))

                    controls(for: word)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                } else {
                    emptyState
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.currentWord?.id)

            // Invisible buttons that own the keyboard shortcuts.
            // Disable while the search field is open so Space/arrows type normally.
            if !isSearchExpanded {
                keyboardShortcuts
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent(for: store.settings.accentColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Theme.accent(for: store.settings.accentColor).opacity(0.08))
                    .padding(8)
                    .allowsHitTesting(false)
                    .overlay {
                        Text("松开以导入词书")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent(for: store.settings.accentColor))
                    }
            }
        }
        .frame(width: 360, height: 540)
        .tint(Theme.accent(for: store.settings.accentColor))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(deleteConfirmDestructiveLabel, role: .destructive) {
                actions.deleteCurrentWord()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteConfirmMessage)
        }
        .onChange(of: store.currentWord?.id) { _, _ in
            revealedDefinitionWordID = nil
        }
        // Auto-reveal the meaning if the user lingers on a word for 10s. The
        // task is keyed to the word id, so switching words cancels and restarts
        // the countdown; a manual reveal earlier just makes this set a no-op.
        .task(id: store.currentWord?.id) {
            guard let id = store.currentWord?.id else { return }
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return  // cancelled — word changed or popover closed
            }
            withAnimation(.easeOut(duration: 0.3)) {
                revealedDefinitionWordID = id
            }
        }
    }

    private var temporaryBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
            Text("仅本次查看 · 不会写入词书")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("加入词书") {
                if let word = store.temporaryPreview {
                    store.presentLookupWord(
                        word.word,
                        result: DictionaryResult(
                            phonetic: word.phonetic,
                            meaning: word.meaning,
                            englishDefinition: word.englishDefinition,
                            example: word.example
                        ),
                        sourceNote: "已加入当前词书"
                    )
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent(for: store.settings.accentColor))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.accent(for: store.settings.accentColor).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var deleteConfirmTitle: String {
        if store.isShowingTemporaryPreview {
            return "关闭预览？"
        }
        let name = store.currentWord?.word ?? "该词"
        return "删除「\(name)」？"
    }

    private var deleteConfirmDestructiveLabel: String {
        store.isShowingTemporaryPreview ? "关闭预览" : "从当前词书删除"
    }

    private var deleteConfirmMessage: String {
        if store.isShowingTemporaryPreview {
            return "仅关闭本次查看，不会改动词书。"
        }
        return "只从当前词书移除这一个单词，不会删除整本词书。若其它词书也有该词，学习进度会保留。"
    }

    private func pendingSearchPanel(_ pending: WordStore.PendingSearch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pending.sourceLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)

            Text(pending.entry.word)
                .font(.maple(32, bold: true))
                .foregroundStyle(Theme.ink)

            if !pending.entry.meaning.isEmpty {
                Text(pending.entry.meaning)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !pending.entry.englishDefinition.isEmpty {
                Text(pending.entry.englishDefinition)
                    .font(.maple(13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !pending.entry.example.isEmpty {
                Text(pending.entry.example)
                    .font(.system(size: 13, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("仅本次查看", action: actions.confirmSearchPeek)
                    .buttonStyle(.bordered)
                Button("加入词书", action: actions.confirmSearchAdd)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill(for: store.settings.accentColor))
                Spacer()
                Button("取消", action: actions.dismissSearchPending)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Spelling suggestions or terminal search failure — actionable, never a dead end.
    private func searchMissPanel(_ miss: WordStore.SearchMiss) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(searchMissTitle(miss.reason))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)

            Text(miss.query)
                .font(.maple(28, bold: true))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text(searchMissBody(miss))
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !miss.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(miss.reason == .spellingSuggestions ? "你是不是要找：" : "相近单词：")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    ForEach(miss.suggestions, id: \.self) { suggestion in
                        Button {
                            actions.searchWord(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(Theme.accent(for: store.settings.accentColor))
                                Text(suggestion)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)

            // Primary actions depend on reason.
            VStack(spacing: 8) {
                if miss.canContinueWithAI {
                    Button {
                        actions.continueSearchWithAI(miss.query)
                    } label: {
                        Text(store.settings.aiEnabled ? "仍用 AI 查询「\(miss.query)」" : "跳过建议，继续查询")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill(for: store.settings.accentColor))
                }

                if miss.reason == .aiDisabled || miss.reason == .aiNotConfigured {
                    Button {
                        actions.openSettings()
                    } label: {
                        Text(miss.reason == .aiDisabled ? "打开设置并启用 AI" : "打开设置配置 AI")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill(for: store.settings.accentColor))
                }

                if case .lookupFailed = miss.reason {
                    Button {
                        actions.continueSearchWithAI(miss.query)
                    } label: {
                        Text("重试")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill(for: store.settings.accentColor))
                }

                HStack(spacing: 8) {
                    Button("空白加入…") {
                        actions.addBlankWord(miss.query)
                    }
                    .buttonStyle(.bordered)
                    .help("生成无释义卡片，仍需确认后才会写入词书")

                    Button("系统词典") {
                        actions.openSystemDictionaryFor(miss.query)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("关闭", action: actions.dismissSearchMiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func searchMissTitle(_ reason: WordStore.SearchMissReason) -> String {
        switch reason {
        case .spellingSuggestions: "未找到精确匹配"
        case .notAValidWord: "无法识别"
        case .aiDisabled: "词典未收录"
        case .aiNotConfigured: "词典未收录"
        case .lookupFailed: "查询失败"
        }
    }

    private func searchMissBody(_ miss: WordStore.SearchMiss) -> String {
        switch miss.reason {
        case .spellingSuggestions:
            return "内置词典没有「\(miss.query)」。下面是相近拼写，点选即可搜索；也可以继续用 AI 查原词，或加入空白卡片。"
        case .notAValidWord:
            return "「\(miss.query)」不像有效的英语单词。请检查拼写，或从下方相近词中选择；仍可空白加入词书。"
        case .aiDisabled:
            return "内置词典没有该词。启用 AI 后可查询生词；也可以先空白加入或打开系统词典。"
        case .aiNotConfigured:
            return "内置词典没有该词。请在设置中填写 AI 接口地址、Key 与模型；也可以空白加入或打开系统词典。"
        case .lookupFailed(let detail):
            let short = detail.count > 80 ? String(detail.prefix(80)) + "…" : detail
            return "词典未收录，在线查询也失败了。\(short.isEmpty ? "" : "（\(short)）")可重试，或空白加入 / 打开系统词典。"
        }
    }

    private func importPreviewPanel(_ preview: WordStore.ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入预览")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("文件：\(preview.sourceName)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)

            VStack(alignment: .leading, spacing: 8) {
                Label("将新增 \(preview.added) 个单词", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.accent(for: store.settings.accentColor))
                Label("跳过 \(preview.skipped) 个重复（保留进度）", systemImage: "arrow.triangle.merge")
                    .foregroundStyle(Theme.inkSoft)
            }
            .font(.system(size: 14, weight: .medium))

            if preview.added == 0 {
                Text("没有新词可导入。")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("取消", action: actions.cancelImport)
                    .buttonStyle(.bordered)
                Button("确认导入") { actions.confirmImport() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentFill(for: store.settings.accentColor))
                    .disabled(preview.added == 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let str = item as? String {
                url = URL(fileURLWithPath: str)
            } else if let u = item as? URL {
                url = u
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                actions.importDroppedFile(url)
            }
        }
        return true
    }

    // MARK: - Header

    private var header: some View {
        // Settings lives only in the bottom toolbar (gear) — the old top-right
        // ellipsis opened the same window and crowded the progress text.
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(Theme.accent(for: store.settings.accentColor))

            bookSwitcher

            Spacer()

            Text(store.progressText)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    /// Dropdown that shows the current book name and switches between books,
    /// each keeping its own progress.
    private var bookSwitcher: some View {
        Menu {
            ForEach(store.books) { book in
                Button {
                    store.selectBook(book.id)
                } label: {
                    if book.id == store.currentBookID {
                        Label(book.name, systemImage: "checkmark")
                    } else {
                        Text(book.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(store.currentBook?.name ?? "FastWords")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Title area (fixed)

    /// Headword + phonetics in a fixed-height region. A small leading inset
    /// absorbs any negative glyph side-bearing so the first letter never clips,
    /// and the row clips to its bounds so a long word can't bleed past the edge.
    private func titleArea(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.word)
                .font(.maple(38, bold: true))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 48)
                .clipped()

            if store.settings.showPhonetic {
                phoneticsRow(entry)
                    .frame(height: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    // MARK: - Word detail (scrolling content)

    private func wordDetail(_ entry: WordEntry) -> some View {
        let settings = store.settings
        let meaningRevealed = revealedDefinitionWordID == entry.id
        return VStack(alignment: .leading, spacing: 12) {
            if settings.showShortcutHint {
                shortcutHint
            }

            if settings.showChinese {
                meaningBlock(entry, isRevealed: meaningRevealed)
            }

            if settings.showEnglish, !entry.englishDefinition.isEmpty {
                englishBlock(entry)
            }

            if settings.showExample, !entry.example.isEmpty {
                exampleBlock(entry)
            }

            if settings.showAIHint {
                aiBlock(entry)
            }
        }
    }

    /// English (English-to-English) definition — always visible, never masked.
    private func englishBlock(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("英英释义")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(entry.englishDefinition)
                .font(.maple(14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func exampleBlock(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("例句")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(entry.example)
                .font(.system(size: 14, design: .serif))
                .italic()
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// US + UK phonetics, stacked vertically (one per line) so even long
    /// transcriptions show in full. Falls back to the single `phonetic` when a
    /// source doesn't distinguish accents.
    @ViewBuilder
    private func phoneticsRow(_ entry: WordEntry) -> some View {
        let us = entry.phoneticUS.isEmpty ? entry.phonetic : entry.phoneticUS
        let uk = entry.phoneticUK.isEmpty ? entry.phonetic : entry.phoneticUK

        VStack(alignment: .leading, spacing: 4) {
            if !us.isEmpty {
                phoneticChip(label: "US", value: us, accent: .american)
            }
            if !uk.isEmpty, uk != us || !entry.phoneticUK.isEmpty {
                phoneticChip(label: "UK", value: uk, accent: .british)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phoneticChip(label: String, value: String, accent: SpeechAccent) -> some View {
        Button {
            actions.speak(accent)
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent(for: store.settings.accentColor))
                    .frame(width: 20, alignment: .leading)
                Text(MeaningFormatter.formattedPhonetic(value))
                    .font(.maple(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent(for: store.settings.accentColor))
            }
        }
        .buttonStyle(.plain)
        .help("\(label) \(MeaningFormatter.formattedPhonetic(value))")
    }

    private var shortcutHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(Theme.inkSoft)
            Text("Space 认识  ·  ←/→  ·  ↵ 朗读  ·  ⌘F 搜索")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Button {
                store.updateSettings { $0.showShortcutHint = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            .help("隐藏快捷键提示（可在设置中重新打开）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meaningBlock(_ entry: WordEntry, isRevealed: Bool) -> some View {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech(entry.meaning)
        return glassMeaningCard(entry: entry, isRevealed: isRevealed || body.isEmpty) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let pos {
                    Text(pos)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent(for: store.settings.accentColor))
                }
                Text(body.isEmpty ? "暂无释义，点击 Dictionary 查询。" : body)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Wraps the Chinese meaning behind a frosted-glass pane. Until tapped, the
    /// characters shimmer faintly through the glass (若隐若现) rather than being
    /// fully hidden; a tap clears the glass with a soft fade.
    private func glassMeaningCard<Content: View>(
        entry: WordEntry,
        isRevealed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.3)) {
                revealedDefinitionWordID = entry.id
            }
        } label: {
            content()
                // Light Gaussian on the glyphs: shapes glimmer, words don't read.
                .blur(radius: isRevealed ? 0 : 4.5)
                .clipShape(shape)
                .overlay {
                    if !isRevealed {
                        frostedVeil(shape).transition(.opacity)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(isRevealed ? "释义已显示" : "点击显示释义")
    }

    /// A translucent frosted pane that lets the blurred meaning glimmer through,
    /// finished with a diagonal specular sheen, a faint azure tint, and a bright
    /// rim so it reads as a real pane of glass.
    private func frostedVeil(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial).opacity(0.5)
            shape.fill(Theme.accent(for: store.settings.accentColor).opacity(0.06))
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear, .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }

    @ViewBuilder
    private func aiBlock(_ entry: WordEntry) -> some View {
        switch store.aiState {
        case .idle:
            if !entry.note.isEmpty {
                Text(.init(entry.note))
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent(for: store.settings.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Generating memory hint…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            }
        case .failed(let message):
            noticeText(message, color: .red)
        }
    }

    // MARK: - Controls

    private func controls(for entry: WordEntry) -> some View {
        VStack(spacing: 10) {
            noticeBlock

            if !store.isShowingTemporaryPreview {
                HStack(spacing: 12) {
                    navButton(systemImage: "chevron.left", action: actions.showPrevious)

                    if store.settings.reviewMode == .smart {
                        gradeRow
                    } else {
                        knownPill(for: entry)
                    }

                    navButton(systemImage: "chevron.right", action: actions.showNext)
                }
            }

            secondaryRow(entry)
        }
    }

    /// Three-way recall grading (Smart mode) — drives the SM-2 schedule and
    /// advances to the next word.
    private var gradeRow: some View {
        HStack(spacing: 6) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    actions.grade(grade)
                } label: {
                    Text(grade.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(color(for: grade))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(color(for: grade).opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(color(for: grade).opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())
                .help(grade.title)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again:
            Color(light: NSColor(srgbRed: 0.90, green: 0.35, blue: 0.38, alpha: 1), dark: NSColor(srgbRed: 0.95, green: 0.45, blue: 0.48, alpha: 1))
        case .hard:
            Color(light: NSColor(srgbRed: 0.85, green: 0.55, blue: 0.20, alpha: 1), dark: NSColor(srgbRed: 0.90, green: 0.65, blue: 0.35, alpha: 1))
        case .good:
            Theme.accent(for: store.settings.accentColor)
        }
    }

    /// Single "known" action for sequential/random modes (no SRS scheduling).
    private func knownPill(for entry: WordEntry) -> some View {
        Button {
            actions.toggleMastered()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: entry.status == .mastered ? "checkmark.seal.fill" : "checkmark")
                Text(entry.status == .mastered ? "已掌握" : "已认识")
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.accent(for: store.settings.accentColor))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.accent(for: store.settings.accentColor).opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(Theme.accent(for: store.settings.accentColor).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Icon-only circular nav button (Apple-style) — just a chevron, no label.
    private func navButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Smart-mode "known" via the Space shortcut grades the word `good`; other
    /// modes mark it mastered.
    private func primaryAction(for entry: WordEntry) {
        if store.settings.reviewMode == .smart {
            actions.grade(.good)
        } else {
            actions.toggleMastered()
        }
    }

    /// Slim toolbar: search + AI + overflow menu (scheme A).
    /// Dictionary / delete / undo / settings / quit live under 「更多」.
    private func secondaryRow(_ entry: WordEntry) -> some View {
        Group {
            if isSearchExpanded {
                searchPanel
            } else {
                HStack(spacing: 12) {
                    iconLink("magnifyingglass", tooltip: "搜索单词 (⌘F)", action: expandSearch)
                    iconLink("sparkles", tooltip: "AI 提示", action: actions.generateAIInsight)
                        .disabled(!store.settings.aiEnabled || store.aiState == .loading)
                    Spacer(minLength: 8)
                    moreMenu
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchExpanded)
    }

    /// Overflow for lower-frequency actions — keeps the bar uncluttered.
    private var moreMenu: some View {
        Menu {
            Button {
                actions.openSystemDictionary()
            } label: {
                Label("系统词典", systemImage: "text.book.closed")
            }

            if store.canUndoGrade {
                Button {
                    actions.undoGrade()
                } label: {
                    Label("撤销评分", systemImage: "arrow.uturn.backward")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("删除当前词", systemImage: "trash")
            }
            .disabled(store.currentWord == nil)

            Divider()

            Button {
                actions.openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                actions.quit()
            } label: {
                Label("退出 FastWords", systemImage: "door.left.hand.open")
            }
        } label: {
            // Plain "ellipsis" (not ellipsis.circle) so it matches 🔍 / ✨:
            // same weight + soft circular chip background, no double-ring glyph.
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("更多")
    }

    private func expandSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchExpanded = true
        }
        // Focus after the expand animation so the field is in the hierarchy.
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func collapseSearch() {
        isSearchFocused = false
        searchQuery = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchExpanded = false
        }
    }

    private func submitSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        // Keep the bar open while loading so the spinner is visible; collapse
        // only when the query is resolved (jump / pending / failure).
        actions.searchWord(query)
    }

    private var searchSuggestions: [String] {
        store.searchSuggestions(for: searchQuery, limit: 6)
    }

    /// Expanded search field + live suggestions. Stays open during lookup.
    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !searchSuggestions.isEmpty, store.lookupState != .loading {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchSuggestions, id: \.self) { suggestion in
                        Button {
                            searchQuery = suggestion
                            actions.searchWord(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSoft)
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent(for: store.settings.accentColor))

                TextField("搜索单词，回车查询…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                    .onSubmit { submitSearch() }
                    .disabled(store.lookupState == .loading)

                if store.lookupState == .loading {
                    ProgressView()
                        .controlSize(.small)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    .help("清空")
                }

                Button(action: collapseSearch) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .help("收起搜索")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent(for: store.settings.accentColor).opacity(0.25), lineWidth: 1)
            )
        }
        .onChange(of: store.lookupState) { _, newValue in
            // Collapse after a successful jump (idle + no pending) or when a
            // pending confirm panel takes over the UI.
            if newValue == .idle, store.pendingSearch != nil || store.importMessage != nil || store.temporaryPreview != nil {
                // Keep open only while still loading; after resolve, close so
                // the card / confirm panel is fully visible.
                if store.pendingSearch != nil || store.temporaryPreview != nil {
                    collapseSearch()
                }
            }
            if case .failed = newValue {
                // Leave open so the user can edit and retry; notice shows error.
            }
        }
        .onChange(of: store.pendingSearch) { _, pending in
            if pending != nil { collapseSearch() }
        }
        .onChange(of: store.currentWord?.id) { _, _ in
            // Jump-to-book success: collapse search.
            if store.lookupState == .idle, store.pendingSearch == nil, isSearchExpanded, store.lookupState != .loading {
                // Only collapse if we just navigated via an exact jump (query matches card).
                if let w = store.currentWord?.word.lowercased(),
                   w == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                   !searchQuery.isEmpty {
                    collapseSearch()
                }
            }
        }
    }

    private func iconLink(_ systemImage: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .help(tooltip)
    }

    // MARK: - Notices

    @ViewBuilder
    private var noticeBlock: some View {
        switch store.lookupState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("查询词典中…").font(.caption).foregroundStyle(Theme.inkSoft)
                Spacer()
            }
        case .failed(let message):
            noticeText(message, color: .red)
        case .idle:
            if let message = store.importMessage {
                noticeText(message, color: Theme.inkSoft)
            }
        }
    }

    private func noticeText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent(for: store.settings.accentColor).opacity(0.6))
            Text("还没有词书")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("从设置选一本考试词书，或导入 TXT/CSV/JSON。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("导入词书", action: actions.importWordBook)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill(for: store.settings.accentColor))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard shortcuts

    /// Hidden buttons whose keyboard shortcuts drive review without the mouse:
    /// Space = known, ←/→ = prev/next, Return = speak, ⌘F = search, ⌘Z = undo.
    private var keyboardShortcuts: some View {
        VStack {
            Button("") { if let w = store.currentWord { primaryAction(for: w) } }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { actions.showPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { actions.showNext() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { actions.speak(store.settings.speechAccent) }
                .keyboardShortcut(.return, modifiers: [])
            Button("") { expandSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { actions.undoGrade() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndoGrade)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
