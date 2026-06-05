import FastWordsCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var store: WordStore
    let actions: AppActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let word = store.currentWord {
                wordCard(word)
                progressBlock
                controls(for: word)
            } else {
                emptyState
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(18)
        .frame(width: 380, height: 440)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FastWords")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: actions.openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    private func wordCard(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.word)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                statusPill(entry.status)
            }

            if !entry.phonetic.isEmpty {
                Text(entry.phonetic)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(entry.meaning.isEmpty ? "No meaning yet. Import a richer word book when ready." : entry.meaning)
                .font(.system(size: 17, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            if !entry.example.isEmpty {
                Text(entry.example)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            aiBlock(entry)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45))
        )
    }

    private func statusPill(_ status: WordStatus) -> some View {
        Text(status == .mastered ? "Mastered" : "Learning")
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .mastered ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(status == .mastered ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
            )
    }

    @ViewBuilder
    private func aiBlock(_ entry: WordEntry) -> some View {
        switch store.aiState {
        case .idle:
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Generating memory hint…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: store.progressValue)
            Text("\(store.masteredCount) mastered · \(store.words.count - store.masteredCount) learning")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func controls(for entry: WordEntry) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: actions.showPrevious) {
                    Label("Previous", systemImage: "chevron.left")
                }

                Button(action: actions.showNext) {
                    Label("Next", systemImage: "chevron.right")
                }

                Button(action: actions.toggleMastered) {
                    Label(entry.status == .mastered ? "Unmark" : "Mastered", systemImage: "checkmark.circle")
                }
            }

            HStack(spacing: 10) {
                Button(action: actions.generateAIInsight) {
                    Label("AI Hint", systemImage: "sparkles")
                }
                .disabled(!store.settings.aiEnabled || store.aiState == .loading)

                Button(action: actions.importWordBook) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No word book")
                .font(.title2.weight(.semibold))
            Text("Import a TXT, CSV, or JSON file to begin.")
                .foregroundStyle(.secondary)
            Button(action: actions.importWordBook) {
                Label("Import Word Book", systemImage: "square.and.arrow.down")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var footer: some View {
        HStack {
            Button("Restore Samples", action: actions.restoreSamples)
                .buttonStyle(.link)

            Spacer()

            Button("Quit", action: actions.quit)
                .buttonStyle(.link)
        }
        .font(.caption)
    }
}
