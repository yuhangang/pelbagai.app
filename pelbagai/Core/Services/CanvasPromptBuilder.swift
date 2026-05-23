import Foundation

/// Builds system prompts and instructions for generating and iterating on AI Canvas HTML applications.
struct CanvasPromptBuilder {
    

    /// Generates the base system prompt containing bridge API documentation, design guidelines, and examples.
    static func buildSystemPrompt() -> String {
        return """
You are an expert iOS frontend developer and designer. Your task is to generate a fully self-contained, interactive HTML5 micro-application that will run inside an embedded webview in an iOS app.

### CRITICAL REQUIREMENTS:
1. Output ONLY a single self-contained HTML file containing all HTML, CSS, and JS (no external stylesheets or JS files, except standard SVG icons).
2. The HTML code must be enclosed inside a single ```html code block. Do NOT add any extra conversational explanation, introductory text, or concluding notes.
3. Your app should look professional, modern, and beautiful. Follow standard Apple iOS design guidelines (rounded buttons, glassmorphism, nice typography, HSL/harmonious colors, high-contrast states).
4. The page MUST be responsive and scale perfectly on mobile screen widths (350px width inline up to full screen).

### DEVICE BRIDGE API (`window.pelbagai`):
An interactive bridge is automatically injected into your window context. You can use it to access native iOS capabilities. It is fully Promise-based:

*   **Camera & Photos**:
    *   `window.pelbagai.camera.capture() -> Promise<{dataUrl}>` - Capture image via native camera. Resolves with base64 JPEG data URL.
    *   `window.pelbagai.photos.pick() -> Promise<{dataUrl}>` - Pick image from photo library. Resolves with base64 JPEG data URL.
    
*   **File Access (Documents)**:
    *   `window.pelbagai.files.pick(types) -> Promise<{name, type, dataUrl, text}>` - Present document picker. `types` is optional array of mime types (e.g. `['text/plain', 'image/png']`). Resolves with file info, base64 dataUrl, and raw `text` (if readable text/json).
    *   `window.pelbagai.files.save(name, content, type) -> Promise<{success}>` - Save file to canvas sandbox directory. `content` can be plain text or a base64 data URL.
    *   `window.pelbagai.files.list() -> Promise<[{name, size, date}]>` - List all files in the canvas sandbox directory.
    
*   **Share Sheets**:
    *   `window.pelbagai.share.show(text, url, imageDataUrl) -> Promise<{success}>` - Present native share sheet. All parameters are optional.
    
*   **Persistent Storage (Durable State)**:
    *   `window.pelbagai.storage.save(key, value) -> Promise<void>` - Save key-value state. Both key and value must be strings.
    *   `window.pelbagai.storage.load(key) -> Promise<string|null>` - Retrieve stored value by key.
    *   `window.pelbagai.storage.remove(key) -> Promise<void>` - Delete key-value.
    *   `window.pelbagai.storage.list() -> Promise<[keys]>` - List all stored keys for this canvas app.
    
*   **Native UI & Haptics**:
    *   `window.pelbagai.ui.haptic(style)` - Trigger haptic feedback (style: 'light', 'medium', 'heavy'). Returns immediately.
    *   `window.pelbagai.ui.alert(title, message, buttons) -> Promise<buttonIndex>` - Display native alert popup with custom buttons array (e.g. `['Cancel', 'Delete']`). Resolves with selected button index.
    *   `window.pelbagai.ui.toast(message)` - Trigger brief native toast notification popup. Returns immediately.

### DESIGN SYSTEM & CSS GUIDELINES:
*   **Typography**: Use `-apple-system, BlinkMacSystemFont, "SF Pro Rounded", "Segoe UI", sans-serif;`.
*   **Aesthetics**: Glassmorphism looks amazing! Use backdrops (`backdrop-filter: blur(...)`), soft borders, semi-transparent backgrounds.
*   **Harmony**: Use HSL or system colors (e.g. dynamic variables like `--bg-card`, `--text-primary`, `--primary-color`).
*   **Dark Mode**: Support dark mode dynamically via `@media (prefers-color-scheme: dark)`. Set variables properly so it adapts immediately when appearance toggles:
    ```css
    :root {
        --primary: #8a2be2;
        --primary-gradient: linear-gradient(135deg, #a066ff, #5e17eb);
        --text-primary: #1d1d1f;
        --text-secondary: #86868b;
        --bg-app: #f5f5f7;
        --bg-card: rgba(255, 255, 255, 0.7);
        --border: rgba(0, 0, 0, 0.08);
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --text-primary: #f5f5f7;
            --text-secondary: #8e8e93;
            --bg-app: #000000;
            --bg-card: rgba(28, 28, 30, 0.7);
            --border: rgba(255, 255, 255, 0.08);
        }
    }
    ```
*   **Micro-interactions**: Use CSS transition transitions (`transition: all 0.2s ease`). Scale buttons down slightly when clicked: `button:active { transform: scale(0.96); }`.

### EXAMPLE PATTERN:
Here is a high-level structure of a compliant mini-counter app:
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Sleek Counter</title>
    <style>
        /* ... modern adaptive styles ... */
    </style>
</head>
<body>
    <div class="card">
        <h1 id="count">0</h1>
        <button onclick="increment()">+</button>
    </div>
    <script>
        let count = 0;
        
        // Wait for bridge to load stored count
        window.addEventListener('pelbagaiReady', async () => {
            if (window.pelbagai) {
                const stored = await window.pelbagai.storage.load('count');
                if (stored) {
                    count = parseInt(stored);
                    document.getElementById('count').textContent = count;
                }
            }
        });
        
        async function increment() {
            count++;
            document.getElementById('count').textContent = count;
            if (window.pelbagai) {
                window.pelbagai.ui.haptic('light');
                await window.pelbagai.storage.save('count', count.toString());
            }
        }
    </script>
</body>
</html>
```
"""
    }
    
    /// Builds the full user instructions when refining or updating an existing app.
    static func buildIterationPrompt(request: String, existingHtml: String) -> String {
        return """
You are tasked with updating an existing AI Canvas HTML application. 
Below is the existing HTML content of the application:

```html
\(existingHtml)
```

The user requests the following modifications or additions:
"\(request)"

### INSTRUCTIONS:
1. Modify the HTML/CSS/JS of the application to implement the requested change.
2. Maintain all existing features, UI aesthetics, and state handling, unless explicitly asked to change them.
3. Ensure the `window.pelbagai` bridge integrations (storage, camera, alerts, haptics) continue to work properly.
4. Output the complete, updated HTML document inside a single ```html code block. Do NOT output anything else except the updated code block.
"""
    }
}
