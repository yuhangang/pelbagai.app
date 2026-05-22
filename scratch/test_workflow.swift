import Foundation
import JavaScriptCore

// Define mock structures to match what ToolScriptRuntime encodes
struct WorkflowScriptInput: Codable {
    var reason: String
    var targetToolID: String
    var latestResult: ScanResultMock?
    var recordsByTool: [String: [ScanResultMock]]
}

enum FieldValueMock: Codable {
    case string(String)
    case list([String])
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .list(let a):   try container.encode(a)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .list(arr)
        } else {
            self = .string((try? container.decode(String.self)) ?? "")
        }
    }
}

struct ScanResultMock: Codable {
    var id: UUID
    var toolID: String
    var template: String
    var richFields: [String: FieldValueMock]
    var isValidated: Bool
    var validationNotes: String
    var timestamp: Date
}

struct LocalToolDefinition: Codable {
    struct WorkflowDefinition: Codable {
        var transformScript: String
    }
    var toolID: String
    var workflow: WorkflowDefinition?
}

// 1. Load the script from LOCAL_TOOLS.json
let localToolsURL = URL(fileURLWithPath: "/Users/yuhang.ang/Desktop/Projects/model/pelbagaiapp/pelbagai/Core/Services/LOCAL_TOOLS.json")
guard let data = try? Data(contentsOf: localToolsURL),
      let definitions = try? JSONDecoder().decode([LocalToolDefinition].self, from: data),
      let expenseReportDef = definitions.first(where: { $0.toolID == "expense_report" }),
      let transformScript = expenseReportDef.workflow?.transformScript else {
    print("Failed to load LOCAL_TOOLS.json or find expense_report workflow script.")
    exit(1)
}

// 2. Prepare mock receipts input
let mockReceipts = [
    ScanResultMock(
        id: UUID(),
        toolID: "receipt",
        template: "Receipt",
        richFields: [
            "Store Name": .string("Whole Foods Market"),
            "Total": .string("$42.15"),
            "Currency": .string("USD"),
            "Date": .string("2026-05-18")
        ],
        isValidated: true,
        validationNotes: "Mocked",
        timestamp: Date()
    ),
    ScanResultMock(
        id: UUID(),
        toolID: "receipt",
        template: "Receipt",
        richFields: [
            "Store Name": .string("Target"),
            "Total": .string("15.50"),
            "Currency": .string("USD"),
            "Date": .string("2026-05-19")
        ],
        isValidated: true,
        validationNotes: "Mocked",
        timestamp: Date()
    )
]

let input = WorkflowScriptInput(
    reason: "Generate report",
    targetToolID: "expense_report",
    latestResult: nil,
    recordsByTool: ["receipt": mockReceipts]
)

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
guard let inputJSONData = try? encoder.encode(input),
      let inputJSON = String(data: inputJSONData, encoding: .utf8) else {
    print("Failed to encode input.")
    exit(1)
}

// 3. Set up JSContext and execute
guard let context = JSContext() else {
    print("Failed to create JSContext.")
    exit(1)
}

context.exceptionHandler = { _, exception in
    print("JS Exception: \(exception?.toString() ?? "Unknown")")
}

context.setObject(inputJSON, forKeyedSubscript: "inputJSON" as NSString)

let wrappedScript = """
(function() {
  "use strict";
  var input = JSON.parse(inputJSON);
  var output = (function(input) {
\(transformScript)
  })(input);
  return JSON.stringify(output || {});
})();
"""

guard let value = context.evaluateScript(wrappedScript),
      let outputJSON = value.toString() else {
    print("Script execution failed.")
    exit(1)
}

print("Script execution succeeded! Output JSON:")
print(outputJSON)
