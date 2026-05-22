import SwiftUI
import PhotosUI
import CoreImage
#if canImport(Charts)
import Charts
#endif

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum WorkbenchTab: String, CaseIterable {
    case workspace = "Workspace"
    case data = "Data"
    
    var icon: String {
        switch self {
        case .workspace: return "sparkles.rectangle.stack.fill"
        case .data:      return "tray.full.fill"
        }
    }
}

/// A consolidated workbench that uses tabs to organize tool interactions.
struct WorkbenchView: View {
    @StateObject private var viewModel: WorkbenchViewModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @FocusState private var isChatBarFocused: Bool
    @State private var selectedTab: WorkbenchTab = .workspace
    
    init(toolID: String, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: WorkbenchViewModel(toolID: toolID, environment: env))
    }
    
    var body: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 0) {
                tabContent
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
    private var tabContent: some View {
        VStack(spacing: 0) {
            // Modern iOS Pill Tab Bar
            HStack(spacing: 0) {
                ForEach(WorkbenchTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab == .data ? "\(tab.rawValue) (\(viewModel.savedResults.count))" : tab.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            ZStack {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(viewModel.toolColor)
                                        .matchedGeometryEffect(id: "tab_pill", in: tabNamespace)
                                }
                            }
                        )
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                    }
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Tab Switcher
            ZStack {
                switch selectedTab {
                case .workspace:
                    workspaceView
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                               removal: .move(edge: .leading).combined(with: .opacity)))
                case .data:
                    libraryView
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                               removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    @Namespace private var tabNamespace
    
    @ViewBuilder
    private var workspaceView: some View {
        if viewModel.tool.capabilities.contains(.chatbot) {
            chatbotView
        } else {
            standardWorkspaceView
        }
    }
    
    @ViewBuilder
    private var standardWorkspaceView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    toolHeader
                    
                    if viewModel.isLoadingModels {
                        loadingView
                            .padding(.horizontal)
                    }
                    
                    // THE STAGE: Integrated Capture + Results
                    VStack(spacing: 16) {
                        HStack {
                            Text("Active Stage")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                            if viewModel.lastResult != nil {
                                Button {
                                    withAnimation { viewModel.lastResult = nil }
                                } label: {
                                    Text("Clear")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(viewModel.toolColor)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        
                        if viewModel.lastResult == nil && !env.vision.isProcessing {
                            emptyStagePlaceholder
                        } else {
                            ResultsBlock(
                                tool: viewModel.tool,
                                toolColor: viewModel.toolColor,
                                savedResults: $viewModel.savedResults,
                                env: env,
                                editingResult: $viewModel.editingResult,
                                showEditSheet: $viewModel.showEditSheet
                            )
                        }
                    }
                    .padding(.horizontal)

                    workflowReportBlock()
                        .padding(.horizontal)
                    
                    htmlViewBlock()
                        .padding(.horizontal)
                    
                    promptResponseList()
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
            .onChange(of: viewModel.lastResult?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
    
    @ViewBuilder
    private var chatbotView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    toolHeader
                    
                    if viewModel.isLoadingModels {
                        loadingView
                            .padding(.horizontal)
                    }
                    
                    let visible = viewModel.promptResponses.filter { !$0.isHiddenContext }
                    if visible.isEmpty {
                        chatbotOnboardingView
                    } else {
                        ForEach(visible) { response in
                            ChatbotResponseBlock(
                                response: response,
                                toolColor: viewModel.toolColor,
                                viewModel: viewModel
                            )
                            .padding(.horizontal)
                        }
                    }
                    
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
    
    @ViewBuilder
    private var chatbotOnboardingView: some View {
        VStack(spacing: 24) {
            Image(systemName: viewModel.tool.icon ?? "globe.americas.fill")
                .font(.system(size: 48))
                .foregroundColor(viewModel.toolColor.opacity(0.8))
                .padding(.top, 30)
            
            VStack(spacing: 6) {
                Text("Search \(viewModel.tool.displayName)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(viewModel.tool.description)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            if let suggestions = viewModel.tool.suggestedPrompts, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested searches:")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            viewModel.textInput = suggestion
                            viewModel.sendTextInput()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundColor(viewModel.toolColor)
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
        }
    }
    
    @ViewBuilder
    private var libraryView: some View {
        WorkbenchLibraryView(viewModel: viewModel)
    }
    
    private var emptyStagePlaceholder: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(viewModel.toolColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "viewfinder")
                    .font(.system(size: 32))
                    .foregroundColor(viewModel.toolColor.opacity(0.5))
            }
            
            VStack(spacing: 4) {
                Text("Ready to Extract")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Use the camera or chat to start processing.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                quickCaptureButton(icon: "camera.fill", label: "Camera") {
                    viewModel.showCamera = true
                }
                
                quickCaptureButton(icon: "photo.fill", label: "Photos") {
                    // Handled by PhotosPicker overlay or direct trigger if we refactor it
                }
                .overlay {
                    PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func quickCaptureButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
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
                    TextField(viewModel.tool.capabilities.contains(.chatbot) ? "Search topic or ask a question…" : "Ask about this tool or paste data…", text: $viewModel.textInput)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .focused($isChatBarFocused) // Note: Renamed from isInputFocused for consistency
                        .disabled(viewModel.isLoadingModels)
                        .onSubmit {
                            isChatBarFocused = false
                            viewModel.sendTextInput()
                        }
                    
                    if !viewModel.textInput.isEmpty || viewModel.pendingImage != nil {
                        Button(action: {
                            isChatBarFocused = false
                            viewModel.sendTextInput()
                        }) {
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
    var extractedTopic: String? = nil
    let timestamp = Date()
}

// MARK: - Chatbot Response Block

struct ChatbotResponseBlock: View {
    let response: ToolPromptResponse
    let toolColor: Color
    @ObservedObject var viewModel: WorkbenchViewModel
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack {
            if response.isUser {
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
                        Text(response.text)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(toolColor)
                            )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let topic = response.extractedTopic, !topic.isEmpty {
                        // Premium Glassmorphic Card for Chatbot Article Result!
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
                                
                                Text(response.text)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineSpacing(4)
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                HStack(spacing: 12) {
                                    if viewModel.tool.urlTemplate != nil {
                                        // Open Article Button
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
                                    
                                    // Bookmark Button
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
                    } else {
                        // Standard Assistant text response
                        Text(response.text)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }
    
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
