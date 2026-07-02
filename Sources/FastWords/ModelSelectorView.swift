import SwiftUI

struct ModelInfo: Identifiable, Decodable {
    let id: String
}

struct ModelListResponse: Decodable {
    let data: [ModelInfo]
}

struct ModelSelectorView: View {
    @Binding var baseURL: String
    @Binding var apiKey: String
    @Binding var selectedModel: String
    
    @State private var availableModels: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: fetchModels) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .help("获取可用模型列表")
                .disabled(baseURL.isEmpty || apiKey.isEmpty)
            }
            
            if !availableModels.isEmpty {
                Picker("", selection: $selectedModel) {
                    Text("请选择...").tag("")
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
            } else {
                TextField("模型名称 (如: gpt-3.5-turbo)", text: $selectedModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    private func fetchModels() {
        guard let url = URL(string: baseURL.hasSuffix("/") ? "\(baseURL)models" : "\(baseURL)/models") else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
                    availableModels = response.data.map { $0.id }.sorted()
                    // Auto-select if current model isn't in list or list has items and current is empty
                    if !availableModels.isEmpty && (selectedModel.isEmpty || !availableModels.contains(selectedModel)) {
                        selectedModel = availableModels[0]
                    }
                } catch {
                    errorMessage = "Failed to parse models"
                    print("Model parse error: \(error), Data: \(String(data: data, encoding: .utf8) ?? "")")
                }
            }
        }.resume()
    }
}
