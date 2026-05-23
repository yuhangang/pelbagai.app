import SwiftUI
import Combine

enum CreatorState: String, Codable {
    case welcome
    case gatheringStyle
    case gatheringFeatures
    case thinking
    case generating
    case validating
    case testing
    case completed
}

@MainActor
class CanvasThinkingChatViewModel: ObservableObject {
    let sessionId: UUID
    let initialPrompt: String?
    let environment: AppEnvironment
    
    @Published var state: CreatorState = .welcome
    @Published var appDescription: String = ""
    @Published var selectedStyle: String = ""
    @Published var selectedCapabilities: [String] = []
    
    @Published var architecturePlan: String = ""
    @Published var generatedHtml: String = ""
    @Published var testAssertions: [CanvasHTMLValidator.TestAssertion] = []
    
    // Model state mirroring
    @Published var isGenerating: Bool = false
    @Published var isLoadingModels: Bool = false
    @Published var loadingStatusText: String = ""
    @Published var isModelLoaded: Bool = false
    @Published var responseText: String = ""
    @Published var statusText: String = ""
    
    @Published var localFileURL: URL? = nil
    @Published var showModelDownloadPrompt: Bool = false
    @Published var currentTestIndex: Int = 0
    @Published var isTestingInProgress: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init(sessionId: UUID, initialPrompt: String? = nil, env: AppEnvironment) {
        self.sessionId = sessionId
        self.initialPrompt = initialPrompt
        self.environment = env
        
        if let initialPrompt = initialPrompt, !initialPrompt.isEmpty {
            self.appDescription = initialPrompt
            self.state = .gatheringStyle
        }
        
        setupBindings()
    }
    
    private func setupBindings() {
        environment.gemma.$isGenerating
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isGenerating = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$response
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.responseText = $0 }
            .store(in: &cancellables)
            
