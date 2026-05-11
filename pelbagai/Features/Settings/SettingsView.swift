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
                Section(header: Text("Model Configuration"), footer: Text("Select the AI model you want to use. Larger models may take longer to load.")) {
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
