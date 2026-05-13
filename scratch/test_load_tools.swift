import Foundation

// Mock classes to test loading
struct LocalToolDefinition: Codable {
    var toolID: String
    var displayName: String
}

let decoder = JSONDecoder()
let url = URL(fileURLWithPath: "/Users/yuhang.ang/Desktop/Projects/model/pelbagaiapp/pelbagai/Core/Services/LOCAL_TOOLS.json")

do {
    let data = try Data(contentsOf: url)
    let defs = try decoder.decode([LocalToolDefinition].self, from: data)
    print("Successfully loaded \(defs.count) tool definitions.")
    for def in defs {
        print("- \(def.displayName) (\(def.toolID))")
    }
} catch {
    print("Failed to load definitions: \(error)")
}
