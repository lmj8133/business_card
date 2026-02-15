import SwiftUI

/// App settings — Ollama server configuration and OCR preferences.
struct SettingsView: View {
    @AppStorage("ollamaModel") private var ollamaModel = "gemma3:27b"
    @AppStorage("ocrLanguages") private var ocrLanguages = "zh-Hant,en,ja"

    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isTesting = false
    @State private var availableModels: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    #if DEBUG
                    if availableModels.isEmpty {
                        LabeledContent("Model") {
                            TextField("gemma3:12b", text: $ollamaModel)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Picker("Model", selection: $ollamaModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    #endif

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

                    if case .failure(let msg) = connectionStatus {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                #if DEBUG
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
                #endif

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }

                    #if DEBUG
                    HStack {
                        Text("OCR Engine")
                        Spacer()
                        Text("Apple Vision")
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
            }
            .navigationTitle("Settings")
        }
    }

    private let genericError = "Unable to connect to server"

    /// Ollama server base URL (injected via Secrets.xcconfig → Info.plist).
    private var ollamaBaseURL: String {
        Bundle.main.infoDictionary?["OllamaBaseURL"] as? String
            ?? "http://localhost:11434"
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
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
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
                connectionStatus = .failure(genericError)
                return
            }

            let models = parseModelNames(from: data)
            availableModels = models

            if models.isEmpty {
                connectionStatus = .failure(genericError)
            } else if models.contains(ollamaModel) {
                connectionStatus = .success
            } else {
                ollamaModel = models[0]
                connectionStatus = .success
            }
        } catch {
            #if DEBUG
            connectionStatus = .failure(error.localizedDescription)
            #else
            connectionStatus = .failure(genericError)
            #endif
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
