import SwiftUI
import PhotosUI
import CoreImage

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Capability Block Container

/// Lays out tool capability blocks in a responsive grid.
/// Each capability from the tool definition maps to a prebuilt SwiftUI block.
struct CapabilityGridView: View {
    let tool: LocalToolDefinition
    let toolColor: Color
    
    // External bindings for cross-block communication
    @Binding var showCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var savedResults: [ScanResult]
    @Binding var showExportSheet: Bool
    @Binding var exportFileURL: URL?
    
    let env: AppEnvironment
    @StateObject private var exporter = ExcelExporter()
    
    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tool.capabilities, id: \.rawValue) { capability in
                capabilityBlock(for: capability)
            }
        }
    }
    
    @ViewBuilder
    private func capabilityBlock(for capability: LocalToolDefinition.Capability) -> some View {
        switch capability {
        case .scanImage:
            ScanImageBlock(
                toolColor: toolColor,
                showCamera: $showCamera,
                selectedPhotoItem: $selectedPhotoItem,
                isProcessing: env.vision.isProcessing,
                isModelLoaded: env.vision.isModelLoaded
            )
        case .exportCSV:
            let lastResult = env.vision.lastResult
            let hasActiveResult = lastResult?.toolID == tool.toolID && !env.vision.isProcessing
            let totalCount = savedResults.count + (hasActiveResult ? 1 : 0)
            
            ExportCSVBlock(
                toolColor: toolColor,
                resultCount: totalCount,
                onExport: {
                    var resultsToExport = savedResults
                    if hasActiveResult, let last = lastResult {
                        resultsToExport.insert(last, at: 0)
                    }
                    if let url = exporter.exportToCSV(results: resultsToExport) {
                        exportFileURL = url
                        showExportSheet = true
                    }
                }
            )
        case .persistentState:
            PersistentStateBlock(
                toolColor: toolColor,
                toolID: tool.toolID,
                env: env
            )
        case .openURL:
            EmptyView()
        case .htmlView:
            EmptyView()
        case .vectorSearch:
            EmptyView()
        }
    }
}

// MARK: - Scan Image Block

/// Camera & photo picker capability block.
struct ScanImageBlock: View {
    let toolColor: Color
    @Binding var showCamera: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let isProcessing: Bool
    let isModelLoaded: Bool
    
