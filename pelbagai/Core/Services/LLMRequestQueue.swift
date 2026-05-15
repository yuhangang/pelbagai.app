import Foundation

/// A central serial queue for all LLM processing tasks.
/// Ensures that multiple generations (text, audio, image) do not overlap,
/// which prevents MLX out-of-memory or race condition crashes.
actor LLMRequestQueue {
    static let shared = LLMRequestQueue()
    
    private var isRunning = false
    private var queue: [(id: UUID, operation: @Sendable () async -> Void)] = []
    
    private init() {}
    
    /// Enqueues an asynchronous operation to be run serially.
    func enqueue(_ operation: @Sendable @escaping () async -> Void) {
        let id = UUID()
        print("🕒 [LLMQueue] Enqueuing task \(id.uuidString.prefix(8))")
        queue.append((id: id, operation: operation))
        processQueue()
    }
    
    private func processQueue() {
        guard !isRunning else { 
            print("🕒 [LLMQueue] Queue is busy, task waiting in line (count: \(queue.count))")
            return 
        }
        guard !queue.isEmpty else { return }
        
        let (id, operation) = queue.removeFirst()
        isRunning = true
        
        print("🚀 [LLMQueue] Starting task \(id.uuidString.prefix(8))")
        
        Task {
            await operation()
            await self.finishOperation(id: id)
        }
    }
    
    private func finishOperation(id: UUID) {
        print("✅ [LLMQueue] Finished task \(id.uuidString.prefix(8))")
        isRunning = false
        processQueue()
    }
    
    /// Clears any pending operations in the queue.
    func clear() {
        print("🧹 [LLMQueue] Clearing all \(queue.count) pending tasks")
        queue.removeAll()
        isRunning = false
    }
}
