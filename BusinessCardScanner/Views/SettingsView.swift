import SwiftUI

/// App settings — Ollama server configuration and OCR preferences.
struct SettingsView: View {
    @AppStorage("ollamaBaseURL") private var ollamaBaseURL = "http://localhost:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "gemma3:27b"
    @AppStorage("ocrLanguages") private var ocrLanguages = "zh-Hant,en,ja"

    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isTesting = false
    @State private var availableModels: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Ollama Server") {
                    HStack {
                        Text("URL")
                            .frame(width: 60, alignment: .leading)
                        TextField("http://192.168.1.100:11434", text: $ollamaBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    HStack {
                        Text("Model")
                            .frame(width: 60, alignment: .leading)
                        if availableModels.isEmpty {
                            TextField("gemma3:12b", text: $ollamaModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            Picker("", selection: $ollamaModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "network")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else {
                                connectionStatusIcon
                            }
                        }
                    }
                    .disabled(isTesting)
                }

                Section("OCR") {
                    HStack {
                        Text("Languages")
                        Spacer()
                        TextField("zh-Hant,en,ja", text: $ocrLanguages)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Text("Comma-separated language codes. Supported: zh-Hant, zh-Hans, en, ja, ko, fr, de, es, pt, it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("OCR Engine")
                        Spacer()
                        Text("Apple Vision")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Connection Test

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch connectionStatus {
        case .unknown:
            EmptyView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let msg):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(msg)
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }

        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            connectionStatus = .failure("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                connectionStatus = .failure("Unexpected status code")
                return
            }

            let models = parseModelNames(from: data)
            availableModels = models

            if models.isEmpty {
                connectionStatus = .failure("No models installed on server")
            } else if models.contains(ollamaModel) {
                connectionStatus = .success
            } else {
                ollamaModel = models[0]
                connectionStatus = .success
            }
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    /// Extract sorted model names from Ollama `/api/tags` response.
    private func parseModelNames(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }
}

private enum ConnectionStatus {
    case unknown
    case success
    case failure(String)
}
