import SwiftUI

struct MarkdownContentView: View {
    let text: String
    
    private enum ContentBlock: Identifiable {
        case text(String)
        case code(language: String, code: String)
        
        var id: String {
            switch self {
            case .text(let val): return "text-\(val.hashValue)"
            case .code(_, let val): return "code-\(val.hashValue)"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseBlocks(from: text)) { block in
                switch block {
                case .text(let content):
                    if !content.isEmpty {
                        Text(LocalizedStringKey(content))
                            .font(.system(.body, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let lang, let code):
                    CodeBlockView(code: code, language: lang)
                        .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func parseBlocks(from input: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let separator = "```"
        let components = input.components(separatedBy: separator)
        
        for (index, component) in components.enumerated() {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Even index means text outside blocks
            if index % 2 == 0 {
                if !component.isEmpty {
                    blocks.append(.text(component))
                }
            } else {
                // Odd index means inside the code block
                var lines = component.components(separatedBy: .newlines)
                let langLine = lines.isEmpty ? "" : lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Determine if first line is a language identifier
                let validLangPattern = "^[a-zA-Z0-9]+$"
                let isLanguage = langLine.range(of: validLangPattern, options: .regularExpression) != nil
                
                let language: String
                let code: String
                
                if isLanguage && lines.count > 1 {
                    language = langLine
                    lines.removeFirst()
                    code = lines.joined(separator: "\n")
                } else {
                    language = ""
                    code = component
                }
                
                blocks.append(.code(language: language, code: code.trimmingCharacters(in: .newlines)))
            }
        }
        
        return blocks
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = code
                    #else
                    let pb = NSPasteboard.general
                    pb.declareTypes([.string], owner: nil)
                    pb.setString(code, forType: .string)
                    #endif
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            
            Divider()
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(12)
            }
        }
        .background(Color.primary.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    VStack {
        MarkdownContentView(text: "Here is some **bold** text and a `short_code` snippet.\n\nAnd a full block:\n```swift\nlet a = 10\nprint(a)\n```\nDone.")
            .padding()
    }
}