    var body: some View {
        CapabilityBlockShell(
            capability: .scanImage,
            toolColor: toolColor
        ) {
            VStack(spacing: 10) {
                // Camera button
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Camera")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [toolColor, toolColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    )
                }
                .disabled(isProcessing)
                
                // Photo library picker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Library")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                }
                .disabled(isProcessing)
                
                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(isModelLoaded ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(isModelLoaded ? "Model ready" : "Loading…")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Export CSV Block

/// Export results capability block.
struct ExportCSVBlock: View {
    let toolColor: Color
    let resultCount: Int
    let onExport: () -> Void
    
    var body: some View {
        CapabilityBlockShell(
            capability: .exportCSV,
            toolColor: toolColor
        ) {
            VStack(spacing: 10) {
                // Result count badge
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("\(resultCount) result\(resultCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Export button
                Button(action: onExport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Export")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(resultCount > 0 ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(resultCount > 0 ? 0.1 : 0.04))
                    )
                }
                .disabled(resultCount == 0)
            }
        }
    }
}

// MARK: - Persistent State Block

/// State variable viewer/editor capability block.
struct PersistentStateBlock: View {
    let toolColor: Color
    let toolID: String
    let env: AppEnvironment
    
    private var latestState: [String: String]? {
        env.storage.loadAll(from: toolID).first?.state
    }
    
    var body: some View {
        CapabilityBlockShell(
            capability: .persistentState,
            toolColor: toolColor
        ) {
            if let state = latestState, !state.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(state.keys.sorted().prefix(4), id: \.self) { key in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple.opacity(0.8))
                            Spacer(minLength: 4)
                            Text(state[key] ?? "")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    if state.count > 4 {
                        Text("+\(state.count - 4) more")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No state stored yet")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Open URL Block

/// Action buttons capability block.
struct OpenURLBlock: View {
    let toolColor: Color
    let results: [ScanResult]
    
    private var recentActions: [ToolAction] {
        results.flatMap(\.actions).prefix(3).map { $0 }
    }
    
    var body: some View {
        CapabilityBlockShell(
            capability: .openURL,
            toolColor: toolColor
        ) {
            if recentActions.isEmpty {
                Text("No actions available")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(recentActions) { action in
                        Button {
                            if let urlStr = action.url, let url = URL(string: urlStr),
                               let scheme = url.scheme?.lowercased(),
                               ["http", "https"].contains(scheme) {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #elseif os(macOS)
                                NSWorkspace.shared.open(url)
                                #endif
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                    .font(.system(size: 10))
                                Text(action.label ?? "Open Link")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(.indigo)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.indigo.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Results Block (full-width)

/// Shows the latest scan result and saved results list.
struct ResultsBlock: View {
    let tool: LocalToolDefinition
    let toolColor: Color
    @Binding var savedResults: [ScanResult]
    let env: AppEnvironment
    
    @State private var showHistoryExpanded = false
    @Binding var editingResult: ScanResult?
    @Binding var showEditSheet: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Processing indicator
            if env.vision.isProcessing {
                processingView
            }
            
            // Latest result
            if let result = env.vision.lastResult, result.toolID == tool.toolID, !env.vision.isProcessing {
                latestResultCard(result)
            }
            
            // Saved results
            if !savedResults.isEmpty {
                savedResultsSection
            }
        }
    }
    
    private var processingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: toolColor))
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning with Gemma 4 Vision")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(env.vision.status.isEmpty ? "Analyzing…" : env.vision.status)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(toolColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func latestResultCard(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Validation header with confidence badge
            HStack {
                Image(systemName: result.isValidated ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isValidated ? .green : .orange)
                Text(result.isValidated ? "Data Verified" : "Review Required")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(result.isValidated ? .green : .orange)
                
                Spacer()
                
                // Confidence badge
                if let confidence = result.confidence {
                    confidenceBadge(confidence)
                }
            }
            
            
            // Missing fields warning
            let emptyFields = result.richFields.filter { $0.value.isEmpty }.map { $0.key }
            if !emptyFields.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("\(emptyFields.count) field\(emptyFields.count > 1 ? "s" : "") could not be extracted")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            Divider()
            
            // Fields (Table Block)
            if !result.sortedKeys.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(result.sortedKeys.enumerated()), id: \.element) { index, key in
                        if let fv = result.richFields[key] {
                            HStack(alignment: .top, spacing: 16) {
                                // Key column
                                Text(key)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                    .padding(.top, 2)
                                
                                Divider()
                                
                                // Value column
                                if fv.isList {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(fv.asList.enumerated()), id: \.offset) { _, item in
                                            HStack(alignment: .top, spacing: 6) {
                                                Circle()
                                                    .fill(toolColor)
                                                    .frame(width: 5, height: 5)
                                                    .offset(y: 7)
                                                Text(item)
                                                    .font(.system(size: 16, design: .rounded))
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(fv.flatString.isEmpty ? "—" : fv.flatString)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(fv.flatString.isEmpty ? .secondary : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(index % 2 == 0 ? Color.primary.opacity(0.04) : Color.clear)
                            
                            if index < result.sortedKeys.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .background(Color(UIColor.systemBackground).opacity(0.5))
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, -16)
                .padding(.vertical, 8)
            }
            
            // Script notes
            if let notes = result.scriptNotes, !notes.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "scroll.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 12))
                    Text(notes)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            // Validation notes
            if !result.validationNotes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(result.validationNotes)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    env.storage.save(result, to: tool.toolID)
                    savedResults.insert(result, at: 0)
                    env.vision.lastResult = nil
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [toolColor, toolColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    )
                }
                
                Button {
                    env.vision.lastResult = nil
                } label: {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Discard")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: (result.isValidated ? Color.green : Color.orange).opacity(0.15), radius: 10, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke((result.isValidated ? Color.green : Color.orange).opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Confidence Badge
    
    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color = confidence >= 0.8 ? .green : (confidence >= 0.5 ? .yellow : .red)
        let label = String(format: "%.0f%%", confidence * 100)
        
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 0.5))
        )
    }
    
    // MARK: - Recovery Banner
    
    
    private var savedResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) { showHistoryExpanded.toggle() }
            } label: {
                HStack {
                    Label("Saved Results", systemImage: "archivebox")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(savedResults.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: showHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if showHistoryExpanded {
                ForEach(Array(savedResults.enumerated()), id: \.element.id) { index, result in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(result.isValidated ? Color.green : Color.orange))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.primaryValue)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Text("\(result.richFields.count) fields · \(result.timestamp, style: .relative)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            editingResult = result
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            env.storage.delete(resultID: result.id, from: tool.toolID)
                            savedResults.removeAll { $0.id == result.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.red.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Response Block

/// Renders a text prompt response as a styled block (replaces chat bubbles).
struct ResponseBlock: View {
    let text: String
    let toolColor: Color
    let isUser: Bool
    var image: UIImage? = nil
    var imageURL: String? = nil
    
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
                if let image = image {
#if os(iOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
#else
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
#endif
                } else if let urlStr = imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 240, maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                        case .failure(_):
                            EmptyView()
                        case .empty:
                            ProgressView()
                                .frame(width: 240, height: 160)
                                .background(Color.primary.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(isUser ? .white : .primary)
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(isUser ? toolColor : Color.primary.opacity(0.06))
                        )
                        .contextMenu {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = text
                                #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                #endif
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
            
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Capability Block Shell

/// Shared wrapper providing consistent glassmorphic card appearance for all capability blocks.
struct CapabilityBlockShell<Content: View>: View {
    let capability: LocalToolDefinition.Capability
    let toolColor: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(capability.color.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: capability.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(capability.color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(capability.displayName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(capability.blockDescription)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Divider().opacity(0.3)
            
            // Content
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(capability.color.opacity(0.12), lineWidth: 0.5)
                )
        )
    }
}
