import FastWordsCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: WordStore
    let actions: AppActions

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
                    ScrollView {
                        wordDetail(word)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                    }
                    .scrollIndicators(.never)

                    controls(for: word)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(Theme.accent)
            Text("FastWords")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)

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

    // MARK: - Word detail

    private func wordDetail(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.word)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            phoneticsRow(entry)

            shortcutHint

            meaningBlock(entry)

            if !entry.example.isEmpty {
                exampleBlock(entry)
            }

            aiBlock(entry)
        }
    }

    /// US + UK phonetics, each with its own speaker. Falls back to the single
    /// `phonetic` when a source doesn't distinguish accents.
    @ViewBuilder
    private func phoneticsRow(_ entry: WordEntry) -> some View {
        let us = entry.phoneticUS.isEmpty ? entry.phonetic : entry.phoneticUS
        let uk = entry.phoneticUK.isEmpty ? entry.phonetic : entry.phoneticUK

        HStack(spacing: 10) {
            if !us.isEmpty {
                phoneticChip(label: "US", value: us, accent: .american)
            }
            if !uk.isEmpty, uk != us || !entry.phoneticUK.isEmpty {
                phoneticChip(label: "UK", value: uk, accent: .british)
            }
            Spacer()
        }
    }

    private func phoneticChip(label: String, value: String, accent: SpeechAccent) -> some View {
        Button {
            actions.speak(accent)
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Pronounce (\(label))")
    }

    private var shortcutHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(Theme.inkSoft)
            Text("Space 已认识  ·  ←/→ 翻页  ·  ↵ 朗读")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meaningBlock(_ entry: WordEntry) -> some View {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech(entry.meaning)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
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
                navButton(systemImage: "chevron.left", title: "上一条", action: actions.showPrevious)

                Button {
                    primaryAction(for: entry)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: entry.status == .mastered ? "checkmark.seal.fill" : "checkmark")
                        Text(entry.status == .mastered ? "已掌握" : "已认识")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)

                navButton(systemImage: "chevron.right", title: "下一条", action: actions.showNext)
            }

            secondaryRow(entry)
        }
    }

    private func navButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(Theme.inkSoft)
            .frame(width: 56)
        }
        .buttonStyle(.plain)
    }

    /// Smart mode grades the word "known" via SRS; other modes just mark mastered.
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
            iconLink("square.and.arrow.down", "导入", action: actions.importWordBook)
            Spacer()
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
