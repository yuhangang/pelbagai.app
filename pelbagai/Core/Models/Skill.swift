import Foundation

struct Skill: Identifiable, Codable, Equatable, Hashable {
    var id: String { name }
    var name: String
    var displayName: String
    var description: String
    var instructions: String
    var isBuiltIn: Bool
    var icon: String
    var color: String
    var htmlContent: String? = nil
    
    static func parse(from markdown: String, fallbackName: String = "Imported Skill") -> Skill? {
        let lines = markdown.components(separatedBy: .newlines)
        
        var name = ""
        var description = ""
        
        var frontmatterStartIndex: Int?
        var frontmatterEndIndex: Int?
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                if frontmatterStartIndex == nil {
                    frontmatterStartIndex = index
                } else if frontmatterEndIndex == nil {
                    frontmatterEndIndex = index
                    break
                }
            }
        }
        
        var frontmatterLineCount = 0
        if let start = frontmatterStartIndex, let end = frontmatterEndIndex, start < end {
            frontmatterLineCount = end + 1
            
            for index in (start + 1)..<end {
                let line = lines[index]
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if key == "name" {
                        name = value
                    } else if key == "description" {
                        description = value
                    }
                }
            }
        }
        
        var instructionLines: [String] = []
        if frontmatterLineCount > 0 {
            for index in frontmatterLineCount..<lines.count {
                instructionLines.append(lines[index])
            }
        } else {
            instructionLines = lines
        }
        
        if name.isEmpty {
            name = fallbackName.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        
        let instructions = instructionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let displayName = name.replacingOccurrences(of: "-", with: " ").capitalized
        let icon = defaultIcon(for: name)
        let color = defaultColor(for: name)
        
        var htmlContent: String? = nil
        if let regex = try? NSRegularExpression(pattern: "```html\\s*([\\s\\S]*?)\\s*```", options: []) {
            let nsString = markdown as NSString
            if let match = regex.firstMatch(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length)) {
                htmlContent = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return Skill(
            name: name,
            displayName: displayName,
            description: description.isEmpty ? "Specialized assistant skill." : description,
            instructions: instructions.isEmpty ? markdown : instructions,
            isBuiltIn: false,
            icon: icon,
            color: color,
            htmlContent: htmlContent
        )
    }
    
    private static func defaultIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wiki") { return "globe.americas.fill" }
        if lower.contains("finance") || lower.contains("money") || lower.contains("budget") { return "dollarsign.circle.fill" }
        if lower.contains("fire") || lower.contains("burn") { return "flame.fill" }
        if lower.contains("law") || lower.contains("legal") { return "gavel.fill" }
        if lower.contains("music") || lower.contains("song") { return "music.note" }
        if lower.contains("health") || lower.contains("medical") { return "heart.text.square.fill" }
        return "bolt.fill"
    }
    
    private static func defaultColor(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("wiki") { return "cyan" }
        if lower.contains("finance") { return "green" }
        if lower.contains("fire") { return "orange" }
        if lower.contains("legal") { return "purple" }
        if lower.contains("music") { return "pink" }
        return "blue"
    }
}
