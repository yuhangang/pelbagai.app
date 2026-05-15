import SwiftUI
import Combine

/// Browse, manage, and export stored tool data.
/// Shows all tools with persistent storage, their result counts, and allows
/// viewing, exporting, or clearing individual tool datasets.
struct ToolDataView: View {
    @StateObject private var viewModel: ToolDataViewModel
    @StateObject private var exporter = ExcelExporter()
    
    @State private var selectedToolID: String?
    @State private var showExportSheet = false
    @State private var exportFileURL: URL?
    @State private var showClearConfirm = false
    @State private var clearTargetID: String?
    @State private var showDeleteDefinitionConfirm = false
    @State private var deleteDefinitionID: String?
    @State private var animateGradient = false
    @State private var animateGradient2 = false
    @State private var animateGradient3 = false
    
    private let env: AppEnvironment
    
    init(env: AppEnvironment) {
        self.env = env
        _viewModel = StateObject(wrappedValue: ToolDataViewModel(environment: env))
    }
    
    var body: some View {
        ZStack {
            // Background
            ZStack {
#if os(iOS)
                Color(UIColor.systemBackground).ignoresSafeArea()
#else
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()
#endif
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 320, height: 320)
                    .blur(radius: 65)
                    .offset(x: animateGradient ? 120 : -80, y: animateGradient ? -60 : -220)
                
                Circle()
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: 280, height: 280)
                    .blur(radius: 55)
                    .offset(x: animateGradient2 ? -100 : 100, y: animateGradient2 ? 140 : -40)
                
                Circle()
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: animateGradient3 ? 60 : -120, y: animateGradient3 ? -240 : 180)
            }
            
            VStack(spacing: 0) {
                if viewModel.toolCatalog.isEmpty && viewModel.userDefinitions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerSection
                            toolDefinitionsSection
                            
                            if !viewModel.toolCatalog.isEmpty {
                                statsCard
                            }
                            
                            ForEach(viewModel.toolCatalog) { tool in
                                toolCard(tool)
                            }
                            
                            if viewModel.toolCatalog.count > 1 {
                                clearAllButton
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .navigationTitle("Tool Storage")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !viewModel.toolCatalog.isEmpty {
                    Text(viewModel.totalStorageSize)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
        .task {
            viewModel.refresh()
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
            withAnimation(.easeInOut(duration: 11.0).repeatForever(autoreverses: true)) {
                animateGradient2.toggle()
            }
            withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                animateGradient3.toggle()
            }
        }
        .navigationDestination(for: NavigationItem.self) { item in
            switch item {
            case .scanner(let toolID):
                WorkbenchView(toolID: toolID ?? "parcel_address", env: env)
            default:
                EmptyView()
            }
        }
        .sheet(item: $selectedToolID) { toolID in
            ToolDetailSheet(toolID: toolID, env: env)
        }
        .sheet(isPresented: $showExportSheet) {
#if os(iOS)
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
#else
            VStack {
                Text("Exported to: \(exportFileURL?.path ?? "")")
                    .padding()
                Button("Show in Finder") {
                    if let url = exportFileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    showExportSheet = false
                }
                .padding()
                Button("Close") { showExportSheet = false }
                    .padding()
            }
            .frame(width: 400, height: 200)
#endif
        }
        .alert("Clear Tool Data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                if let id = clearTargetID {
                    if id == "__ALL__" {
                        viewModel.clearAll()
                    } else {
                        viewModel.clearTool(id)
                    }
                }
            }
        } message: {
            if clearTargetID == "__ALL__" {
                Text("This will permanently delete all stored tool data. This cannot be undone.")
            } else {
                Text("This will permanently delete all data for this tool. This cannot be undone.")
            }
        }
        .alert("Delete Tool Definition?", isPresented: $showDeleteDefinitionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = deleteDefinitionID {
                    viewModel.deleteUserDefinition(toolID: id)
                }
            }
        } message: {
            Text("This removes the custom tool definition. Stored scan data for the same tool is not deleted.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Gemma 4 Powered")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                
                Spacer()
            }
            
            Text("Tool Storage & Hub")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("Browse, execute, and inspect persistent dataset results from your local extraction tools.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var statsCard: some View {
        HStack(spacing: 12) {
            statItem(
                value: "\(viewModel.toolCatalog.count)",
                label: "Active Tools",
                icon: "wrench.and.screwdriver.fill",
                color: .indigo
            )
            
            statItem(
                value: "\(viewModel.totalResultCount)",
                label: "Total Results",
                icon: "doc.text.fill",
                color: .purple
            )
            
            statItem(
                value: viewModel.totalStorageSize,
                label: "Disk Size",
                icon: "internaldrive.fill",
                color: .cyan
            )
        }
        .padding(.top, 8)
    }
    
    private var toolDefinitionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Local Tools", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(viewModel.allDefinitions.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 12) {
                ForEach(viewModel.allDefinitions) { definition in
                    NavigationLink(value: NavigationItem.scanner(definition.toolID)) {
                        toolDefinitionRow(definition)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if !viewModel.userDefinitions.isEmpty {
                Button(role: .destructive) {
                    viewModel.resetUserDefinitions()
                } label: {
                    Label("Reset Custom Tools", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
    
    private func toolDefinitionRow(_ definition: LocalToolDefinition) -> some View {
        let isCustom = viewModel.isUserDefinition(definition.toolID)
        let color = definition.uiColor
        let iconName = definition.uiIcon
        
        return HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4, height: 36)
            
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(definition.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(isCustom ? "Custom" : "Bundled")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(isCustom ? .cyan : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isCustom ? Color.cyan : Color.secondary).opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Text(definition.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(definition.toolID)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            if isCustom {
                Button(role: .destructive) {
                    deleteDefinitionID = definition.toolID
                    showDeleteDefinitionConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.02), lineWidth: 0.5)
        )
    }
    
    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
    
    private func toolCard(_ tool: ToolInfo) -> some View {
        let accentColor = templateColor(for: tool.id)
        
        return VStack(spacing: 12) {
            Button(action: {
                selectedToolID = tool.id
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: templateIcon(for: tool.id))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.displayName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 9))
                            Text("\(tool.resultCount)")
                            Text("•")
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                            Text(tool.formattedSize)
                            Text("•")
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(tool.formattedDate)
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(width: 26, height: 26)
                        
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider().opacity(0.4)
            
            HStack(spacing: 12) {
                Button(action: {
                    let results = viewModel.loadAllResults(for: tool.id)
                    if let url = exporter.exportToCSV(results: results) {
                        exportFileURL = url
                        showExportSheet = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Export CSV")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    clearTargetID = tool.id
                    showClearConfirm = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clear Data")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: accentColor.opacity(0.05), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(accentColor.opacity(0.12), lineWidth: 1.0)
                )
        )
    }
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "wrench.and.screwdriver",
            title: "No Stored Tool Data",
            description: "Run any tool from the Home screen or create a custom one. Scan results and historical persistent datasets will appear here."
        )
    }
    
    private var clearAllButton: some View {
        Button(action: {
            clearTargetID = "__ALL__"
            showClearConfirm = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13))
                Text("Clear All Storage")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 12)
    }
    
    private func templateColor(for toolID: String) -> Color {
        env.registry.definition(for: toolID)?.uiColor ?? .indigo
    }
    
    private func templateIcon(for toolID: String) -> String {
        env.registry.definition(for: toolID)?.uiIcon ?? "doc.text.fill"
    }
}

struct ToolDetailSheet: View {
    let toolID: String
    private let env: AppEnvironment
    @State private var results: [ScanResult] = []
    @State private var editingResult: ScanResult?
    @State private var showEditSheet = false
    @StateObject private var exporter = ExcelExporter()
    @State private var showExportSheet = false
    @State private var exportFileURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    init(toolID: String, env: AppEnvironment) {
        self.toolID = toolID
        self.env = env
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(results) { result in
                        resultRow(result)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    env.storage.delete(resultID: result.id, from: toolID)
                                    results.removeAll { $0.id == result.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    editingResult = result
                                    showEditSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                } header: {
                    Text("\(results.count) results")
                } footer: {
                    if !results.isEmpty {
                        Text("Swipe left on a row to edit or delete.")
                    }
                }
            }
            .navigationTitle(toolID.replacingOccurrences(of: "_", with: " ").capitalized)
    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !results.isEmpty {
                        Button {
                            if let url = exporter.exportToCSV(results: results) {
                                exportFileURL = url
                                showExportSheet = true
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear {
                results = env.storage.loadAll(from: toolID)
            }
            .sheet(isPresented: $showEditSheet) {
                if let result = editingResult {
                    ScanResultEditSheet(result: result) { updated in
                        env.storage.update(updated, in: toolID)
                        if let idx = results.firstIndex(where: { $0.id == updated.id }) {
                            results[idx] = updated
                        }
                        showEditSheet = false
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
#if os(iOS)
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
#else
                VStack {
                    Text("Exported to: \(exportFileURL?.path ?? "")")
                        .padding()
                    Button("Show in Finder") {
                        if let url = exportFileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        showExportSheet = false
                    }
                    .padding()
                    Button("Close") { showExportSheet = false }
                        .padding()
                }
                .frame(width: 400, height: 200)
#endif
            }
        }
    }
    
    private func resultRow(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: result.isValidated ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(result.isValidated ? .green : .orange)
                    .font(.system(size: 12))
                
                Text(result.primaryValue)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(1)
                
                Spacer()
                
                Text(result.timestamp, style: .relative)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            let topKeys = result.sortedKeys.prefix(3)
            ForEach(Array(topKeys), id: \.self) { key in
                if let fv = result.richFields[key], !fv.isEmpty {
                    if fv.isList {
                        HStack(alignment: .top, spacing: 4) {
                            Text(key + ":")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(fv.asList.prefix(3), id: \.self) { item in
                                    HStack(spacing: 3) {
                                        Circle().fill(Color.secondary).frame(width: 3, height: 3)
                                        Text(item)
                                            .font(.system(size: 11))
                                            .foregroundColor(.primary.opacity(0.7))
                                            .lineLimit(1)
                                    }
                                }
                                if fv.asList.count > 3 {
                                    Text("+\(fv.asList.count - 3) more")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(key + ":")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(fv.flatString)
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            if result.richFields.count > 3 {
                Text("+\(result.richFields.count - 3) more fields")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 6) {
                if result.scriptNotes != nil {
                    Label("Notes", systemImage: "scroll")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Capsule())
                }
                if !result.actions.isEmpty {
                    Label("\(result.actions.count) actions", systemImage: "bolt.badge.checkmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                }
                if let state = result.state, !state.isEmpty {
                    Label("\(state.count) state vars", systemImage: "memorychip")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Make String identifiable for sheet presentation
extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    ToolDataView(env: AppEnvironment())
}
