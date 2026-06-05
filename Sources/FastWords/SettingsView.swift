import FastWordsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WordStore

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

                Picker("Menu bar", selection: binding(\.displayMode)) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Order", selection: binding(\.reviewMode)) {
                    ForEach(ReviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
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
        .frame(width: 460, height: 420)
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
