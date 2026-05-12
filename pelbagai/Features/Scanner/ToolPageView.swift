import SwiftUI
import PhotosUI
import CoreImage

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A block-based tool page that renders capabilities as interactive GUI blocks.
struct ToolPageView: View {
    @StateObject private var viewModel: ToolPageViewModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isChatBarFocused: Bool
    
    init(toolID: String, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: ToolPageViewModel(toolID: toolID, environment: env))
    }
    
    var body: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 0) {
                toolMainContent()
                toolPromptBar()
            }
        }
        .navigationTitle(viewModel.tool.displayName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            toolToolbarContent()
        }
        .task {
            viewModel.resetSessionState()
            viewModel.loadStoredResults()
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            Task { await viewModel.handlePhotoSelection(newItem) }
        }
        .onChange(of: viewModel.capturedImage) { _, newImage in
            handleCapturedImage(newImage)
        }
#if os(iOS)
        .sheet(isPresented: $viewModel.showCamera) {
            CameraView(image: $viewModel.capturedImage)
        }
#endif
        .sheet(isPresented: $viewModel.showEditSheet) {
            editResultSheet()
        }
#if os(iOS)
        .sheet(isPresented: $viewModel.showExportSheet) {
            exportShareSheet()
        }
#endif
    }
    
    @ViewBuilder
    private func toolMainContent() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                toolScrollContent()
            }
            .onChange(of: viewModel.promptResponses.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.lastResult?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func toolScrollContent() -> some View {
        VStack(spacing: 16) {
            toolHeader
            
            if viewModel.isLoadingModels {
                loadingView
                    .padding(.horizontal)
            }
            
            CapabilityGridView(
                tool: viewModel.tool,
                toolColor: viewModel.toolColor,
                showCamera: $viewModel.showCamera,
                selectedPhotoItem: $viewModel.selectedPhotoItem,
                savedResults: $viewModel.savedResults,
                showExportSheet: $viewModel.showExportSheet,
                exportFileURL: $viewModel.exportFileURL,
                env: env
            )
            .padding(.horizontal)
            
            htmlViewBlock()
                .padding(.horizontal)
            promptResponseList()
                .padding(.horizontal)
            
            if viewModel.tool.capabilities.contains(.exportCSV) {
                ResultsBlock(
                    tool: viewModel.tool,
                    toolColor: viewModel.toolColor,
                    savedResults: $viewModel.savedResults,
                    env: env,
                    editingResult: $viewModel.editingResult,
                    showEditSheet: $viewModel.showEditSheet
                )
                .padding(.horizontal)
            }
            processingIndicator()
                .padding(.horizontal)
            
            Color.clear.frame(height: 20).id("bottom")
        }
        .padding(.bottom, 100)
    }

    @ViewBuilder
    private func promptResponseList() -> some View {
        let visible = viewModel.promptResponses.filter { !$0.isHiddenContext }
        ForEach(visible) { response in
            ResponseBlock(
                text: response.text,
                toolColor: viewModel.toolColor,
                isUser: response.isUser,
                image: response.image,
                imageURL: response.imageURL
            )
        }
    }

    @ToolbarContentBuilder
    private func toolToolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !viewModel.savedResults.isEmpty || viewModel.lastResult != nil {
                Button {
                    viewModel.exportCurrentResults()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                }
            }
            modelStatusView()
        }
    }

    @ViewBuilder
    private func editResultSheet() -> some View {
        if let result = viewModel.editingResult {
            ScanResultEditSheet(result: result) { updated in
                viewModel.updateResult(updated)
                viewModel.showEditSheet = false
            }
        }
    }

    @ViewBuilder
    private func exportShareSheet() -> some View {
#if os(iOS)
        if let url = viewModel.exportFileURL {
            ShareSheet(activityItems: [url])
        }
#endif
    }
    
    @ViewBuilder
    private func htmlViewBlock() -> some View {
        if viewModel.tool.capabilities.contains(.htmlView),
           let html = viewModel.tool.htmlTemplate, !html.isEmpty {
            #if canImport(UIKit)
            ToolWebViewBlock(
                htmlContent: html,
                toolColor: viewModel.toolColor,
                onMessage: handleWebViewMessage
            )
            #endif
        } else if viewModel.tool.actions?.values.contains(where: { $0.effect == .run_js }) == true {
            #if canImport(UIKit)
            ToolWebView(
                htmlContent: viewModel.tool.htmlTemplate ?? "",
                toolColor: viewModel.toolColor,
                onMessage: handleWebViewMessage
            )
            .frame(width: 0, height: 0)
            .opacity(0)
            #endif
        }
    }

    @ViewBuilder
    private func processingIndicator() -> some View {
        if viewModel.isProcessingText {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: viewModel.toolColor))
                Text("Processing…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    @ViewBuilder
    private func modelStatusView() -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(modelStatusColor())
                .frame(width: 6, height: 6)
            Text(modelStatusText())
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(modelStatusColor())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private func modelStatusColor() -> Color {
        if viewModel.isModelLoaded {
            return .green
        } else if viewModel.isLoadingModels {
            return .orange
        } else {
            return .red
        }
    }
    
    private func modelStatusText() -> String {
        if viewModel.isModelLoaded {
            return "Ready"
        } else if viewModel.isLoadingModels {
            return "Loading"
        } else {
            return "Offline"
        }
    }
    
    private func handleCapturedImage(_ newImage: UIImage?) {
        if let image = newImage {
            viewModel.capturedImage = nil
            viewModel.pendingImage = image
        }
    }

    @State private var animateGradient = false
    
    private var backgroundView: some View {
        ZStack {
#if os(iOS)
            Color(UIColor.systemBackground).ignoresSafeArea()
#else
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
#endif
            Circle()
                .fill(viewModel.toolColor.opacity(0.12))
                .frame(width: 350, height: 350)
                .blur(radius: 70)
                .offset(x: animateGradient ? 80 : -80, y: animateGradient ? -150 : -250)
            
            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: animateGradient ? -100 : 100, y: animateGradient ? 200 : 120)
        }
    }
    
    private var toolHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(viewModel.toolColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: viewModel.toolIcon)
                    .font(.system(size: 28))
                    .foregroundColor(viewModel.toolColor)
            }
            
            Text(viewModel.tool.description)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            if !viewModel.tool.capabilities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.tool.capabilities, id: \.rawValue) { cap in
                            HStack(spacing: 4) {
                                Image(systemName: cap.icon)
                                    .font(.system(size: 8, weight: .bold))
                                Text(cap.displayName)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(cap.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(cap.color.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: viewModel.toolColor))
            Text(viewModel.status)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
    
    @ViewBuilder
    private func toolPromptBar() -> some View {
        VStack(spacing: 0) {
            // Pending Image Preview
            if let image = viewModel.pendingImage {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.toolColor.opacity(0.2), lineWidth: 1))
                        
                        Button {
                            withAnimation {
                                viewModel.pendingImage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .background(Circle().fill(Color.white))
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                HStack {
                    TextField("Ask about this tool or paste data…", text: $viewModel.textInput)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .focused($isChatBarFocused) // Note: Renamed from isInputFocused for consistency
                        .disabled(viewModel.isLoadingModels)
                        .onSubmit { viewModel.sendTextInput() }
                    
                    if !viewModel.textInput.isEmpty || viewModel.pendingImage != nil {
                        Button(action: viewModel.sendTextInput) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                .frame(width: 30, height: 30)
                                .background(viewModel.toolColor)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 6)
                        .disabled(viewModel.isProcessing || viewModel.isProcessingText)
                    }
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                
                Button {
                    viewModel.showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.toolColor.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.isLoadingModels || viewModel.isProcessingText)
                
                PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.toolColor.opacity(0.8))
                        .frame(width: 36, height: 36)
                }
                .disabled(viewModel.isLoadingModels || viewModel.isProcessingText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .shadow(color: Color.primary.opacity(0.08), radius: 10, y: -3)
            )
        }
    }
    
    #if canImport(UIKit)
    private func handleWebViewMessage(_ message: ToolWebViewMessage) {
        if let actionDef = viewModel.tool.actions?[message.action] {
            viewModel.executeDynamicAction(actionDef, payload: message.payload)
            return
        }
        viewModel.handleStandardWebViewAction(message)
    }
    #endif
}

// MARK: - Prompt Response Model

/// Represents a text prompt response in the block canvas (replaces ToolChatMessage).
struct ToolPromptResponse: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var image: UIImage? = nil
    var imageURL: String? = nil
    var isHiddenContext: Bool = false
    var contextData: [String: String]? = nil
    let timestamp = Date()
}
