import FastWordsCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: WordStore
    let actions: AppActions
    @State private var revealedDefinitionWordID: UUID?

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

                Divider().overlay(Theme.accent.opacity(0.18))

                if let word = store.currentWord {
                    // Fixed title area (headword + phonetics) — independent of the
                    // scrolling content, so its position never changes per word.
                    titleArea(word)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    // The content area always fills the remaining height, so the
                    // controls stay pinned to the bottom no matter how much
                    // content a word has. Long content scrolls inside this region.
                    ScrollView {
                        wordDetail(word)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    Divider().overlay(Theme.accent.opacity(0.10))

                    controls(for: word)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                } else {
                    emptyState
                }
            }

            // Invisible buttons that own the keyboard shortcuts.
            keyboardShortcuts
        }
        .frame(width: 360, height: 540)
        .tint(Theme.accent)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(Theme.accent)

            bookSwitcher

            Spacer()

            Text(store.progressText)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)

            Button(action: actions.openSettings) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            .help("Settings")
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
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.stroke.opacity(0.6), lineWidth: 1)
        )
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
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, alignment: .leading)
                Text(MeaningFormatter.formattedPhonetic(value))
                    .font(.maple(13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        .help("\(label) \(MeaningFormatter.formattedPhonetic(value))")
    }

    private var shortcutHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(Theme.inkSoft)
            Text("Space 已认识  ·  ←/→ 翻页  ·  ↵ 朗读")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
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
                        .foregroundStyle(Theme.accent)
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
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke.opacity(0.6), lineWidth: 1)
            )
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
            shape.fill(Theme.accent.opacity(0.06))
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

    private func exampleBlock(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("例句")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(entry.example)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.5)).frame(width: 3)
        }
    }

    @ViewBuilder
    private func aiBlock(_ entry: WordEntry) -> some View {
        switch store.aiState {
        case .idle:
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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

            HStack(spacing: 12) {
                navButton(systemImage: "chevron.left", action: actions.showPrevious)

                if store.settings.reviewMode == .smart {
                    gradeRow
                } else {
                    knownPill(for: entry)
                }

                navButton(systemImage: "chevron.right", action: actions.showNext)
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
                .buttonStyle(.plain)
                .help(grade.title)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again:
            Color(.systemRed)
        case .hard:
            Color(.systemOrange)
        case .good:
            Theme.accent
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
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.accent.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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

    private func secondaryRow(_ entry: WordEntry) -> some View {
        HStack(spacing: 16) {
            iconLink("character.book.closed", "查词典", action: actions.lookUp)
                .disabled(store.lookupState == .loading)
            iconLink("sparkles", "AI 提示", action: actions.generateAIInsight)
                .disabled(!store.settings.aiEnabled || store.aiState == .loading)
            Spacer()
            iconLink("door.left.hand.open", "退出", action: actions.quit)
            iconLink("gearshape", "设置", action: actions.openSettings)
        }
        .font(.system(size: 12))
    }

    private func iconLink(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .foregroundStyle(Theme.inkSoft)
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text("还没有词书")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("从设置选一本考试词书，或导入 TXT/CSV/JSON。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("导入词书", action: actions.importWordBook)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard shortcuts

    /// Hidden buttons whose keyboard shortcuts drive review without the mouse:
    /// Space = known, ←/→ = prev/next, Return = speak.
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
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
