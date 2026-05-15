import Foundation
import PDFKit

/// A service to handle generic file attachment operations.
class AttachmentService {
    enum AttachmentError: LocalizedError {
        case cannotReadFile
        case unsupportedType
        
        var errorDescription: String? {
            switch self {
            case .cannotReadFile: return "Could not read the file content."
            case .unsupportedType: return "This file type is not supported for text extraction."
            }
        }
    }
    
    /// Extracts text from a file (PDF or Plain Text).
    func extractText(from url: URL, maxCharacters: Int = 4000) throws -> String {
        let ext = url.pathExtension.lowercased()
        
        if ext == "pdf" {
            return try extractTextFromPDF(url: url, maxCharacters: maxCharacters)
        } else if ext == "txt" || ext == "text" {
            return try extractTextFromPlainFile(url: url, maxCharacters: maxCharacters)
        } else {
            // Fallback: try reading as plain text anyway
            return try extractTextFromPlainFile(url: url, maxCharacters: maxCharacters)
        }
    }
    
    private func extractTextFromPDF(url: URL, maxCharacters: Int) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw AttachmentError.cannotReadFile
        }
        
        var extractedText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                extractedText += pageText + "\n"
            }
            if extractedText.count >= maxCharacters { break }
        }
        return String(extractedText.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractTextFromPlainFile(url: URL, maxCharacters: Int) throws -> String {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return String(content.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw AttachmentError.cannotReadFile
        }
    }
}
