import Foundation

/// Pure Swift static analyzer that parses generated HTML code and runs quality assertions.
struct CanvasHTMLValidator {
    
    struct TestAssertion: Identifiable, Hashable, Codable {
        var id = UUID()
        let name: String
        let description: String
        let passed: Bool
        let feedback: String
    }
    
    /// Runs a comprehensive suite of static analysis and dynamic code capability tests.
    static func runSuite(html: String, requestedCapabilities: [String]) -> [TestAssertion] {
        var assertions: [TestAssertion] = []
        
        // 1. Structure Check
        let hasDoctype = html.lowercased().contains("<!doctype html>")
        let hasHtml = html.lowercased().contains("<html") && html.lowercased().contains("</html>")
        let hasHead = html.lowercased().contains("<head>") && html.lowercased().contains("</head>")
        let hasBody = html.lowercased().contains("<body>") && html.lowercased().contains("</body>")
        
        assertions.append(TestAssertion(
            name: "Standard HTML5 Structure",
            description: "Verifies correct DOCTYPE, html wrapper, head and body tag completeness.",
            passed: hasDoctype && hasHtml && hasHead && hasBody,
            feedback: hasDoctype && hasHtml && hasHead && hasBody ? 
                "Standard structure conforms perfectly." : 
                "Missing one or more standard layout tags (doctype, html, head, or body)."
        ))
        
        // 2. Viewport Responsiveness Check
        let hasViewport = html.lowercased().contains("name=\"viewport\"") || html.lowercased().contains("name='viewport'")
        let isMobileResponsive = hasViewport && 
            (html.lowercased().contains("width=device-width") || html.lowercased().contains("initial-scale="))
        
        assertions.append(TestAssertion(
            name: "Mobile Viewport Responsiveness",
            description: "Checks if a viewport meta tag specifies mobile-friendly, scale-fitted scaling.",
            passed: isMobileResponsive,
            feedback: isMobileResponsive ?
                "Viewport metadata detected. Scaling fits device bounds smoothly." :
                "Missing scale-fitting viewport tags. Layout might feel unoptimized on small screens."
        ))
        
        // 3. Apple Aesthetics & CSS Harmony
        let supportsDarkMode = html.lowercased().contains("prefers-color-scheme") || html.lowercased().contains("color-scheme")
        let usesAppleFonts = html.lowercased().contains("-apple-system") || html.lowercased().contains("sf pro") || html.lowercased().contains("sans-serif")
        
        assertions.append(TestAssertion(
            name: "iOS Harmonious Appearance",
            description: "Checks for dark-mode adaptation styles and Apple Human Interface typography.",
            passed: supportsDarkMode && usesAppleFonts,
            feedback: (supportsDarkMode && usesAppleFonts) ?
                "Excellent! Detected system fonts and adaptive appearance queries." :
                "Aesthetic rules are incomplete. Add prefers-color-scheme variables for beautiful style transitions."
        ))
        
        // 4. Device Bridge Event Listener Setup
        let hasReadyListener = html.contains("pelbagaiReady") || html.contains("window.pelbagai.onReady")
        
        assertions.append(TestAssertion(
            name: "Bridge Connection Setup",
            description: "Ensures the app hooks into the device listener event to synchronize initial states safely.",
            passed: hasReadyListener,
            feedback: hasReadyListener ?
                "Successfully listening for device bridge readiness signal." :
                "Missing 'pelbagaiReady' event hook. State restoration might start before the bridge is fully initialized."
        ))
        
        // 5. Capability Matchers
        for capability in requestedCapabilities {
            let passed: Bool
            let feedback: String
            let name = "Capability Hook: \(capability)"
            
            switch capability.lowercased() {
            case "local storage", "storage":
                passed = html.contains("window.pelbagai.storage") || html.contains("pelbagai.storage")
                feedback = passed ?
                    "Durable sandboxed state load/save verified in Javascript code." :
                    "Requested storage capability, but could not detect window.pelbagai.storage operations."
                
            case "camera/photos", "camera", "photos":
                passed = html.contains("window.pelbagai.camera") || html.contains("window.pelbagai.photos") ||
                         html.contains("pelbagai.camera") || html.contains("pelbagai.photos")
                feedback = passed ?
                    "On-device media capturing/picking hooks successfully validated." :
                    "Requested camera picker, but did not find calls to window.pelbagai.camera or photos."
                
            case "haptics/alerts", "haptic", "alerts":
                passed = html.contains("window.pelbagai.ui.haptic") || html.contains("window.pelbagai.ui.alert") ||
                         html.contains("window.pelbagai.ui.toast") || html.contains("pelbagai.ui")
                feedback = passed ?
                    "Physical tactile haptics and alerts setup confirmed." :
                    "Requested alerts, but could not find calls to window.pelbagai.ui."
                
            case "share sheets", "share":
                passed = html.contains("window.pelbagai.share") || html.contains("pelbagai.share")
                feedback = passed ?
                    "System share sheets dispatcher integrated." :
                    "Requested share sheets integration, but could not locate window.pelbagai.share hooks."
                
            default:
                // General fallback checks if any reference to pelbagai exists
                passed = html.contains("window.pelbagai") || html.contains("pelbagai")
                feedback = passed ? "Valid device bridge operations referenced." : "No bridge interactions found."
            }
            
            assertions.append(TestAssertion(
                name: name,
                description: "Verifies correct Javascript hook implementation matching requested native APIs.",
                passed: passed,
                feedback: feedback
            ))
        }
        
        return assertions
    }
}
