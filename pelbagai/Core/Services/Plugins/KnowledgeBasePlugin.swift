import Foundation
import NaturalLanguage
import Accelerate

struct KnowledgeChunk: Codable {
    let chunk_id: String
    let page: Int
    let text: String
    let images: [String]
}

actor VectorStore {
    static let shared = VectorStore()
    
    private var chunks: [KnowledgeChunk] = []
    private var embeddings: [[Double]] = []
    private var isLoaded = false
    
    func loadIfNeeded() {
        guard !isLoaded else { return }
        
        guard let url = Bundle.main.url(forResource: "survival_knowledge", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loadedChunks = try? JSONDecoder().decode([KnowledgeChunk].self, from: data) else {
            print("Failed to load survival_knowledge.json")
            return
        }
        
        guard let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english) else {
            print("Failed to load NLEmbedding")
            return
        }
        
        self.chunks = loadedChunks
        
        // In a real app, we would cache these to disk. For this prototype, we compute on the fly
        // if not cached, or we just compute them once per session. Computing 500 chunks is fast enough.
        var computedEmbeddings: [[Double]] = []
        for chunk in loadedChunks {
            if let vector = embeddingModel.vector(for: chunk.text) {
                computedEmbeddings.append(vector)
            } else {
                // fallback empty vector
                computedEmbeddings.append(Array(repeating: 0.0, count: 512))
            }
        }
        
        self.embeddings = computedEmbeddings
        self.isLoaded = true
    }
    
    func search(query: String, topK: Int = 3) -> [(chunk: KnowledgeChunk, score: Double)] {
        loadIfNeeded()
        
        guard let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english),
              let queryVector = embeddingModel.vector(for: query) else {
            return []
        }
        
        var scores: [(index: Int, score: Double)] = []
        
        for (i, vector) in embeddings.enumerated() {
            let score = cosineSimilarity(queryVector, vector)
            scores.append((i, score))
        }
        
        scores.sort { $0.score > $1.score }
        
        return scores.prefix(topK).map { (chunks[$0.index], $0.score) }
    }
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 0 else { return 0.0 }
        var dotProduct: Double = 0.0
        var normA: Double = 0.0
        var normB: Double = 0.0
        
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesqD(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesqD(b, 1, &normB, vDSP_Length(b.count))
        
        if normA == 0.0 || normB == 0.0 { return 0.0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
}

/// A native plugin that implements semantic search across local knowledge.
/// Bridges the 'knowledge_base' chat tool and 'vector_search' capability.
@MainActor
struct KnowledgeBasePlugin: NativePlugin {
    let id = "knowledge_base"
    let displayName = "Knowledge Base"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "vector_search",
                displayName: "Vector Search",
                description: "Perform semantic search across vectorized local documents.",
                argumentSchema: ["query": "The search query or question"],
                requiresUserApproval: false
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "knowledge_base",
                displayName: "Knowledge Base",
                description: "Use to find reliable survival tips, technical guides, or historical facts from local knowledge base.",
                pluginID: id,
                capabilityID: "vector_search"
            )
        ]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "vector_search":
            return try await performSearch(query: arguments["query"] ?? "")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }

    private func performSearch(query: String) async throws -> NativePluginResult {
        let results = await VectorStore.shared.search(query: query)
        
        if results.isEmpty {
            return NativePluginResult(summary: "No specific match found in the knowledge base for '\(query)'. Advice: stay calm and stay put if you are lost.")
        }
        
        var summaryText = "Found in Knowledge Base:\n\n"
        
        for (chunk, _) in results {
            summaryText += "[Page \(chunk.page)]\n\(chunk.text)\n\n"
        }
        
        return NativePluginResult(summary: summaryText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}