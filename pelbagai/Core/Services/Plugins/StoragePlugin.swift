import Foundation

@MainActor
struct StoragePlugin: NativePlugin {
    let id = "storage"
    let displayName = "Storage"

    var capabilities: [NativePluginCapability] {
        [
            NativePluginCapability(
                id: "list_files",
                displayName: "List Files",
                description: "List files in the app's documents directory.",
                argumentSchema: [:],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "read_file",
                displayName: "Read File",
                description: "Read the content of a file in documents.",
                argumentSchema: ["filename": "The name of the file to read"],
                requiresUserApproval: false
            ),
            NativePluginCapability(
                id: "write_file",
                displayName: "Write File",
                description: "Create or overwrite a file in documents.",
                argumentSchema: [
                    "filename": "The name of the file",
                    "content": "Text content to save"
                ],
                requiresUserApproval: true
            )
        ]
    }

    var chatTools: [NativeChatTool] {
        [
            NativeChatTool(
                name: "list_documents",
                displayName: "List Documents",
                description: "Use to see what files are saved locally.",
                pluginID: id,
                capabilityID: "list_files"
            ),
            NativeChatTool(
                name: "read_local_file",
                displayName: "Read Local File",
                description: "Use to read the content of a specific local file.",
                pluginID: id,
                capabilityID: "read_file"
            ),
            NativeChatTool(
                name: "save_to_tool_table",
                displayName: "Save to Table",
                description: "Use to save structured information (like a receipt, contact, or note) into a specific tool's persistent table view. Ensure you use the correct tool_id.",
                pluginID: id,
                capabilityID: "save_result"
            )
        ]
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func execute(capabilityID: String, arguments: [String: String]) async throws -> NativePluginResult {
        switch capabilityID {
        case "list_files":
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let fileList = files.map { $0.lastPathComponent }.joined(separator: "\n")
            return NativePluginResult(summary: fileList.isEmpty ? "No files in documents." : "Files:\n\(fileList)")
        case "read_file":
            let filename = arguments["filename"] ?? ""
            let fileURL = documentsURL.appendingPathComponent(filename)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return NativePluginResult(summary: "File content of '\(filename)':\n\(content)", data: ["content": content])
        case "write_file":
            let filename = arguments["filename"] ?? ""
            let content = arguments["content"] ?? ""
            let fileURL = documentsURL.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return NativePluginResult(summary: "Successfully wrote to '\(filename)'.")
        case "save_result":
            let toolID = arguments["tool_id"] ?? "custom_tool"
            let dataString = arguments["data"] ?? "{}"
            
            guard let data = dataString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NativePluginError.unknownCapability(pluginID: id, capabilityID: "save_result")
            }
            
            let richFields = json.mapValues { value -> FieldValue in
                if let arr = value as? [String] { return .list(arr) }
                return .string("\(value)")
            }
            
            let result = ScanResult(
                toolID: toolID,
                richFields: richFields,
                isValidated: true,
                timestamp: Date()
            )
            
            ToolStorage.shared.save(result, to: toolID)
            return NativePluginResult(summary: "Successfully saved entry to \(toolID) table.")
        default:
            throw NativePluginError.unknownCapability(pluginID: id, capabilityID: capabilityID)
        }
    }
}
