import SwiftUI
import Combine
import PhotosUI
import CoreImage

#if canImport(UIKit)
import UIKit
#else
import AppKit
fileprivate typealias UIImage = NSImage
#endif

@MainActor
class ScannerViewModel: ObservableObject {
    private let environment: AppEnvironment
    
    @Published var scanResults: [ScanResult] = []
    @Published var selectedToolID: String
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var capturedImage: UIImage?
    @Published var showCamera = false
    @Published var showExportSheet = false
    @Published var exportFileURL: URL?
    @Published var editingResult: ScanResult?
    @Published var showEditSheet = false
    
    // Model state mirroring
    @Published var isLoadingModel = false
    @Published var loadingText = ""
    @Published var isModelLoaded = false
    @Published var isProcessing = false
    @Published var status = ""
    @Published var lastResult: ScanResult?
    
    @Published var webViewURL: URL?
    @Published var showWebView = false
    
    private let exporter = ExcelExporter()
    private var cancellables = Set<AnyCancellable>()
    
    init(environment: AppEnvironment, initialToolID: String? = nil) {
        self.environment = environment
        self.selectedToolID = initialToolID ?? "parcel_address"
        
        setupBindings()
        loadStoredResults()
    }
    
    private func setupBindings() {
        environment.mlx.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isLoadingModel = $0 }
            .store(in: &cancellables)
            
        environment.mlx.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.loadingText = $0 }
            .store(in: &cancellables)
            
        environment.vision.$isProcessing
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isProcessing = $0 }
            .store(in: &cancellables)
            
        environment.vision.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.status = $0 }
            .store(in: &cancellables)
            
        environment.vision.$lastResult
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastResult = $0 }
            .store(in: &cancellables)
        
        environment.mlx.$isLoaded
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.isModelLoaded = $0 }
            .store(in: &cancellables)
            
        $selectedToolID.sink { [weak self] _ in
            self?.loadStoredResults()
        }.store(in: &cancellables)
    }
    
    var selectedTool: LocalToolDefinition {
        environment.registry.definition(for: selectedToolID) ?? 
        environment.registry.definition(for: "parcel_address") ??
        LocalToolDefinition(toolID: "fallback", displayName: "Scanner", description: "System scanner")
    }
    
    var selectedToolColor: Color {
        selectedTool.uiColor
    }
    
    var selectedToolIcon: String {
        selectedTool.uiIcon
    }
    
    func loadStoredResults() {
        scanResults = environment.storage.loadAll(from: selectedTool.toolID)
    }
    
    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if !environment.vision.isModelLoaded { await environment.vision.loadModel() }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            capturedImage = uiImage
            await processImage(uiImage)
        }
    }
    
    func processImage(_ image: UIImage) async {
        guard let ciImage = ImageInputPreparer.ciImage(from: image) else {
            environment.vision.status = "Failed to process image"
            return
        }
        if !environment.vision.isModelLoaded {
            await environment.vision.loadModel()
        }
        await environment.vision.scan(image: ciImage, definition: selectedTool)
    }
    
    func addToBatch(_ result: ScanResult) {
        scanResults.append(result)
        environment.storage.save(result, to: selectedTool.toolID)
        capturedImage = nil
        environment.vision.lastResult = nil
        environment.vision.status = ""
    }
    
    func discardResult() {
        capturedImage = nil
        environment.vision.lastResult = nil
        environment.vision.status = ""
    }
    
    func deleteResult(_ result: ScanResult) {
        environment.storage.delete(resultID: result.id, from: selectedTool.toolID)
        scanResults.removeAll { $0.id == result.id }
    }
    
    func updateResult(_ updated: ScanResult) {
        environment.storage.update(updated, in: selectedTool.toolID)
        if let idx = scanResults.firstIndex(where: { $0.id == updated.id }) {
            scanResults[idx] = updated
        }
    }
    
    func exportBatch() {
        if let url = exporter.exportToCSV(results: scanResults) {
            exportFileURL = url
            showExportSheet = true
        }
    }
    
    func openToolAction(_ action: ToolAction) {
        guard let url = validatedURL(for: action) else { return }
        webViewURL = url
        showWebView = true
    }
    
    func validatedURL(for action: ToolAction) -> URL? {
        guard action.type == .openURL,
              let rawURL = action.url,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
    
    func prepareAndShowCamera() {
        showCamera = true
    }
    
    func unloadModel() async {
        await environment.mlx.unloadModel()
    }
}
