import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = true
    
    init(env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(environment: env))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Model Configuration"), footer: Text("Select the AI model you want to use. Larger models may take longer to load. First use downloads model weights and keeps them on-device for later offline use.")) {
                    Picker("Active Model", selection: Binding(
                        get: { viewModel.selectedModel },
                        set: { viewModel.switchModel(to: $0) }
                    )) {
                        ForEach(GemmaModel.availableModels) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(viewModel.loadingStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Label(
                        viewModel.selectedModel.isDownloaded ? "Stored locally on this device" : "Will download when you load it the first time",
                        systemImage: viewModel.selectedModel.isDownloaded ? "internaldrive.fill" : "arrow.down.circle"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section(header: Text("Compute Backend"), footer: Text("GPU (Metal) is recommended for speed. CPU can be more stable if you encounter out-of-memory crashes with large models.")) {
                    Picker("Inference Backend", selection: Binding(
                        get: { viewModel.preferredBackend },
                        set: { viewModel.switchBackend(to: $0) }
                    )) {
                        ForEach(MLXBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if viewModel.preferredBackend == .cpu {
                        Label("Running on CPU is significantly slower.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Voice & Audio")) {
                    Toggle("Text-to-Speech", isOn: $ttsEnabled)
                }
                
                Section(header: Text("Storage Management")) {
                    NavigationLink(destination: ToolDataView(env: viewModel.environment)) {
                        Label("Manage Tool Storage", systemImage: "externaldrive.fill")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(env: AppEnvironment())
}
