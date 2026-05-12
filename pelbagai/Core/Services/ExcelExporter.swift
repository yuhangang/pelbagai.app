import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

/// Exports an array of `ScanResult` to CSV format and provides sharing functionality.
/// CSV is used instead of XLSX to avoid third-party dependencies — it opens natively in Excel, Numbers, and Google Sheets.
@MainActor
class ExcelExporter: ObservableObject {
    @Published var exportedFileURL: URL?
    @Published var isExporting: Bool = false
    @Published var exportError: String?
    
    /// Generates a CSV file from the scanned results and returns the file URL.
    func exportToCSV(results: [ScanResult]) -> URL? {
        guard !results.isEmpty else {
            exportError = "No results to export."
            return nil
        }
        
        isExporting = true
        exportError = nil
        
        defer { isExporting = false }
        
        // Collect all unique field keys across results
        let allKeys = ScanResult.allFieldKeys(from: results)
        
        // Build CSV content (with UTF-8 BOM for Excel compatibility)
        var csvContent = "\u{FEFF}" + ScanResult.csvHeader(for: results) + "\n"
        for result in results {
            csvContent += result.csvRow(allKeys: allKeys) + "\n"
        }
        
        // Write to documents directory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "Scan_\(dateFormatter.string(from: Date())).csv"
        
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = documentsURL.appendingPathComponent(filename)
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            exportedFileURL = fileURL
            print("📊 Exported \(results.count) results to: \(fileURL.path)")
            return fileURL
        } catch {
            exportError = "Failed to write CSV: \(error.localizedDescription)"
            print("📊 Export error: \(error)")
            return nil
        }
    }
    
    /// Generates a CSV file from raw string content.
    func exportCustomCSV(content: String, filename: String) -> URL? {
        isExporting = true
        exportError = nil
        
        defer { isExporting = false }
        
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = documentsURL.appendingPathComponent(filename)
            
            let finalContent = content.hasPrefix("\u{FEFF}") ? content : "\u{FEFF}" + content
            try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            exportedFileURL = fileURL
            print("📊 Exported custom CSV to: \(fileURL.path)")
            return fileURL
        } catch {
            exportError = "Failed to write CSV: \(error.localizedDescription)"
            print("📊 Export error: \(error)")
            return nil
        }
    }
    
    /// Presents the system share sheet for the exported file.
    func shareFile(url: URL) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        // For iPad popover
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootVC.present(activityVC, animated: true)
        #endif
    }
}

/// A SwiftUI-compatible wrapper for CSV file documents used with `fileExporter`.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    let content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.content = text
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
