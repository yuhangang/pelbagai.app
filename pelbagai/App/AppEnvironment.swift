import SwiftUI
import Combine

/// A container for all core services in the application.
/// Injected into the view hierarchy via `.environmentObject()`.
@MainActor
class AppEnvironment: ObservableObject {
    lazy var gemma: GemmaManager = .shared
    lazy var mlx: MLXModelManager = {
        mlxHasInitialized = true
        return .shared
    }()
    lazy var speech: SpeechService = .shared
    lazy var registry: ToolRegistry = .shared
    lazy var skills: SkillRegistry = .shared
    lazy var database: DatabaseManager = .shared
    lazy var storage: ToolStorage = .shared
    lazy var tools: ToolManager = .shared
    lazy var plugins: NativePluginRegistry = .shared
    lazy var capabilitySettings: SystemCapabilitySettings = .shared
    lazy var agent: AgentOrchestrator = .shared
    lazy var vision: VisionManager = .shared
    lazy var whisper: WhisperManager = .shared
    lazy var workflows: WorkflowExecutor = .shared
    
    private var mlxHasInitialized = false
    
    init() {}
    
    func handleBackground() {
        guard mlxHasInitialized else { return }
        mlx.handleBackground()
    }
    
    func handleForeground() {
        guard mlxHasInitialized else { return }
        mlx.handleForeground()
    }
    
    func unloadAllModels() async {
        print("🧠 [AppEnvironment] Offloading all models before settings update")
        await gemma.unloadModel()
        await vision.unloadModel()
        await whisper.unloadModel()
        await mlx.unloadModel()
    }
}
