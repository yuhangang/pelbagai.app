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
                if viewModel.allDefinitions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection
                            
                            statsCard
                            
                            toolsCatalogSection
                            
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
        .navigationTitle("Tool Hub")
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
    
    private var toolsCatalogSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Tool Hub & Catalog", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(viewModel.allDefinitions.count) Available")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                ForEach(viewModel.allDefinitions) { definition in
                    let storedInfo = viewModel.toolCatalog.first(where: { $0.id == definition.toolID })
                    let isCustom = viewModel.isUserDefinition(definition.toolID)
                    let color = definition.uiColor
                    let iconName = definition.uiIcon
                    
                    NavigationLink(value: NavigationItem.scanner(definition.toolID)) {
                        HStack(alignment: .center, spacing: 14) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(width: 4, height: 44)
                            
                            ZStack {
                                Circle()
                                    .fill(color.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(color)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(definition.displayName)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                
                                Text(definition.toolID)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 6) {
                                if let info = storedInfo, info.resultCount > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 9))
                                        Text("\(info.resultCount)")
                                        Text("•")
                                        Text(info.formattedSize)
                                    }
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(color.opacity(0.12))
                                    .clipShape(Capsule())
                                } else {
                                    Text("Ready")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.04))
                                        .clipShape(Capsule())
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.3))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .shadow(color: color.opacity(0.03), radius: 6, x: 0, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        if let info = storedInfo, info.resultCount > 0 {
                            Button {
                                let results = viewModel.loadAllResults(for: info.id)
                                if let url = exporter.exportToCSV(results: results) {
                                    exportFileURL = url
                                    showExportSheet = true
                                }
                            } label: {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                            
                            Button(role: .destructive) {
                                clearTargetID = info.id
                                showClearConfirm = true
                            } label: {
                                Label("Clear Stored Data", systemImage: "trash")
                            }
                        }
                        
                        if isCustom {
                            Divider()
                            
                            Button(role: .destructive) {
                                deleteDefinitionID = definition.toolID
                                showDeleteDefinitionConfirm = true
                            } label: {
                                Label("Delete Custom Tool", systemImage: "trash.slash")
                            }
                        }
                    }
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
                .padding(.top, 4)
            }
        }
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
}

// Make String identifiable for sheet presentation
extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    ToolDataView(env: AppEnvironment())
}
