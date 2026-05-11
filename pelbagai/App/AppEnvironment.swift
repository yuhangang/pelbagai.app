import SwiftUI
import Combine

/// A container for all core services in the application.
/// Injected into the view hierarchy via `.environmentObject()`.
@MainActor
class AppEnvironment: ObservableObject {
    let gemma: GemmaManager
    let mlx: MLXModelManager
    let speech: SpeechService
    let registry: ToolRegistry
    let database: DatabaseManager
    let storage: ToolStorage
    let tools: ToolManager
    let vision: VisionManager
    let whisper: WhisperManager
    
    init(
        gemma: GemmaManager = .shared,
        mlx: MLXModelManager = .shared,
        speech: SpeechService = .shared,
        registry: ToolRegistry = .shared,
        database: DatabaseManager = .shared,
        storage: ToolStorage = .shared,
        tools: ToolManager = .shared,
        vision: VisionManager = .shared,
        whisper: WhisperManager = .shared
    ) {
        self.gemma = gemma
        self.mlx = mlx
        self.speech = speech
        self.registry = registry
        self.database = database
        self.storage = storage
        self.tools = tools
        self.vision = vision
        self.whisper = whisper
    }
}
