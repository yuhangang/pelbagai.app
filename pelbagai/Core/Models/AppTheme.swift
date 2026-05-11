import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "Auto"
    case light = "Light"
    case dark = "Dark"
    
    var id: Self { self }
}
