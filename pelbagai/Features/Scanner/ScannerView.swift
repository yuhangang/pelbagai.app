import SwiftUI
import Combine
import PhotosUI
import CoreImage

#if canImport(UIKit)
import UIKit
#else
import AppKit
fileprivate typealias UIImage = NSImage
#endif

/// A general-purpose vision scanner that uses Gemma 4 to extract structured data from images.
/// Supports multiple scan templates (Parcel Address, Business Card, Receipt, Document, Custom)
/// and exports results to CSV for use in Excel, Numbers, or Google Sheets.
struct ScannerView: View {
    @StateObject private var viewModel: ScannerViewModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    
    init(initialToolID: String? = nil, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(environment: env, initialToolID: initialToolID))
    }
    
    var body: some View {
        ZStack {
            scannerBackground
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.isLoadingModel {
                            loadingModelView
                                .padding(.horizontal)
                        }
                        
                        if !viewModel.isLoadingModel {
                            templateSelector
                            scanInputArea
                                .padding(.horizontal)
                        }
                        
                        if let image = viewModel.capturedImage {
                            capturedImagePreview(image)
                                .padding(.horizontal)
                        }
                        
                        if viewModel.isProcessing {
                            processingIndicator
                                .padding(.horizontal)
                        }
                        
                        if let result = viewModel.lastResult, !viewModel.isProcessing {
                            extractedDataCard(result)
                                .padding(.horizontal)
                        }
                        
                        if !viewModel.scanResults.isEmpty {
                            batchListSection
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
                
                if !viewModel.scanResults.isEmpty {
                    exportBar
                }
            }
        }
        .navigationTitle("Vision Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !viewModel.scanResults.isEmpty {
                    Text("\(viewModel.scanResults.count) scanned")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(viewModel.selectedToolColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(viewModel.selectedToolColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isModelLoaded ? Color.green : (viewModel.isLoadingModel ? Color.orange : Color.red))
                        .frame(width: 6, height: 6)
                    Text(viewModel.isModelLoaded ? "Ready" : (viewModel.isLoadingModel ? "Loading" : "Offline"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(viewModel.isModelLoaded ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .task {
            viewModel.loadStoredResults()
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            Task { await viewModel.handlePhotoSelection(newItem) }
        }
        .onChange(of: viewModel.showCamera) { _, isPresented in
            if isPresented {
                Task { await viewModel.unloadModel() }
            }
        }
        .sheet(isPresented: $viewModel.showCamera) {
            CameraView(image: $viewModel.capturedImage)
        }
        .onChange(of: viewModel.capturedImage) { _, newImage in
            if let image = newImage {
                Task { await viewModel.processImage(image) }
            }
        }
        .sheet(isPresented: $viewModel.showEditSheet) {
            if let result = viewModel.editingResult {
                ScanResultEditSheet(result: result) { updated in
                    viewModel.updateResult(updated)
                    viewModel.showEditSheet = false
                }
            }
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            if let url = viewModel.exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $viewModel.showWebView, onDismiss: { viewModel.webViewURL = nil }) {
            if let url = viewModel.webViewURL {
                ScriptWebViewSheet(url: url)
            }
        }
    }
    
    @State private var animateGradient = false
    
    private var scannerBackground: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            Circle()
                .fill(viewModel.selectedToolColor.opacity(0.12))
                .frame(width: 350, height: 350)
                .blur(radius: 70)
                .offset(x: animateGradient ? 80 : -80, y: animateGradient ? -150 : -250)
            
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animateGradient ? -120 : 120, y: animateGradient ? 250 : 150)
        }
        .animation(.easeInOut(duration: 1.0), value: viewModel.selectedToolID)
    }
    
    private var templateSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan Mode")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(env.registry.allDefinitions) { definition in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.selectedToolID = definition.toolID
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: definition))
                                    .font(.system(size: 12))
                                Text(definition.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundColor(viewModel.selectedToolID == definition.toolID ? .white : .primary)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedToolID == definition.toolID
                                          ? AnyShapeStyle(color(for: definition))
                                          : AnyShapeStyle(Color.primary.opacity(0.06)))
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 16)
    }
    
    private var loadingModelView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            
            Text(viewModel.loadingText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding(.top, 20)
    }
    
    private var scanInputArea: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.selectedToolIcon)
                    .foregroundColor(viewModel.selectedToolColor)
                Text("Scan: \(viewModel.selectedTool.displayName)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Text("Take a photo or select from library")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button(action: {
                    viewModel.prepareAndShowCamera()
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                        Text("Camera")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [viewModel.selectedToolColor, viewModel.selectedToolColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .disabled(viewModel.isProcessing)
                
                PhotosPicker(
                    selection: $viewModel.selectedPhotoItem,
                    matching: .images
                ) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                        Text("Library")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .foregroundColor(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .disabled(viewModel.isProcessing)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.primary.opacity(0.08), radius: 15, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
    
    private func capturedImagePreview(_ image: UIImage) -> some View {
        VStack(spacing: 8) {
            Text("Captured Image")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var processingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: viewModel.selectedToolColor))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning with Gemma 4 Vision")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(viewModel.status)
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
                        .stroke(
                            LinearGradient(colors: [viewModel.selectedToolColor.opacity(0.5), viewModel.selectedToolColor.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func extractedDataCard(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isValidated ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.isValidated ? .green : .orange)
                Text(result.isValidated ? "Data Verified" : "Review Required")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(result.isValidated ? .green : .orange)
                
                Spacer()
                
                Text(result.template)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            
            Divider()
            
            if result.confidence != nil || result.followUp != nil {
                HStack(spacing: 8) {
                    if let confidence = result.confidence {
                        Label("\(Int((confidence * 100).rounded()))% confidence", systemImage: "gauge.medium")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(confidence >= 0.75 ? .green : .orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((confidence >= 0.75 ? Color.green : Color.orange).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    if let followUp = result.followUp {
                        Label("Follow-up: \(followUp.tool)", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            
            ForEach(result.sortedKeys, id: \.self) { key in
                if let fv = result.richFields[key] {
                    if fv.isList {
                        listDataField(key, fv.asList)
                    } else {
                        dataField(key, fv.flatString)
                    }
                }
            }
            
            if let script = result.scriptNotes, !script.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "scroll.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extraction Notes")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.cyan)
                        Text(script)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color.cyan.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            if !result.actions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.badge.checkmark")
                            .font(.system(size: 11))
                            .foregroundColor(.indigo)
                        Text("Actions")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.indigo)
                    }
                    
                    ForEach(result.actions) { action in
                        Button {
                            viewModel.openToolAction(action)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text(action.label ?? "Open Link")
                                    .lineLimit(1)
                                Spacer()
                                if action.requiresUserApproval {
                                    Image(systemName: "hand.tap")
                                        .font(.system(size: 11))
                                }
                            }
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.indigo)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.indigo.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.validatedURL(for: action) == nil)
                    }
                }
            }
            
            if let state = result.state, !state.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                        Text("State")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                    ForEach(state.keys.sorted(), id: \.self) { k in
                        HStack(spacing: 6) {
                            Text(k)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.purple.opacity(0.8))
                            Text("→")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(state[k] ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                    }
                }
                .padding(10)
                .background(Color.purple.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            if !result.validationNotes.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text(result.validationNotes)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.addToBatch(result)
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Batch")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(colors: [viewModel.selectedToolColor, viewModel.selectedToolColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                            )
                    )
                }
                
                Button(action: {
                    viewModel.discardResult()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
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
                        .stroke(
                            (result.isValidated ? Color.green : Color.orange).opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func dataField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(value.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func listDataField(_ label: String, _ items: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.selectedToolColor)
                            .frame(width: 4, height: 4)
                        Text(item)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var batchListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scanned Batch")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(viewModel.scanResults.count) items")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            ForEach(Array(viewModel.scanResults.enumerated()), id: \.element.id) { index, result in
                batchItemRow(result, index: index)
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
    
    private func batchItemRow(_ result: ScanResult, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(result.isValidated ? Color.green : Color.orange))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.primaryValue)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(result.template)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text("\(result.fields.filter { !$0.value.isEmpty }.count) fields")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                viewModel.editingResult = result
                viewModel.showEditSheet = true
            }) {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.primary.opacity(0.4))
            }
            
            Button(action: {
                viewModel.deleteResult(result)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    private var exportBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.scanResults.count) items ready")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                let validated = viewModel.scanResults.filter(\.isValidated).count
                Text("\(validated) verified, \(viewModel.scanResults.count - validated) need review")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: viewModel.exportBatch) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export CSV")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(colors: [viewModel.selectedToolColor, viewModel.selectedToolColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.primary.opacity(0.1), radius: 15, y: -5)
        )
    }
    
    private func color(for definition: LocalToolDefinition) -> Color {
        definition.uiColor
    }
    
    private func icon(for definition: LocalToolDefinition) -> String {
        definition.uiIcon
    }
}

// MARK: - Camera View (UIKit Bridge)

#if os(iOS)
// CameraView moved to its own file.
#endif

// MARK: - Share Sheet (UIKit Bridge)

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Edit Sheet

struct ScanResultEditSheet: View {
    @State var result: ScanResult
    let onSave: (ScanResult) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Extracted Fields") {
                    ForEach(result.sortedKeys, id: \.self) { key in
                        if let fv = result.richFields[key] {
                            if fv.isList {
                                // List field → edit as newline-separated text
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(key)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Label("List", systemImage: "list.bullet")
                                            .font(.system(size: 10))
                                            .foregroundColor(.cyan)
                                    }
                                    TextEditor(text: Binding(
                                        get: { fv.asList.joined(separator: "\n") },
                                        set: { text in
                                            let items = text
                                                .components(separatedBy: "\n")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                                .filter { !$0.isEmpty }
                                            result.richFields[key] = .list(items)
                                        }
                                    ))
                                    .frame(minHeight: 60)
                                    .font(.system(size: 13))
                                    Text("One item per line")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                HStack {
                                    Text(key)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                    
                                    TextField(key, text: Binding(
                                        get: { fv.flatString },
                                        set: { result.richFields[key] = .string($0) }
                                    ))
                                }
                            }
                        }
                    }
                }
                
                if let script = result.scriptNotes {
                    Section {
                        TextEditor(text: Binding(
                            get: { script },
                            set: { result.scriptNotes = $0.isEmpty ? nil : $0 }
                        ))
                        .frame(minHeight: 60)
                        .font(.system(size: 13))
                    } header: {
                        Label("Extraction Notes", systemImage: "scroll")
                    }
                }
                
                if let state = result.state, !state.isEmpty {
                    Section {
                        ForEach(state.keys.sorted(), id: \.self) { k in
                            HStack {
                                Text(k)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                                TextField(k, text: Binding(
                                    get: { result.state?[k] ?? "" },
                                    set: { result.state?[k] = $0 }
                                ))
                                .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    } header: {
                        Label("State Variables", systemImage: "memorychip")
                    }
                }
                
                Section("Validation") {
                    Toggle("Verified", isOn: $result.isValidated)
                    TextField("Notes", text: $result.validationNotes)
                }
            }
            .navigationTitle("Edit Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(result)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    let env = AppEnvironment()
    ScannerView(env: env)
        .environmentObject(env)
}

// MARK: - Tool Action Web View
// Shown only when a validated openURL action is selected.

#if canImport(UIKit)
import WebKit

struct ScriptWebView: UIViewRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("⚙️ ScriptWebView navigation error: \(error.localizedDescription)")
        }
    }
}

/// Wraps ScriptWebView in a NavigationStack with a dismiss button.
struct ScriptWebViewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScriptWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? "Web View")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif
