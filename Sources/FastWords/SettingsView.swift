import FastWordsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WordStore

    private enum Section: String, CaseIterable, Identifiable {
        case stats, review, appearance, pronunciation, books, ai
        var id: String { rawValue }
        var title: String {
            switch self {
            case .stats: "统计"
            case .review: "复习"
            case .appearance: "外观"
            case .pronunciation: "发音"
            case .books: "词书"
            case .ai: "AI 助手"
            }
        }
        var icon: String {
            switch self {
            case .stats: "chart.bar.xaxis"
            case .review: "arrow.triangle.2.circlepath"
            case .appearance: "paintpalette"
            case .pronunciation: "speaker.wave.2"
            case .books: "books.vertical"
            case .ai: "sparkles"
            }
        }
    }

    @State private var selection: Section = .stats

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 168)
                .frame(maxHeight: .infinity)
                .background(.quaternary.opacity(0.5))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .frame(width: 600, height: 460)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Section.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .frame(width: 18)
                        Text(section.title)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == section ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .foregroundStyle(selection == section ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .stats: StatsView(store: store)
        case .review: reviewSettings
        case .appearance: appearanceSettings
        case .pronunciation: pronunciationSettings
        case .books: bookSettings
        case .ai: aiSettings
        }
    }

    // MARK: - 复习

    private let refreshOptions: [(String, TimeInterval)] = [
        ("手动（不自动翻页）", 0),
        ("30 秒", 30),
        ("1 分钟", 60),
        ("5 分钟", 300),
        ("15 分钟", 900)
    ]

    private var reviewSettings: some View {
        Form {
            SwiftUI.Section {
                Picker("自动翻页间隔", selection: binding(\.refreshInterval)) {
                    ForEach(refreshOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }

                Picker("复习顺序", selection: binding(\.reviewMode)) {
                    ForEach(ReviewMode.allCases) { mode in
                        Text(reviewModeTitle(mode)).tag(mode)
                    }
                }

                Text("「智能」模式按间隔重复（SM-2）优先安排到期和薄弱的单词。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func reviewModeTitle(_ mode: ReviewMode) -> String {
        switch mode {
        case .sequential: "顺序"
        case .random: "随机"
        case .smart: "智能（间隔重复）"
        }
    }

    // MARK: - 外观

    private var appearanceSettings: some View {
        Form {
            SwiftUI.Section("颜色") {
                Picker("主题色", selection: binding(\.accentColor)) {
                    ForEach(AccentColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
            }

            SwiftUI.Section("卡片显示内容") {
                Toggle("中文释义", isOn: binding(\.showChinese))
                Toggle("英英释义", isOn: binding(\.showEnglish))
                Toggle("音标", isOn: binding(\.showPhonetic))
                Toggle("例句", isOn: binding(\.showExample))
                Toggle("AI 记忆提示", isOn: binding(\.showAIHint))
                Toggle("快捷键提示栏", isOn: binding(\.showShortcutHint))
            }
        }
        .formStyle(.grouped)
    }



    // MARK: - 发音

    private var pronunciationSettings: some View {
        Form {
            Picker("口音", selection: binding(\.speechAccent)) {
                ForEach(SpeechAccent.allCases) { accent in
                    Text(accentTitle(accent)).tag(accent)
                }
            }

            HStack {
                Text("语速")
                Slider(value: binding(\.speechRate), in: 0...1)
            }

            Toggle("翻到新词时自动朗读", isOn: binding(\.autoSpeak))

            Text("使用 macOS 内置语音，完全离线、无需配置。有真人音频时优先播放真人发音。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func accentTitle(_ accent: SpeechAccent) -> String {
        switch accent {
        case .american: "美音（en-US）"
        case .british: "英音（en-GB）"
        }
    }

    // MARK: - 词书

    /// Word counts per exam category (cached once; the dictionary is read-only).
    private var examCounts: [ExamCategory: Int] { OfflineDictionary.shared.counts() }

    private let bookColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var bookSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("考试词库")
                    .font(.headline)
                Text("内置离线中英词典（ECDICT），全部免费。点击卡片加载或切换；已加载的词书保留各自进度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let book = store.currentBook {
                    HStack(spacing: 8) {
                        Text("当前《\(book.name)》")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("补全英英/释义") {
                            store.enrichCurrentBookFromOffline()
                        }
                        .help("为旧词书从内置词典补上英英释义等缺失内容")
                    }
                }

                LazyVGrid(columns: bookColumns, spacing: 12) {
                    ForEach(ExamCategory.allCases) { exam in
                        examCard(exam)
                    }
                }

                let extras = store.books.filter { if case .exam = $0.source { return false } else { return true } }
                if !extras.isEmpty {
                    Text("其他词书")
                        .font(.headline)
                        .padding(.top, 4)
                    LazyVGrid(columns: bookColumns, spacing: 12) {
                        ForEach(extras) { book in
                            customCard(book)
                        }
                    }
                }
            }
            .padding(2)
        }
    }

    /// A card for a built-in exam word book. Loaded books show progress and an
    /// "in use" marker; unloaded ones invite a tap to load.
    private func examCard(_ exam: ExamCategory) -> some View {
        let loaded = store.books.first { $0.source == .exam(exam) }
        let isCurrent = loaded?.id == store.currentBookID && loaded != nil
        let total = examCounts[exam] ?? 0

        return Button {
            store.loadExamBook(exam)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(exam.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                }

                if let loaded {
                    Text("\(loaded.words.count) 词 · \(store.masteredCount(in: loaded)) 已掌握")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(isCurrent ? "使用中" : "点击切换",
                          systemImage: isCurrent ? "largecircle.fill.circle" : "arrow.left.arrow.right")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .blue : .secondary)
                } else {
                    Text("\(total) 词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("点击加载", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.blue.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? Color.blue.opacity(0.7) : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// A card for a non-exam book (imported file or the sample book).
    private func customCard(_ book: WordBook) -> some View {
        let isCurrent = book.id == store.currentBookID
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(book.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                if isCurrent { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            }
            Text("\(book.words.count) 词 · \(store.masteredCount(in: book)) 已掌握")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !isCurrent {
                    Button("切换") { store.selectBook(book.id) }
                        .buttonStyle(.link)
                }
                Button(role: .destructive) { store.deleteBook(book.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除词书")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.blue.opacity(0.10) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCurrent ? Color.blue.opacity(0.7) : Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - AI

    private var aiSettings: some View {
        Form {
            Toggle("启用 AI 记忆提示", isOn: binding(\.aiEnabled))

            TextField("接口地址（Base URL）", text: binding(\.aiBaseURL))
                .textFieldStyle(.roundedBorder)
            TextField("模型名称", text: binding(\.aiModel))
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: binding(\.aiAPIKey))
                .textFieldStyle(.roundedBorder)

            Text("使用兼容 OpenAI 的 /chat/completions 接口，由你自己的服务商提供。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                store.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
