import Foundation

enum ValidationScratch {
    static func sampleIsValid() -> Bool {
        let json: [String: Any] = ["isValid": 1]
        let fields = ["a": "b"]
        return json["isValid"] as? Bool ?? (fields.count >= 2)
    }
}
