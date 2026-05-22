import Foundation
import JavaScriptCore

enum ToolScriptRuntimeError: LocalizedError {
    case scriptError(String)
    case invalidOutput
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .scriptError(let message):
            return "Tool script failed: \(message)"
        case .invalidOutput:
            return "Tool script did not return a valid JSON object."
        case .encodingFailed:
            return "Tool script input could not be encoded."
        }
    }
}

struct WorkflowScriptInput: Codable {
    var reason: String
    var targetToolID: String
    var latestResult: ScanResult?
    var recordsByTool: [String: [ScanResult]]
}

final class ToolScriptRuntime {
    func execute(script: String, input: WorkflowScriptInput) throws -> WorkflowArtifact {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let inputJSONData = try? encoder.encode(input),
              let inputJSON = String(data: inputJSONData, encoding: .utf8) else {
            throw ToolScriptRuntimeError.encodingFailed
        }

        guard let context = JSContext() else {
            throw ToolScriptRuntimeError.invalidOutput
        }

        var capturedError: String?
        context.exceptionHandler = { _, exception in
            capturedError = exception?.toString()
        }

        context.setObject(inputJSON, forKeyedSubscript: "inputJSON" as NSString)

        let wrappedScript = """
        (function() {
          "use strict";
          var input = JSON.parse(inputJSON);
          var output = (function(input) {
        \(script)
          })(input);
          return JSON.stringify(output || {});
        })();
        """

        guard let value = context.evaluateScript(wrappedScript),
              capturedError == nil,
              let outputJSON = value.toString(),
              let outputData = outputJSON.data(using: .utf8) else {
            throw ToolScriptRuntimeError.scriptError(capturedError ?? "Unknown JavaScript error")
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WorkflowArtifact.self, from: outputData)
        } catch {
            throw ToolScriptRuntimeError.invalidOutput
        }
    }
}
