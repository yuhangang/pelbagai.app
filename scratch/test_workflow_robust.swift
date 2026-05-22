import Foundation
import JavaScriptCore

// New robust amount parser implementation
let newAmountJS = #"""
function amount(value) {
  if (value === undefined || value === null) return NaN;
  var str = String(value).trim();
  if (str === '') return NaN;
  
  // 1. European format check: if there is exactly one comma and no dot,
  // and it is followed by exactly 2 digits (e.g. "12,34"), treat it as a decimal point.
  if (str.indexOf(',') !== -1 && str.indexOf('.') === -1) {
    var parts = str.split(',');
    if (parts.length === 2 && parts[1].replace(/\D/g, '').length === 2) {
      str = str.replace(',', '.');
    }
  }
  
  // 2. Remove thousands separator commas (e.g. "1,234.56" -> "1234.56")
  str = str.replace(/,/g, '');
  
  // 3. Extract all potential numbers
  var match = str.match(/[-+]?\d*\.?\d+/g);
  if (!match || !match.length) return NaN;
  
  // 4. Return the first valid finite number (almost always the actual price/total)
  for (var i = 0; i < match.length; i++) {
    var val = Number(match[i]);
    if (isFinite(val)) return val;
  }
  
  return NaN;
}
"""#

// Original amount parser implementation for comparison
let originalAmountJS = #"""
function amount(value) {
  var match = String(value || '').replace(/,/g, '').match(/[-+]?\d*\.?\d+/g);
  return match && match.length ? Number(match[match.length - 1]) : NaN;
}
"""#

let testCases = [
    "$42.15",
    "42.15",
    "12,34",        // European decimal
    "$12.34 (Qty: 2)", // Trailing count
    "$12.34 [Tax: $1.00]", // Trailing tax
    "Total: 42.15 / Tax: 2.15", // Multiple numbers
    "1,234.56",     // Thousands separator
    "RM 12.34",     // Currency prefix
    "12.34 SGD",    // Currency suffix
    "Undated"       // Non-numeric
]

let context = JSContext()!

context.evaluateScript("var originalAmount = \(originalAmountJS)")
context.evaluateScript("var newAmount = \(newAmountJS)")

print(String(repeating: "-", count: 70))
print(String(format: "%-30s | %-15s | %-15s", "Input Total String", "Original JS", "Robust JS"))
print(String(repeating: "-", count: 70))

for testCase in testCases {
    context.setObject(testCase, forKeyedSubscript: "testValue" as NSString)
    
    let origVal = context.evaluateScript("originalAmount(testValue)").toString()!
    let newVal = context.evaluateScript("newAmount(testValue)").toString()!
    
    print(String(format: "%-30s | %-15s | %-15s", testCase, origVal, newVal))
}
print(String(repeating: "-", count: 70))
