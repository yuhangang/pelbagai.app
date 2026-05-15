import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = true
    @AppStorage("gemma4AudioInputEnabled") private var gemma4AudioInputEnabled: Bool = true
    
    init(env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(environment: env))
    }
    
    var body: some View {
        Form {
            Section(header: Text("Active Model Selection")) {
                Picker("Active Model", selection: Binding(
                    get: { viewModel.selectedModel },
                    set: { viewModel.switchModel(to: $0) }
                )) {
                    ForEach(GemmaModel.availableModels) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                
                Label(
                    viewModel.selectedModel.isDownloaded ? "Stored locally" : "Not downloaded",
                    systemImage: viewModel.selectedModel.isDownloaded ? "internaldrive.fill" : "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Section(header: Text("Model Management"), footer: Text("Download models for offline use or remove them to free up space.")) {
                ForEach(GemmaModel.availableModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(.body, design: .rounded, weight: .medium))
                            if model == viewModel.selectedModel {
                                Text("Selected")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.cyan.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        
                        Spacer()
                        
                        if viewModel.isDownloading && viewModel.downloadingModel == model {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("\(Int(viewModel.downloadProgress * 100))%")
                                    .font(.caption2.monospacedDigit())
                            }
                        } else if model.isDownloaded {
                            Button(role: .destructive) {
                                viewModel.deleteModel(model)
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        } else {
                            Button {
                                viewModel.downloadModel(model)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
                Toggle("Prefer Gemma 4 Direct Audio", isOn: Binding(
                    get: { gemma4AudioInputEnabled },
                    set: { newValue in
                        gemma4AudioInputEnabled = newValue
                        viewModel.setGemma4AudioInputEnabled(newValue)
                    }
                ))
                Text("Experimental. Used only on memory tiers where the selected Gemma model can load its audio tower safely; otherwise voice falls back to speech-to-text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        }
        .navigationTitle("Settings")
        .alert("Large Download", isPresented: $viewModel.showDownloadWarning) {
            Button("Download Anyway") {
                viewModel.confirmDownload()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDownload()
            }
        } message: {
            Text("You are currently on a cellular connection or hotspot. Downloading a model requires several gigabytes of data. Do you want to proceed?")
        }
    }
}

#Preview {
    SettingsView(env: AppEnvironment())
}
