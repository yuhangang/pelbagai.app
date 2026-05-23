import SwiftUI
import PhotosUI
import CoreImage
import UniformTypeIdentifiers
#if canImport(Charts)
import Charts
#endif

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A consolidated workbench with a chat-like UI for tool interactions.
struct WorkbenchView: View {
    @StateObject private var viewModel: WorkbenchViewModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @FocusState private var isChatBarFocused: Bool
    @State private var inputMode: ChatInputMode = .chat
    @State private var showLibrarySheet = false
    @State private var showFilePicker = false
    
    init(toolID: String, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: WorkbenchViewModel(toolID: toolID, environment: env))
    }
    
    var body: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 0) {
                workspaceChatView
                
                ChatInputView(
                    textInput: $viewModel.textInput,
                    inputMode: $inputMode,
                    isRecording: viewModel.isRecording,
                    isGenerating: viewModel.isProcessing || viewModel.isProcessingText,
                    isLoadingModels: viewModel.isLoadingModels,
                    isModelLoaded: viewModel.isModelLoaded,
                    userDefinitionsCount: 0,
                    activeSkill: nil,
                    pendingImage: $viewModel.pendingImage,
                    onMicTap: { viewModel.handleMicTap() },
                    onCameraTap: { viewModel.showCamera = true },
                    onFileTap: { showFilePicker = true },
                    onSend: { viewModel.sendTextInput() },
                    onSkillsTap: { },
                    showModeSelector: false,
                    showSkillsSelector: false
                )
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(viewModel.tool.displayName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            toolToolbarContent()
        }
        .sheet(isPresented: $showLibrarySheet) {
            NavigationStack {
                WorkbenchLibraryView(viewModel: viewModel)
                    .navigationTitle("Data (\(viewModel.savedResults.count))")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLibrarySheet = false }
                        }
                    }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImportedFile(result: result)
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
        .fullScreenCover(isPresented: $viewModel.showCamera) {
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
    // MARK: - Unified Workspace Chat View


    @ViewBuilder
    private var workspaceChatView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    let visible = viewModel.promptResponses.filter { !$0.isHiddenContext }

                    if visible.isEmpty {
                        compactOnboardingHeader
                    }

                    if viewModel.isLoadingModels {
                        loadingView
                            .padding(.horizontal)
                    }

                    ForEach(visible) { response in
                        WorkspaceChatBubble(
                            response: response,
                            toolColor: viewModel.toolColor,
                            viewModel: viewModel,
                            env: env,
                            onEditResult: { result in
                                viewModel.editingResult = result
                                viewModel.showEditSheet = true
                            },
                            onSaveResult: { result in
                                viewModel.saveResult(result)
                            },
                            onDiscardResult: { result in
                                viewModel.lastResult = nil
                                env.vision.lastResult = nil
                            },
                            onConfirmOption: { option in
                                viewModel.handleConfirmChoice(option)
                            }
                        )
                        .padding(.horizontal)
                    }

                    htmlViewBlock()
                        .padding(.horizontal)

                    processingIndicator()
                        .padding(.horizontal)

                    Color.clear.frame(height: 20).id("bottom")
                }
                .padding(.bottom, 40)
            }
            .onChange(of: viewModel.promptResponses.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Compact Onboarding Header

    private var compactOnboardingHeader: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            ZStack {
                Circle()
                    .fill(viewModel.toolColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: viewModel.toolIcon)
                    .font(.system(size: 30))
                    .foregroundStyle(viewModel.toolColor)
            }

            VStack(spacing: 6) {
                Text(viewModel.tool.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(viewModel.tool.description)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Capability pills
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

            // Quick actions for scanner tools
            if viewModel.tool.capabilities.contains(.scanImage) {
                HStack(spacing: 16) {
                    onboardingQuickButton(icon: "camera.fill", label: "Camera") {
                        viewModel.showCamera = true
                    }
                    onboardingQuickButton(icon: "photo.fill", label: "Photos") { }
                        .overlay {
                            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                }
            }

            // Suggested prompts for chatbot tools
            if let suggestions = viewModel.tool.suggestedPrompts, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try asking:")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)

                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.textInput = suggestion
                            viewModel.sendTextInput()
                        } label: {
                            HStack {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.toolColor)
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }

            Spacer().frame(height: 20)
        }
    }

    private func onboardingQuickButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(viewModel.toolColor)
            .frame(width: 80, height: 80)
            .background(viewModel.toolColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func workflowReportBlock() -> some View {
        if viewModel.tool.workflow != nil || viewModel.workflowArtifact != nil || viewModel.allDefinitions.contains(where: { definition in
            definition.workflow?.triggerSourceToolIDs.contains(viewModel.toolID) == true
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(viewModel.toolColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workflow")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(viewModel.workflowStatus.isEmpty ? "Configured tool workflow" : viewModel.workflowStatus)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await viewModel.runConfiguredWorkflow(reason: "Manual workflow run")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isWorkflowRunning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chart.bar.doc.horizontal")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text("Report")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.toolColor)
                        .clipShape(Capsule())
                    }
                    .disabled(viewModel.isWorkflowRunning)
                }

                if let artifact = viewModel.workflowArtifact {
                    artifactSummary(artifact)
                    artifactCharts(artifact)
                } else if let run = viewModel.activeWorkflowRun {
                    workflowEventList(run)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func artifactSummary(_ artifact: WorkflowArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(artifact.summary)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.primary.opacity(0.82))
                .lineSpacing(3)

            HStack(spacing: 10) {
                ForEach(artifact.metrics.prefix(3)) { metric in
                    metricPill(title: metric.title, value: metric.value)
                }
            }
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func artifactCharts(_ artifact: WorkflowArtifact) -> some View {
#if canImport(Charts)
        VStack(spacing: 14) {
            ForEach(artifact.charts) { chart in
                VStack(alignment: .leading, spacing: 8) {
                    Text(chart.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Chart(chart.points) { point in
                        switch chart.kind {
                        case .bar:
                            BarMark(
                                x: .value("Value", point.value),
                                y: .value("Label", point.label)
                            )
                            .foregroundStyle(viewModel.toolColor.gradient)
                        case .line:
                            LineMark(
                                x: .value("Label", point.label),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(viewModel.toolColor)
                            PointMark(
                                x: .value("Label", point.label),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(viewModel.toolColor)
                        }
                    }
                    .frame(height: chart.kind == .bar ? 180 : 160)
                }
            }
        }
#else
        EmptyView()
#endif
    }

    private func workflowEventList(_ run: WorkflowRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(run.events.suffix(4)) { event in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(viewModel.toolColor.opacity(0.8))
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text(event.detail)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // promptResponseList removed — all items now rendered inline in workspaceChatView

    @ToolbarContentBuilder
    private func toolToolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showLibrarySheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 13))
                    if !viewModel.savedResults.isEmpty {
                        Text("\(viewModel.savedResults.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }
            }
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
        if viewModel.isProcessingText || viewModel.isProcessing {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: viewModel.toolColor))
                Text(viewModel.isProcessing ? (!env.vision.status.isEmpty ? env.vision.status : "Analyzing image…") : "Processing…")
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
            viewModel.pendingImage = ImageInputPreparer.preparedForModel(image)
        }
    }

    @State private var animateGradient = false
    
    private var toolSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Switch Tool")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.allDefinitions) { definition in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.switchToTool(definition.toolID)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: definition.uiIcon)
                                    .font(.system(size: 12))
                                Text(definition.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundColor(viewModel.toolID == definition.toolID ? .white : .primary)
                            .background(
                                Capsule()
                                    .fill(viewModel.toolID == definition.toolID
                                          ? AnyShapeStyle(definition.uiColor)
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
    
    // toolHeader removed — replaced by compactOnboardingHeader in workspaceChatView
    
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
    
    // toolPromptBar removed — replaced by ChatInputView

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

/// Represents a chat item in the workbench timeline.
struct ToolPromptResponse: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    var image: UIImage? = nil
    var imageURL: String? = nil
    var isHiddenContext: Bool = false
    var contextData: [String: String]? = nil
    var extractedTopic: String? = nil
    let timestamp = Date()

    /// Inline scan result card rendered in the chat timeline.
    var scanResult: ScanResult? = nil

    /// Inline confirm/choice request rendered in the chat timeline.
    var confirmRequest: ConfirmChatRequest? = nil
}

// MARK: - Workspace Chat Bubble

/// Renders a single item in the unified workbench chat timeline.
/// Dispatches to different visual presentations based on the response payload.
struct WorkspaceChatBubble: View {
    let response: ToolPromptResponse
    let toolColor: Color
    @ObservedObject var viewModel: WorkbenchViewModel
    let env: AppEnvironment
    var onEditResult: ((ScanResult) -> Void)?
    var onSaveResult: ((ScanResult) -> Void)?
    var onDiscardResult: ((ScanResult) -> Void)?
    var onConfirmOption: ((ConfirmChatOption) -> Void)?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if response.isUser {
            userBubble
        } else if let scanResult = response.scanResult {
            InlineScanResultCard(
                result: scanResult,
                toolColor: toolColor,
                onEdit: { onEditResult?(scanResult) },
                onSave: { onSaveResult?(scanResult) },
                onDiscard: { onDiscardResult?(scanResult) }
            )
        } else if let confirmRequest = response.confirmRequest {
            ConfirmChatItem(
                request: confirmRequest,
                onSelect: { option in onConfirmOption?(option) },
                onDismiss: nil
            )
        } else if let topic = response.extractedTopic, !topic.isEmpty {
            articleCard(topic: topic)
        } else {
            assistantBubble
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 8) {
                if let image = response.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                }

                if !response.text.isEmpty {
                    MarkdownContentView(text: response.text)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(toolColor.opacity(0.15))
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(toolColor.opacity(0.2), lineWidth: 0.5)
                                )
                                .shadow(color: toolColor.opacity(0.08), radius: 10, x: 0, y: 5)
                        )
                        .contextMenu {
                            Button {
#if os(iOS)
                                UIPasteboard.general.string = response.text
#elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(response.text, forType: .string)
#endif
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownContentView(text: response.text)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                    .contextMenu {
                        Button {
#if os(iOS)
                            UIPasteboard.general.string = response.text
#elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(response.text, forType: .string)
#endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }
            Spacer(minLength: 40)
        }
    }

    // MARK: - Article Card

    @ViewBuilder
    private func articleCard(topic: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL = response.imageURL, let url = URL(string: imageURL), !imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 180)
                                .clipped()
                        case .failure:
                            EmptyView()
                        case .empty:
                            ProgressView()
                                .frame(height: 180)
                                .frame(maxWidth: .infinity)
                                .background(Color.primary.opacity(0.03))
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: viewModel.tool.icon ?? "globe.americas.fill")
                            .foregroundColor(toolColor)
                            .font(.system(size: 12))
                        Text("\(viewModel.tool.displayName) Article")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Text(topic)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    MarkdownContentView(text: response.text)
                        .foregroundColor(.primary.opacity(0.8))
                        .padding(.bottom, 4)

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 12) {
                        if viewModel.tool.urlTemplate != nil {
                            Button {
                                openArticleLink(for: topic)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "safari")
                                    Text("Open Link")
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(toolColor)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(toolColor.opacity(0.1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        let bookmarked = isBookmarked(topic: topic)
                        Button {
                            toggleBookmark(topic: topic, summary: response.text, imageURL: response.imageURL)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: bookmarked ? "star.fill" : "star")
                                Text(bookmarked ? "Bookmarked" : "Bookmark")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(bookmarked ? .orange : .secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(bookmarked ? Color.orange.opacity(0.1) : Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
            .contextMenu {
                Button {
#if os(iOS)
                    UIPasteboard.general.string = response.text
#elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(response.text, forType: .string)
#endif
                } label: {
                    Label("Copy Article Text", systemImage: "doc.on.doc")
                }
            }
            Spacer(minLength: 20)
        }
    }

    // MARK: - Helpers

    private func openArticleLink(for topic: String) {
        if let template = viewModel.tool.urlTemplate {
            let escaped = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? topic
            let urlString = template.replacingOccurrences(of: "{topic}", with: escaped)
            if let url = URL(string: urlString) {
                openURL(url)
            }
        }
    }

    private func isBookmarked(topic: String) -> Bool {
        viewModel.savedResults.contains { result in
            (result.richFields["topic"]?.flatString ?? result.primaryValue).lowercased() == topic.lowercased()
        }
    }

    private func toggleBookmark(topic: String, summary: String, imageURL: String?) {
        if isBookmarked(topic: topic) {
            if let result = viewModel.savedResults.first(where: { ($0.richFields["topic"]?.flatString ?? $0.primaryValue).lowercased() == topic.lowercased() }) {
                viewModel.deleteResult(result)
            }
        } else {
            let escaped = topic.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? topic
            let targetURLString = viewModel.tool.urlTemplate?.replacingOccurrences(of: "{topic}", with: escaped) ?? ""

            let result = ScanResult(
                toolID: viewModel.toolID,
                template: viewModel.toolID,
                richFields: [
                    "topic": .string(topic),
                    "summary": .string(summary),
                    "imageURL": .string(imageURL ?? ""),
                    "url": .string(targetURLString)
                ],
                isValidated: true,
                timestamp: Date()
            )
            viewModel.saveResult(result)
        }
    }
}

// MARK: - Inline Scan Result Card

/// Premium glassmorphic card for displaying extraction results inline in the chat timeline.
struct InlineScanResultCard: View {
    let result: ScanResult
    let toolColor: Color
    var onEdit: (() -> Void)?
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?

    @State private var isSaved = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accent bar
            LinearGradient(
                colors: [toolColor.opacity(0.8), toolColor.opacity(0.3)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 3)

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(toolColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(toolColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Extraction Result")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        HStack(spacing: 6) {
                            if let confidence = result.confidence {
                                Text("\(Int(confidence * 100))% confidence")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(confidence > 0.7 ? .green : .orange)
                            }
                            Text(result.timestamp, style: .relative)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: result.isValidated ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundColor(result.isValidated ? .green : .orange)
                }

                // Fields grid
                let fieldKeys = result.sortedKeys.prefix(6)
                if !fieldKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(fieldKeys), id: \.self) { key in
                            if let fv = result.richFields[key], !fv.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(key.capitalized)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .frame(width: 90, alignment: .leading)

                                    if fv.isList {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(fv.asList.prefix(4), id: \.self) { item in
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(toolColor.opacity(0.4))
                                                        .frame(width: 4, height: 4)
                                                    Text(item)
                                                        .font(.system(size: 12, design: .rounded))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            if fv.asList.count > 4 {
                                                Text("+\(fv.asList.count - 4) more")
                                                    .font(.system(size: 10, design: .rounded))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    } else {
                                        Text(fv.flatString)
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }

                        if result.richFields.count > 6 {
                            Text("+\(result.richFields.count - 6) more fields")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                }

                // Action buttons
                HStack(spacing: 10) {
                    if isSaved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Saved")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isSaved = true
                            }
                            onSave?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(toolColor)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(toolColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onEdit?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if !isSaved {
                        Button {
                            onDiscard?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                Text("Discard")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color.red.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: toolColor.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(toolColor.opacity(0.12), lineWidth: 0.5)
        )
        .scaleEffect(appeared ? 1.0 : 0.96)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}

