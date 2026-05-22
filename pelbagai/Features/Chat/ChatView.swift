import SwiftUI
import AVFAudio

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers


/// The main chat interface for the Pelbagai app.
/// Combines WhisperKit voice input with Gemma E2B AI responses in a chat bubble layout.
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var mainViewModel: MainViewModel
    
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = true
    
    @State private var animateGradient = false
    @State private var isRotating = false
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var newSessionTitle = ""
    @State private var showFilePicker = false
    @State private var showSkillsSheet = false
    @State private var showSkillImporter = false
    
    init(sessionId: UUID, initialPrompt: String? = nil, initialSkill: Skill? = nil, env: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(sessionId: sessionId, environment: env, initialPrompt: initialPrompt, initialSkill: initialSkill))
    }
    
    var body: some View {
        ZStack {
            spatialBackground
            
            VStack(spacing: 0) {
                chatScrollView
                
                VStack(spacing: 12) {
                    ChatInputView(
                        textInput: $viewModel.textInput,
                        inputMode: $viewModel.inputMode,
                        isRecording: viewModel.isRecording,
                        isGenerating: viewModel.isGenerating,
                        isLoadingModels: viewModel.isLoadingModels,
                        isModelLoaded: viewModel.isModelLoaded,
                        userDefinitionsCount: viewModel.userDefinitionsCount,
                        activeSkill: viewModel.activeSkill,
                        pendingImage: $viewModel.pendingImage,
                        onMicTap: viewModel.handleMicTap,
                        onCameraTap: { viewModel.showCamera = true },
                        onFileTap: { showFilePicker = true },
                        onSend: viewModel.sendTypedMessage,
                        onSkillsTap: { showSkillsSheet = true }
                    )
                }
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            
            if viewModel.isLoadingModels {
                ZStack {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    modelLoadingOverlay
                }
                .zIndex(1)
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        isRotating = true
                    }
                }
            } else if !viewModel.isModelLoaded && !env.gemma.selectedModel.isDownloaded {
                ZStack {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    downloadPromptOverlay
                }
                .zIndex(1)
            }
            
            if let request = viewModel.clarificationRequest {
                clarificationOverlay(request)
            }
        }
#if os(iOS)
        .sheet(isPresented: $viewModel.showCamera) {
            CameraView(image: $viewModel.capturedImage)
        }
#endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImportedFile(result: result)
        }

        .onChange(of: viewModel.capturedImage) { _, newImage in
            if let image = newImage {
                viewModel.capturedImage = nil
                viewModel.pendingImage = ImageInputPreparer.preparedForModel(image)
            }
        }
        .navigationTitle("Pelbagai")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                dynamicIslandStatus
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: viewModel.retryLastAgentResponse) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(viewModel.isGenerating || viewModel.messages.isEmpty ? .primary.opacity(0.3) : .cyan)
                }
                .disabled(viewModel.isGenerating || viewModel.messages.isEmpty)

                Button(action: {
                    ttsEnabled.toggle()
                    if !ttsEnabled {
                        env.speech.stop()
                    }
                }) {
                    Image(systemName: ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(ttsEnabled ? .cyan : .primary.opacity(0.4))
                }

                Button {
                    newSessionTitle = viewModel.messages.first?.content.prefix(30).description ?? ""
                    showRenameAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.cyan)
                }
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
        .alert("Rename Chat", isPresented: $showRenameAlert) {
            TextField("Chat Title", text: $newSessionTitle)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                viewModel.renameSession(to: newSessionTitle)
            }
        }
        .alert("Large Download", isPresented: $viewModel.showDownloadWarning) {
            Button("Download Anyway") {
                viewModel.confirmDownload()
            }
            Button("Cancel", role: .cancel) {
                // If they cancel, they stay in Chat but model won't load
            }
        } message: {
            Text("You are currently on a cellular connection or hotspot. Downloading the AI model requires several gigabytes of data. Do you want to proceed?")
        }
        .confirmationDialog("Delete Chat?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                mainViewModel.deleteSession(withId: viewModel.sessionId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This conversation will be permanently removed.")
        }
        .task {
            viewModel.loadMessages()
            await viewModel.loadAllModels()
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var spatialBackground: some View {
        ZStack {
#if os(iOS)
            Color(UIColor.systemBackground).ignoresSafeArea()
#else
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
#endif
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animateGradient ? 100 : -50, y: animateGradient ? -100 : -200)
            
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: animateGradient ? -150 : 150, y: animateGradient ? 200 : 300)
        }
    }
    
    private var dynamicIslandStatus: some View {
        HStack(spacing: 6) {
            if viewModel.isLoadingModels {
                statusBadge(color: .orange, text: "Loading Models", pulsing: true)
            } else if env.speech.isSpeaking {
                statusBadge(color: .cyan, text: "Speaking", pulsing: true)
            } else if viewModel.isRecording {
                statusBadge(color: .red, text: "Listening (Gemma)", pulsing: true)
            } else if viewModel.isGenerating {
                statusBadge(color: .purple, text: "Thinking", pulsing: true)
            } else {
                statusBadge(color: .green, text: "Ready", pulsing: false)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black)
        .clipShape(Capsule())
    }
    
    private func statusBadge(color: Color, text: String, pulsing: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
                .opacity(!pulsing || animateGradient ? 1.0 : 0.4)
                .animation(pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: animateGradient)
            Text(text)
                .font(.system(size: 11, weight: pulsing ? .bold : .medium, design: .rounded))
                .foregroundColor(color.opacity(pulsing ? 1.0 : 0.8))
        }
    }
    
    private var downloadPromptOverlay: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            VStack(spacing: 8) {
                Text("Model Download Required")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                
                Text("The \(env.gemma.selectedModel.displayName) model is not yet on this device. You need to download it to start chatting.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                viewModel.confirmDownload()
            } label: {
                Text("Download Now")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 20)
            
            Text("Size: ~2GB")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(32)
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 40)
    }
    
    private var modelLoadingOverlay: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(Angle(degrees: isRotating ? 360 : 0))
            }
            
            VStack(spacing: 8) {
                Text(viewModel.loadingStatusText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                
                Text("Initializing Gemma 4 on-device AI...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .cornerRadius(32)
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        .transition(.opacity.combined(with: .scale))
    }
    
    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    Spacer().frame(height: 20)
                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        emptyStateView
                    }
                    
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    
                    if viewModel.isGenerating {
                        inlineStreamingView
                            .id("streaming")
                    }
                    
                    if let pending = viewModel.pendingToolCall {
                        ToolConfirmationBlock(
                            pending: pending,
                            onConfirm: { args in
                                viewModel.confirmPendingToolCall(arguments: args)
                            },
                            onCancel: {
                                viewModel.cancelPendingToolCall()
                            }
                        )
                        .id("toolConfirmation")
                        .padding(.vertical, 8)
                    }
                    
                    Spacer().frame(height: 20)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.response) { _, _ in
                if viewModel.isGenerating {
                    scrollToBottom(proxy: proxy, animate: false)
                }
            }
            .onChange(of: viewModel.isGenerating) { _, isGen in
                if isGen {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: viewModel.pendingToolCall) { _, pending in
                if pending != nil {
                    withAnimation {
                        proxy.scrollTo("toolConfirmation", anchor: .bottom)
                    }
                }
            }
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                scrollToBottom(proxy: proxy)
            }