        environment.gemma.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.statusText = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoadingModels = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.loadingStatusText = $0 }
            .store(in: &cancellables)
            
        // Setup initial model loaded state
        self.isModelLoaded = environment.gemma.isModelLoaded
        
        Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isModelLoaded = self.environment.gemma.isModelLoaded
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func submitDescription(_ desc: String) {
        guard !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appDescription = desc
        withAnimation(.spring()) {
            state = .gatheringStyle
        }
    }
    
    func selectStyle(_ style: String) {
        selectedStyle = style
        withAnimation(.spring()) {
            state = .gatheringFeatures
        }
    }
    
    func toggleCapability(_ cap: String) {
        if selectedCapabilities.contains(cap) {
            selectedCapabilities.removeAll { $0 == cap }
        } else {
            selectedCapabilities.append(cap)
        }
    }
    
    func confirmCapabilities() {
        withAnimation(.spring()) {
            state = .thinking
        }
        
        generateArchitecturePlan()
        
        // Short delay to allow user to admire the glowing architectural card before generation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            Task {
                await self.startAppGeneration()
            }
        }
    }
    
    private func generateArchitecturePlan() {
        let styleDesc: String
        switch selectedStyle.lowercased() {
        case "neon cyber":
            styleDesc = "High-contrast dark layout with glowing neon drop shadows, custom glass borders, and electric linear accents."
        case "minimal apple":
            styleDesc = "Sleek iOS desktop environment styling, rounded edges, generous paddings, clean SF Pro rounded typography, and micro-scale transformations."
        case "retro terminal":
            styleDesc = "Monochromatic green-phosphor text layout, blocky visual inputs, dotted container borders, and retro type-in styles."
        case "soft glass":
            styleDesc = "Sophisticated backdrop-filtered blur sheets, translucent fill colors, subtle outer strokes, and smooth gradient layers."
        default:
            styleDesc = "Harmonious curated HSL color parameters adapting gracefully to light and dark color schemes."
        }
        
        let interfaceHooks = selectedCapabilities.map { cap -> String in
            switch cap.lowercased() {
            case "local storage":
                return "- **Durable Database**: window.pelbagai.storage.save/load integrations."
            case "camera/photos":
                return "- **On-device Media**: Camera picker utilizing window.pelbagai.camera/photos."
            case "haptics/alerts":
                return "- **Tactile feedback**: physical ui.haptic alerts and ui.toast notifications."
            case "share sheets":
                return "- **Share controller**: native system sharing layout integration."
            default:
                return "- **Bridge capability**: \(cap) interface setup."
            }
        }.joined(separator: "\n")
        
        architecturePlan = """
        # Architecture Plan & Design Specification
        
        ## 🎨 Aesthetic Theme
        - **Style Scheme**: \(selectedStyle)
        - **Visual Parameters**: \(styleDesc)
        
        ## 🧩 System Modules
        - **Document Layout**: Responsive Single Page App (SPA) structure.
        - **Viewport Target**: Fitted mobile scale boundaries (`width=device-width, initial-scale=1.0`).
        
        ## 🔌 Native API Bridge Integrations
        \(interfaceHooks.isEmpty ? "*No special capabilities requested. Standard bridge setup only.*" : interfaceHooks)
        
        ## 🧪 Automated Assertions Verification Suite
        - Static HTML layout completeness check.
        - Device scale and responsiveness bounds validation.
        - Adaptive colors dark mode matching test.
        - Hook execution and bridge interface compliance check.
        """
    }
    
    private func startAppGeneration() async {
        // Enforce model download check
        guard environment.gemma.selectedModel.isDownloaded else {
            showModelDownloadPrompt = true
            return
        }
        
        // Ensure model is loaded
        if !environment.gemma.isModelLoaded {
            state = .thinking
            statusText = "Loading resident weights..."
            let loaded = await environment.gemma.loadModel()
            if !loaded {
                responseText = "Failed to load Gemma resident model weights. Please check available memory in Settings."
                state = .completed
                return
            }
        }
        
        withAnimation(.spring()) {
            state = .generating
        }
        
        let systemPrompt = CanvasPromptBuilder.buildSystemPrompt()
        let localDesc = self.appDescription
        let localStyle = self.selectedStyle
        let localCaps = self.selectedCapabilities
        
        let userPrompt = """
        Please build a complete interactive HTML5 micro-application matching these specifications:
        - **App Description**: \(localDesc)
        - **Design Theme Aesthetic**: \(localStyle) (Apply this thoroughly using dynamic CSS and colors)
        - **Native Device Bridge Capabilities**: \(localCaps.joined(separator: ", "))
        
        Ensure you hook into the injected pelbagaiReady event and integrate native APIs seamlessly. Write ONLY the single complete HTML file inside a single ```html code block.
        """
        
        await LLMRequestQueue.shared.enqueue { [weak self] in
            guard let self = self else { return }
            
            let textOutput = await self.environment.gemma.generateText(
                messages: [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ],
                statusText: "Synthesizing App Components..."
            )
            
            await MainActor.run {
                self.generatedHtml = textOutput
                self.transitionToValidation()
            }
        }
    }
    
    private func transitionToValidation() {
        withAnimation(.spring()) {
            state = .validating
        }
        
        // Parse HTML
        guard let extracted = CanvasParser.extractHTML(from: generatedHtml) else {
            let failedAssertion = CanvasHTMLValidator.TestAssertion(
                name: "Standard HTML5 Structure",
                description: "Verifies correct DOCTYPE, html wrapper, head and body tag completeness.",
                passed: false,
                feedback: "Failed to locate standard ```html code block in the generated model response."
            )
            testAssertions = [failedAssertion]
            state = .completed
            return
        }
        
        // Run static analysis validator
        let assertions = CanvasHTMLValidator.runSuite(html: extracted, requestedCapabilities: selectedCapabilities)
        testAssertions = assertions
        
        // Transition to dynamic test sequence
        withAnimation(.spring()) {
            state = .testing
            isTestingInProgress = true
            currentTestIndex = 0
        }
        
        runDynamicTestAnimationSequence(extracted: extracted)
    }
    
    private func runDynamicTestAnimationSequence(extracted: String) {
        guard currentTestIndex < testAssertions.count else {
            finalizeCanvasApp(extracted: extracted)
            return
        }
        
        // Animate each test completing with a cool dynamic delay to wow the user
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring()) {
                self.currentTestIndex += 1
                self.runDynamicTestAnimationSequence(extracted: extracted)
            }
        }
    }
    
    private func finalizeCanvasApp(extracted: String) {
        isTestingInProgress = false
        
        // Check if all test assertions passed
        let allPassed = testAssertions.allSatisfy { $0.passed }
        
        if allPassed {
            do {
                // Determine clean application filename
                var appName = "canvas_app"
                if let titleRange = extracted.range(of: "<title>", options: .caseInsensitive),
                   let endTitleRange = extracted.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<extracted.endIndex) {
                    let title = extracted[titleRange.upperBound..<endTitleRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        appName = title.replacingOccurrences(of: " ", with: "_").lowercased()
                    }
                }
                
                // Save attachment to Storage
                let filename = try saveHTMLAttachmentToStorage(htmlContent: extracted)
                let localPath = filename
                
                // Save database record
                let attachment = ChatAttachment(
                    id: UUID(),
                    filename: "\(appName).html",
                    fileType: "html",
                    localPath: localPath,
                    extractedText: "[AI Canvas Micro-App]"
                )
                
                let attachmentsData = try JSONEncoder().encode([attachment])
                
                // Construct assistant final message
                let assistantMessage = ChatMessage(
                    id: UUID(),
                    sessionId: sessionId,
                    role: .assistant,
                    content: "I've successfully created, validated, and verified your fully-interactive **\(appName)** application. All automated viewport scaling, bridge connectivity, and aesthetic compliance checks passed beautifully. Enjoy your app!",
                    imageData: nil,
                    attachmentsData: attachmentsData,
                    timestamp: Date()
                )
                
                // Check if session has a title or needs title updates
                let existingMessages = environment.database.getMessages(for: sessionId)
                if existingMessages.isEmpty {
                    // Update session title to the app name
                    let formattedTitle = appName.replacingOccurrences(of: "_", with: " ").capitalized
                    environment.database.updateSessionTitle(id: sessionId, newTitle: formattedTitle)
                }
                
                // Insert messages to keep history complete
                let userMessage = ChatMessage(
                    id: UUID(),
                    sessionId: sessionId,
                    role: .user,
                    content: "Build \(appDescription) using style \(selectedStyle).",
                    imageData: nil,
                    attachmentsData: nil,
                    timestamp: Date().addingTimeInterval(-10)
                )
                
                environment.database.addMessage(userMessage)
                environment.database.addMessage(assistantMessage)
                
                // Dispatch notification to refresh Home lists
                NotificationCenter.default.post(name: .sessionUpdated, object: nil)
                
                // Setup local URL for instant interaction
                let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                self.localFileURL = docs.appendingPathComponent("Attachments").appendingPathComponent(localPath)
                
            } catch {
                print("⚠️ [CanvasCreatorVM] Save failure: \(error)")
            }
        }
        
        withAnimation(.spring()) {
            state = .completed
        }
    }
    
    private func saveHTMLAttachmentToStorage(htmlContent: String) throws -> String {
        let fileManager = FileManager.default
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let attachmentsDirectory = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        
        if !fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
        
        let uniqueName = "\(UUID().uuidString).html"
        let destinationURL = attachmentsDirectory.appendingPathComponent(uniqueName)
        
        try htmlContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        return uniqueName
    }
    
    func retryDownloadAndLoad() {
        showModelDownloadPrompt = false
        Task {
            isLoadingModels = true
            loadingStatusText = "Downloading weights..."
            await environment.gemma.downloadModel(environment.gemma.selectedModel)
            isLoadingModels = false
            await startAppGeneration()
        }
    }
}
