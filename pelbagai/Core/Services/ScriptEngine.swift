import Foundation

/// Legacy compatibility shim.
///
/// Earlier scanner experiments treated `_script` as JavaScript and executed it
/// in a `JSContext`. The local tool protocol is now declarative: model output
/// may include extraction notes, state, and actions, but Swift-owned code
/// validates and executes every action.
enum ScriptEngine {
    @available(*, deprecated, message: "Model-produced scripts are no longer executed. Use ToolAction instead.")
    @discardableResult
    static func run(_ result: ScanResult) -> ScanResult {
        result
    }
}