#endif
        }
        .sheet(isPresented: $showSkillsSheet) {
            SkillsBrowserSheet(
                showSkillImporter: $showSkillImporter,
                onSkillSelected: { skill in
                    viewModel.activeSkill = skill
                }
            )
            .environmentObject(viewModel.environment.skills)
        }
        .fileImporter(
            isPresented: $showSkillImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleSkillImport(result: result)
        }
    }
    
    private func handleSkillImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                if let skill = Skill.parse(from: markdown) {
                    viewModel.registerSkill(skill)
                    viewModel.activeSkill = skill
                    print("🧠 ChatView: Successfully imported and activated skill: \(skill.name)")
                } else {
                    print("🧠 ChatView: Failed to parse skill from markdown")
                }
            } catch {
                print("🧠 ChatView: Failed to parse skill from markdown: \(error)")
            }
            
        case .failure(let error):
            print("🧠 ChatView: Skill import failed: \(error)")
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animate: Bool = true) {
        if animate {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 100)
            
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "waveform.circle")
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.8), .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.9))
                
                Text("Powered by Whisper & \(env.gemma.selectedModel.displayName)")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(0.5))
            }
        }
    }
    
    private var inlineStreamingView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                if !viewModel.response.isEmpty {
                    MarkdownContentView(text: viewModel.response)
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
                                        .stroke(
                                            Color.primary.opacity(0.1),
                                            lineWidth: 0.5
                                        )
                                )
                        )
                } else if !viewModel.status.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(viewModel.status)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    )
                } else {
                    TypingIndicator()
                }
            }
            Spacer(minLength: 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func clarificationOverlay(_ request: ClarificationRequest) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.clarificationRequest = nil
                }
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Text("Clarification Needed")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                
                Text(request.question)
                    .font(.system(size: 16, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(.horizontal)
                
                if let options = request.options, !options.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                viewModel.handleClarificationChoice(option)
                            } label: {
                                Text(option)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                            )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Button {
                        viewModel.clarificationRequest = nil
                    } label: {
                        Text("I'll provide more info")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary)
                            )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
            )
            .padding(.horizontal, 40)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 1.1).combined(with: .opacity)
            ))
        }
        .zIndex(10)
    }

}

private enum ToolDefinitionError: LocalizedError {
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The model did not return a valid JSON object."
        }
    }
}

// MARK: - Chat Bubble Component

struct ChatBubble: View {
    let message: ChatMessage
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Generic Attachments
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { attachment in
                        FileAttachmentView(attachment: attachment)
                            .padding(.bottom, 4)
                    }
                } else if message.content == "[Audio Message]" {
                    Label("Voice message", systemImage: "waveform")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.primary.opacity(0.1))
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )
                } else {
                    MarkdownContentView(text: message.content)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(message.role == .user ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(
                                            Color.primary.opacity(0.1),
                                            lineWidth: 0.5
                                        )
                                )
                                .shadow(color: message.role == .user ? Color.primary.opacity(0.05) : Color.clear, radius: 10, x: 0, y: 5)
                        )
                }
                
                if let imageData = message.imageData {
                    AsyncDataImageView(imageData: imageData)
                        .frame(maxWidth: 240, maxHeight: 320)
                        .cornerRadius(16)
                        .padding(.top, 4)
                        .shadow(radius: 5)
                }
            }
            
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

struct FileAttachmentView: View {
    let attachment: ChatAttachment
    
    private var iconName: String {
        switch attachment.fileType.lowercased() {
        case "pdf": return "doc.fill"
        case "txt", "text": return "doc.text.fill"
        case "doc", "docx": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch attachment.fileType.lowercased() {
        case "pdf": return .red
        case "txt", "text": return .blue
        default: return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 20))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(attachment.fileType.uppercased() + " Document")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        )
        .frame(maxWidth: 240)
    }
}

struct AsyncDataImageView: View {
    let imageData: Data
    @State private var uiImage: UIImage?
    
    var body: some View {
        Group {
            if let uiImage = uiImage {
#if os(iOS)
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
#else
                Image(nsImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
#endif
            } else {
                Color.primary.opacity(0.1)
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .task {
            // Load and decode image in the background to prevent main thread lag
            if let image = await Task.detached(priority: .userInitiated, operation: {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: imageData) {
                    // Force decoding on background thread
                    UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
                    uiImage.draw(at: .zero)
                    UIGraphicsEndImageContext()
                    return uiImage
                }
                return nil
                #else
                return UIImage(data: imageData)
                #endif
            }).value {
                await MainActor.run {
                    self.uiImage = image
                }
            }
        }
    }
}

#Preview {
    let env = AppEnvironment()
    ChatView(sessionId: UUID(), env: env)
        .environmentObject(env)
        .environmentObject(MainViewModel(environment: env))
}
