import Foundation
import Combine

/// Persistent JSON storage engine for tool data.
/// Each tool gets its own JSON file in the app's documents directory.
///
/// Storage layout:
/// ```
/// Documents/
///   tool_storage/
///     parcel_address.json
///     business_card.json
///     receipt.json
///     custom_inventory.json
///     ...
/// ```
///
/// Usage:
/// ```swift
/// let storage = ToolStorage.shared
/// storage.save(result, to: "parcel_address")
/// let results: [ScanResult] = storage.loadAll(from: "parcel_address")
/// ```
@MainActor
class ToolStorage: ObservableObject {
    static let shared = ToolStorage()
    
    /// Published so views can react to data changes.
    @Published var toolCatalog: [ToolInfo] = []
    @Published var totalResultCount: Int = 0
    
    var toolDefinitions: [LocalToolDefinition] {
        ToolRegistry.shared.allDefinitions
    }
    
    private let storageDirectoryName = "tool_storage"
    private let fileExtension = "json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        createStorageDirectoryIfNeeded()
        refreshCatalog()
    }
    
    // MARK: - Storage Directory
    
    private var storageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }
    
    private func createStorageDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            do {
                try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                print("🗂️ Created tool storage directory: \(storageDirectory.path)")
            } catch {
                print("🗂️ Failed to create storage directory: \(error)")
            }
        }
    }
    
    private func fileURL(for toolID: String) -> URL {
        let sanitized = normalizedToolID(for: toolID)
        return storageDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension(fileExtension)
    }
    
    func normalizedToolID(for toolID: String) -> String {
        toolID
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
    
    // MARK: - CRUD Operations
    
    /// Saves a single result to a tool's storage, appending to existing data.
    func save(_ result: ScanResult, to toolID: String) {
        let normalizedToolID = normalizedToolID(for: toolID)
        var storedResult = result
        storedResult.toolID = normalizedToolID
        var existing = loadAll(from: normalizedToolID)
        existing.append(storedResult)
        writeAll(existing, to: normalizedToolID)
    }
    
    /// Saves multiple results to a tool's storage, appending to existing data.
    func saveAll(_ results: [ScanResult], to toolID: String) {
        let normalizedToolID = normalizedToolID(for: toolID)
        var existing = loadAll(from: normalizedToolID)
        existing.append(contentsOf: results.map { result in
            var storedResult = result
            storedResult.toolID = normalizedToolID
            return storedResult
        })
        writeAll(existing, to: normalizedToolID)
    }
    
    /// Overwrites the entire storage for a tool with the given results.
    func replaceAll(_ results: [ScanResult], in toolID: String) {
        let normalizedToolID = normalizedToolID(for: toolID)
        writeAll(results.map { result in
            var storedResult = result
            storedResult.toolID = normalizedToolID
            return storedResult
        }, to: normalizedToolID)
    }
    
    /// Loads all results from a tool's storage.
    func loadAll(from toolID: String) -> [ScanResult] {
        let normalizedToolID = normalizedToolID(for: toolID)
        let url = fileURL(for: normalizedToolID)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let results = try decoder.decode([ScanResult].self, from: data)
            print("🗂️ Loaded \(results.count) results from \(normalizedToolID)")
            return results
        } catch {
            print("🗂️ Failed to load from \(normalizedToolID): \(error)")
            return []
        }
    }
    
    /// Returns the most recent persisted state for a tool. This is the local
    /// MCP-lite state handoff used to keep scan chains deterministic.
    func latestState(for toolID: String) -> [String: String] {
        loadAll(from: toolID)
            .sorted { $0.timestamp > $1.timestamp }
            .first(where: { !($0.state?.isEmpty ?? true) })?
            .state ?? [:]
    }
    
    /// Updates a single result in a tool's storage by ID.
    func update(_ result: ScanResult, in toolID: String) {
        var all = loadAll(from: toolID)
        if let idx = all.firstIndex(where: { $0.id == result.id }) {
            all[idx] = result
            writeAll(all, to: toolID)
        }
    }
    
    /// Deletes a single result from a tool's storage by ID.
    func delete(resultID: UUID, from toolID: String) {
        var all = loadAll(from: toolID)
        all.removeAll { $0.id == resultID }
        writeAll(all, to: toolID)
    }
    
    /// Deletes all data for a specific tool.
    func clearTool(_ toolID: String) {
        let url = fileURL(for: toolID)
        try? FileManager.default.removeItem(at: url)
        print("🗂️ Cleared tool storage: \(toolID)")
        refreshCatalog()
    }
    
    /// Deletes all tool storage.
    func clearAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == fileExtension {
                try? fm.removeItem(at: file)
            }
        }
        print("🗂️ Cleared all tool storage")
        refreshCatalog()
    }
    
    // MARK: - Tool Catalog
    
    /// Refreshes the catalog of all tools with stored data.
    func refreshCatalog() {
        let fm = FileManager.default
        var catalog: [ToolInfo] = []
        
        if let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
            for file in files where file.pathExtension == fileExtension {
                let toolID = file.deletingPathExtension().lastPathComponent
                let results = loadAll(from: toolID)
                let attributes = try? fm.attributesOfItem(atPath: file.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0
                let lastModified = attributes?[.modificationDate] as? Date ?? Date()
                
                catalog.append(ToolInfo(
                    id: toolID,
                    displayName: toolID.replacingOccurrences(of: "_", with: " ").capitalized,
                    resultCount: results.count,
                    fileSize: fileSize,
                    lastModified: lastModified
                ))
            }
        }
        
        toolCatalog = catalog.sorted { $0.lastModified > $1.lastModified }
        totalResultCount = catalog.reduce(0) { $0 + $1.resultCount }
    }
    
    /// Returns total storage size across all tools.
    var totalStorageSize: String {
        let totalBytes = toolCatalog.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    // MARK: - Private
    
    private func writeAll(_ results: [ScanResult], to toolID: String) {
        let url = fileURL(for: toolID)
        
        do {
            let data = try encoder.encode(results)
            try data.write(to: url, options: .atomic)
            print("🗂️ Saved \(results.count) results to \(toolID) (\(data.count) bytes)")
            refreshCatalog()
        } catch {
            print("🗂️ Failed to write to \(toolID): \(error)")
        }
    }
}

// MARK: - Tool Info

/// Metadata about a tool's stored data for catalog display.
struct ToolInfo: Identifiable {
    let id: String
    let displayName: String
    let resultCount: Int
    let fileSize: Int64
    let lastModified: Date
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
}
