import Foundation

// MARK: - Core Parser Logic under Test (Copied from ChatViewModel to run in isolation)
struct CanvasParser {
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

// MARK: - Test Runner
func runTests() {
    print("🧪 Starting AI Canvas parsing and prompt generation unit tests...")
    
    // Test Case 1: Standard ```html markdown block extraction
    let test1 = """
    Here is your app:
    ```html
    <!DOCTYPE html>
    <html>
    <head><title>Test App 1</title></head>
    <body><h1>Hello</h1></body>
    </html>
    ```
    Enjoy!
    """
    let html1 = CanvasParser.extractHTML(from: test1)
    assert(html1 != nil, "Test 1 Failed: Extraction returned nil")
    assert(html1!.contains("<title>Test App 1</title>"), "Test 1 Failed: Content missing title")
    
    let clean1 = CanvasParser.cleanResponseText(test1)
    assert(!clean1.contains("```html"), "Test 1 Failed: Clean response contains block start")
    assert(!clean1.contains("</html>"), "Test 1 Failed: Clean response contains HTML tags")
    assert(clean1.contains("Here is your app:") && clean1.contains("Enjoy!"), "Test 1 Failed: Explanation text lost")
    print("✅ Test Case 1 (Standard block) passed!")
    
    // Test Case 2: Case-insensitive block detection (e.g. ```HTML)
    let test2 = """
    ```HTML
    <html><body>Count</body></html>
    ```
    """
    let html2 = CanvasParser.extractHTML(from: test2)
    assert(html2 != nil, "Test 2 Failed: Case-insensitive extraction failed")
    assert(html2! == "<html><body>Count</body></html>", "Test 2 Failed: Content mismatch")
    print("✅ Test Case 2 (Case-insensitive block) passed!")
    
    // Test Case 3: Fallback raw <html> tags (without markdown block)
    let test3 = """
    Sure, here is the code:
    <HTML>
    <head><title>Raw App</title></head>
    <body>Test</body>
    </HTML>
    Hope you like it!
    """
    let html3 = CanvasParser.extractHTML(from: test3)
    assert(html3 != nil, "Test 3 Failed: Raw tags extraction failed")
    assert(html3!.contains("<title>Raw App</title>"), "Test 3 Failed: Content missing title")
    
    let clean3 = CanvasParser.cleanResponseText(test3)
    assert(!clean3.contains("Raw App"), "Test 3 Failed: Clean response contains raw HTML app title")
    assert(clean3.contains("Sure, here is the code:") && clean3.contains("Hope you like it!"), "Test 3 Failed: Explanations lost")
    print("✅ Test Case 3 (Raw tags fallback) passed!")
    
    // Test Case 4: Fallback <!DOCTYPE html> ... </html>
    let test4 = """
    Some text
    <!doctype html>
    <html><body>Doctype</body></html>
    Some trailing text
    """
    let html4 = CanvasParser.extractHTML(from: test4)
    assert(html4 != nil, "Test 4 Failed: Doctype extraction failed")
    assert(html4!.contains("Doctype"), "Test 4 Failed: Content missing")
    
    let clean4 = CanvasParser.cleanResponseText(test4)
    assert(!clean4.contains("Doctype"), "Test 4 Failed: Clean response contains html text")
    assert(clean4.contains("Some text") && clean4.contains("Some trailing text"), "Test 4 Failed: Explanations lost")
    print("✅ Test Case 4 (Doctype fallback) passed!")
    
    // Test Case 5: Response cleaning with ONLY html output (should return success placeholder)
    let test5 = """
    ```html
    <html><body>Only Code</body></html>
    ```
    """
    let clean5 = CanvasParser.cleanResponseText(test5)
    assert(clean5 == "Generated AI Canvas micro-app successfully.", "Test 5 Failed: Empty explanation placeholder mismatch")
    print("✅ Test Case 5 (Placeholder fallback) passed!")
    
    print("🚀 All parser unit tests completed successfully!")
}

runTests()
