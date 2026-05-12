import Foundation

enum FieldValue {
    case string(String)
    case list([String])
    
    var flatString: String {
        switch self {
        case .string(let s): return s
        case .list(let a):   return a.joined(separator: ", ")
        }
    }
}

func escapeCSV(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

var richFields: [String: FieldValue] = [
    "Name": .string("MITCHEL JHQON"),
    "Title": .string("Creative Designer"),
    "Company": .string(""),
    "Email": .string(""),
    "Phone": .string(""),
    "Address": .string(""),
    "Website": .string("")
]

let allKeys = ["Address", "Company", "Email", "Name", "Phone", "Title", "Website"]

var values: [String] = allKeys.map { key in
    escapeCSV(richFields[key]?.flatString ?? "")
}

values.append(escapeCSV("business_card"))
values.append(escapeCSV("Business Card"))
values.append("Yes")
values.append(escapeCSV(""))
values.append(escapeCSV(""))
values.append(escapeCSV(""))
values.append("2026-05-12T07:51:36Z")

print(allKeys.joined(separator: ","))
print(values.joined(separator: ","))
