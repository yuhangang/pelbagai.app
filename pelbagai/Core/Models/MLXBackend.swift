import Foundation

enum MLXBackend: String, CaseIterable, Identifiable {
    case gpu = "GPU (Metal)"
    case cpu = "CPU"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        self.rawValue
    }
}
