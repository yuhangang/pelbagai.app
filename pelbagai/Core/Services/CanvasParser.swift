import Foundation

/// Centralized parser and visual code-cleaning service for AI Canvas HTML application blocks.
struct CanvasParser {
    
    /// Searches the generated LLM text for HTML formats: markdown blocks, full HTML tags, or DOCTYPE wrappers.
    static func extractHTML(from text: String) -> String? {
        // Let's first search for html code blocks: ```html ... ```
        if let blockStart = text.range(of: "```html", options: .caseInsensitive) {
            let rest = text[blockStart.upperBound...]
            if let blockEnd = rest.range(of: "```") {
                let code = rest[..<blockEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    return code
                }
            }
        }
        
        // Fallback: search for <html> ... </html>
        if let htmlStart = text.range(of: "<html>", options: .caseInsensitive),
           let htmlEnd = text.range(of: "</html>", options: .caseInsensitive, range: htmlStart.upperBound..<text.endIndex) {
            return String(text[htmlStart.lowerBound...htmlEnd.upperBound])
        }
        
        // Check for <!DOCTYPE html> ... </html>
        if let doctypeStart = text.range(of: "<!DOCTYPE html>", options: .caseInsensitive),
           let htmlEnd = text.range(of: "</html>", options: .caseInsensitive, range: doctypeStart.upperBound..<text.endIndex) {
            return String(text[doctypeStart.lowerBound...htmlEnd.upperBound])
        }
        
        return nil
    }
    
    /// Cleans standard and inline HTML markers from the assistant response to keep the chat interface pristine.
    static func cleanResponseText(_ text: String) -> String {
        // Remove ```html ... ``` block
        var cleaned = text
        if let rangeStart = cleaned.range(of: "```html", options: .caseInsensitive) {
            let rest = cleaned[rangeStart.upperBound...]
            if let rangeEnd = rest.range(of: "```") {
                cleaned.removeSubrange(rangeStart.lowerBound...rest.index(rangeEnd.upperBound, offsetBy: -1))
            }
        }
        
        // Remove <html>...</html>
        if let htmlStart = cleaned.range(of: "<html>", options: .caseInsensitive),
           let htmlEnd = cleaned.range(of: "</html>", options: .caseInsensitive, range: htmlStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(htmlStart.lowerBound...htmlEnd.upperBound)
        }
        
        // Remove <!DOCTYPE html>...</html>
        if let doctypeStart = cleaned.range(of: "<!DOCTYPE html>", options: .caseInsensitive),
           let htmlEnd = cleaned.range(of: "</html>", options: .caseInsensitive, range: doctypeStart.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(doctypeStart.lowerBound...htmlEnd.upperBound)
        }
        
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Generated AI Canvas micro-app successfully."
        }
        return trimmed
    }
}
