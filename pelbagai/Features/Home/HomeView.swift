import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct HomeView: View {
    @Binding var selectedItem: NavigationItem?
    @StateObject private var viewModel: HomeViewModel
    @FocusState private var isChatBarFocused: Bool
    @State private var showSkillsSheet = false
    @State private var showSkillImporter = false
    @State private var selectedCanvasApp: CanvasAppInfo? = nil
    
    init(selectedItem: Binding<NavigationItem?>, env: AppEnvironment) {
        self._selectedItem = selectedItem
        self._viewModel = StateObject(wrappedValue: HomeViewModel(environment: env))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection
                    statsSection
                    
                    canvasCreatorBanner
                    
                    skillsSection
                    
                    if !viewModel.canvasApps.isEmpty {
                        canvasAppsSection
                    }
                    
                    if !viewModel.defaultTools.isEmpty {
                        toolSection(title: "Default Tools", tools: viewModel.defaultTools)
                    }
                    
                    if !viewModel.customTools.isEmpty {
                        toolSection(title: "Custom Tools", tools: viewModel.customTools)
                    } else {
                        noCustomToolsPlaceholder
                    }
                    
                    recentChatsSection
                    Spacer(minLength: 120)
                }
                .padding(.bottom, 40)
            }
            
            VStack(spacing: 0) {
                if isChatBarFocused {
                    suggestionsOverlay
                }
                floatingChatBar
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isChatBarFocused)
        }
        .sheet(isPresented: $showSkillsSheet) {
            SkillsBrowserSheet(
                showSkillImporter: $showSkillImporter,
                onSkillSelected: { skill in
                    let id = viewModel.startNewChatForSkill()
                    selectedItem = .chat(id, initialPrompt: nil, initialSkill: skill)
                }
            )
            .environmentObject(viewModel.environment.skills)
        }
        .fullScreenCover(item: $selectedCanvasApp) { app in
            let htmlContent: String? = {
                if app.localPath.hasPrefix("bundle:") {
                    let resourceName = app.localPath.replacingOccurrences(of: "bundle:", with: "")
                    if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: "html") ??
                                       Bundle.main.url(forResource: resourceName, withExtension: "html", subdirectory: "CanvasExamples") {
                        return try? String(contentsOf: bundleURL, encoding: .utf8)
                    }
                } else {
                    if let documentsURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                        let fileURL = documentsURL.appendingPathComponent("Attachments").appendingPathComponent(app.localPath)
                        return try? String(contentsOf: fileURL, encoding: .utf8)
                    }
                }
                return nil
            }()
            
            if let html = htmlContent {
                CanvasFullscreenView(htmlContent: html, canvasId: app.id.uuidString)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Unable to load canvas HTML.")
                        .font(.headline)
                    Button("Dismiss") {
                        selectedCanvasApp = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
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
                    print("🧠 HomeView: Successfully imported skill: \(skill.name)")
                    
                    // Automatically open chat with the new skill
                    let id = viewModel.startNewChatForSkill()
                    selectedItem = .chat(id, initialPrompt: nil, initialSkill: skill)
                } else {
                    print("🧠 HomeView: Failed to parse skill from markdown")
                }
            } catch {
                print("🧠 HomeView: Failed to parse skill from markdown: \(error)")
            }
            
        case .failure(let error):
            print("🧠 HomeView: Skill import failed: \(error)")
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Pelbagai")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            
            Text("Your personal AI assistant, powered by Gemma 4.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
    
    private var floatingChatBar: some View {
        ChatInputView(
            textInput: $viewModel.chatSearchText,
            inputMode: $viewModel.chatInputMode,
            isRecording: false,
            isGenerating: viewModel.isGenerating,
            isLoadingModels: viewModel.isLoadingModels,
            isModelLoaded: viewModel.isModelLoaded,
            userDefinitionsCount: viewModel.userDefinitionsCount,
            activeSkill: nil,
            pendingImage: $viewModel.pendingImage,
            onMicTap: { }, onCameraTap: { }, onFileTap: {},
            onSend: {
                let id = viewModel.startNewQuickChat()
                isChatBarFocused = false
                selectedItem = .chat(id)
            },
            onSkillsTap: { }
        )
        .focused($isChatBarFocused)
        .padding(.bottom, 20)
        .padding(.top, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        )
    }
    
    private var suggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(viewModel.chatSearchText.isEmpty ? "Recent Conversations" : "Search Results")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isChatBarFocused = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.filteredSessions.isEmpty && !viewModel.chatSearchText.isEmpty {
                        Text("No matches found. Press enter to start a new chat.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    }
                    
                    ForEach(viewModel.filteredSessions.prefix(5)) { session in
                        Button(action: {
                            isChatBarFocused = false
                            selectedItem = .chat(session.id)
                        }) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.orange.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                    .overlay(Image(systemName: "bubble.left").foregroundColor(.orange))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text(session.createdAt, style: .relative)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical, 20)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: -5)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var statsSection: some View {
        HStack(spacing: 16) {
            Button(action: { selectedItem = .data }) {
                StatCard(title: "Scans", value: "\(viewModel.totalResultCount)", icon: "viewfinder", color: .orange)
            }
            .buttonStyle(.plain)
            
            Button(action: { selectedItem = .chats }) {
                StatCard(title: "Chats", value: "\(viewModel.recentSessions.count)", icon: "bubble.left.and.bubble.right.fill", color: .blue)
            }
            .buttonStyle(.plain)
            
            Button(action: { selectedItem = .data }) {
                StatCard(title: "Tools", value: "\(viewModel.allDefinitions.count)", icon: "hammer.fill", color: .purple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }
    
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { showSkillsSheet = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.purple)
                    
                    Text("Agent Skills")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("Browse All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Prioritize recent skills
                    let displaySkills = Array((viewModel.recentSkills + viewModel.availableSkills.filter { skill in
                        !viewModel.recentSkills.contains(where: { $0.name == skill.name })
                    }).prefix(10))
                    
                    ForEach(displaySkills) { skill in
                        Button {
                            let id = viewModel.startNewChatForSkill()
                            selectedItem = .chat(id, initialPrompt: nil, initialSkill: skill)
                        } label: {
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(color(for: skill.color).opacity(0.15))
                                    .frame(width: 48, height: 48)
                                    .overlay(Image(systemName: skill.icon).foregroundColor(color(for: skill.color)).font(.title2))
                                
                                VStack(spacing: 4) {
                                    Text(skill.displayName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    if viewModel.recentSkills.contains(where: { $0.name == skill.name }) {
                                        Text("Recent")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15).clipShape(Capsule()))
                                    } else {
                                        Text(skill.isBuiltIn ? "Built-in" : "Custom")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(width: 140, height: 140)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(color(for: skill.color).opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private func color(for name: String) -> Color {
        switch name.lowercased() {
        case "cyan": return .cyan
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        default: return .blue
        }
    }
    
    // MARK: - Canvas Section
    
    private var canvasAppsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.purple)
                
                Text("My Canvas Apps")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.canvasApps) { app in
                        canvasAppCard(for: app)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private func canvasAppCard(for app: CanvasAppInfo) -> some View {
        let colors = gradientColors(for: app.id)
        
        return ZStack(alignment: .topTrailing) {
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                selectedCanvasApp = app
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [colors.0.opacity(0.15), colors.1.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [colors.0, colors.1],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Spacer(minLength: 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text("Interactive")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                            
                            Text(app.timestamp, style: .relative)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(14)
                .frame(width: 160, height: 140, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [colors.0.opacity(0.2), colors.1.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            
            // Secondary button to route to original chat session
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                
                if app.sessionId == UUID(uuidString: "00000000-0000-0000-0000-000000000000")! {
                    let canvasSkill = viewModel.environment.skills.skill(byID: "canvas-app-builder")
                    let newSessionId = viewModel.startNewChatForSkill()
                    selectedItem = .chat(newSessionId, initialPrompt: "I want to modify the '\(app.title)' canvas app template. Please load it so we can iterate on it.", initialSkill: canvasSkill)
                } else {
                    selectedItem = .chat(app.sessionId)
                }
            }) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [colors.0, colors.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
    }
    
    private func gradientColors(for id: UUID) -> (Color, Color) {
        let hash = abs(id.hashValue)
        let pairs: [(Color, Color)] = [
            (.purple, .blue),
            (.pink, .orange),
            (.teal, .indigo),
            (.orange, .red),
            (.green, .teal),
            (.mint, .purple)
        ]
        return pairs[hash % pairs.count]
    }
    
    private func toolSection(title: String, tools: [LocalToolDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(tools) { tool in
                        NavigationLink(value: NavigationItem.scanner(tool.toolID)) {
                            ToolCard(tool: tool)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var noCustomToolsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Tools")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 24)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Define Your Own Tools")
                        .font(.headline)
                    Text("Add custom extraction schemas via the developer console.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .padding(20)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
            .padding(.horizontal, 24)
        }
    }
    
    private var recentChatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Chats")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("See All") {
                    selectedItem = .chats
                }
                .font(.subheadline)
                .foregroundColor(.orange)
            }
            .padding(.horizontal, 24)
            
            if viewModel.recentSessions.isEmpty {
                Text("No recent chats.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.recentSessions.prefix(3)) { session in
                        NavigationLink(value: NavigationItem.chat(session.id)) {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "bubble.left")
                                            .foregroundColor(.orange)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(session.createdAt, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var canvasCreatorBanner: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            selectedItem = .canvasCreator(UUID())
        }) {
            HStack(spacing: 16) {
                // Icon representation
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build AI Canvas App")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Interactive on-device HTML5 apps with automated verification.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.purple.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

struct ToolCard: View {
    let tool: LocalToolDefinition
    
    private var color: Color {
        tool.uiColor
    }
    
    private var icon: String {
        tool.uiIcon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(tool.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .top)
            }
        }
        .padding(16)
        .frame(width: 160)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}
