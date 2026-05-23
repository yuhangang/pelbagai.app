import Foundation

/// Thread-safe actor for persistent per-canvas key-value storage.
/// Saves each canvas's state to `Documents/canvas_storage/<canvasId>.json`.
actor CanvasStorageManager {
    static let shared = CanvasStorageManager()
    
    private let storageDirectoryName = "canvas_storage"
    private let fileExtension = "json"
    
    private init() {
        createStorageDirectoryIfNeeded()
    }
    
    private var storageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }
    
    private func createStorageDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            do {
                try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                print("📦 Created canvas storage directory: \(storageDirectory.path)")
            } catch {
                print("📦 Failed to create canvas storage directory: \(error)")
            }
        }
    }
    
    private func fileURL(for canvasId: String) -> URL {
        // Sanitize canvasId to be safe for filenames
        let sanitized = canvasId.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        return storageDirectory.appendingPathComponent(sanitized).appendingPathExtension(fileExtension)
    }
    
    /// Load all key-values for a specific canvas ID.
    private func loadStorage(for canvasId: String) -> [String: String] {
        let url = fileURL(for: canvasId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            print("📦 Failed to load canvas storage for \(canvasId): \(error)")
            return [:]
        }
    }
    
    /// Save all key-values for a specific canvas ID.
    private func saveStorage(_ storage: [String: String], for canvasId: String) {
        let url = fileURL(for: canvasId)
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: url, options: .atomic)
        } catch {
            print("📦 Failed to save canvas storage for \(canvasId): \(error)")
        }
    }
    
    // MARK: - Public API
    
    func save(canvasId: String, key: String, value: String) {
        var storage = loadStorage(for: canvasId)
        storage[key] = value
        saveStorage(storage, for: canvasId)
    }
    
    func load(canvasId: String, key: String) -> String? {
        let storage = loadStorage(for: canvasId)
        return storage[key]
    }
    
    func remove(canvasId: String, key: String) {
        var storage = loadStorage(for: canvasId)
        storage.removeValue(forKey: key)
        saveStorage(storage, for: canvasId)
    }
    
    func listKeys(canvasId: String) -> [String] {
        let storage = loadStorage(for: canvasId)
        return Array(storage.keys)
    }
    
    func clearStorage(for canvasId: String) {
        let url = fileURL(for: canvasId)
        try? FileManager.default.removeItem(at: url)
    }
    
    func clearAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
    }
}
