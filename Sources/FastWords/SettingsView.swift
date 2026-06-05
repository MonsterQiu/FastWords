import FastWordsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WordStore
    @State private var selectedExam: ExamCategory = .cet4

    private let refreshOptions: [(String, TimeInterval)] = [
        ("Manual", 0),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900)
    ]

    var body: some View {
        Form {
            Section("Review") {
                Picker("Refresh", selection: binding(\.refreshInterval)) {
                    ForEach(refreshOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }

                Picker("Order", selection: binding(\.reviewMode)) {
                    ForEach(ReviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("Pronunciation") {
                Picker("Accent", selection: binding(\.speechAccent)) {
                    ForEach(SpeechAccent.allCases) { accent in
                        Text(accent.title).tag(accent)
                    }
                }

                HStack {
                    Text("Speed")
                    Slider(value: binding(\.speechRate), in: 0...1)
                }

                Toggle("Speak each new word automatically", isOn: binding(\.autoSpeak))

                Text("Uses the built-in macOS voice — fully offline, no setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Exam Word Books") {
                Picker("Exam", selection: $selectedExam) {
                    ForEach(ExamCategory.allCases) { exam in
                        Text(exam.title).tag(exam)
                    }
                }

                Button("Load this word book") {
                    store.loadExamBook(selectedExam)
                }

                Text("Built-in offline 中英词典 (ECDICT). Loading replaces the current word book.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI") {
                Toggle("Enable AI hints", isOn: binding(\.aiEnabled))

                TextField("Base URL", text: binding(\.aiBaseURL))
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: binding(\.aiModel))
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: binding(\.aiAPIKey))
                    .textFieldStyle(.roundedBorder)

                Text("Uses an OpenAI-compatible /chat/completions endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460, height: 540)
    }

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
