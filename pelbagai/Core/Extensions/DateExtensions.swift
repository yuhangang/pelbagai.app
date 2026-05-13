import Foundation

extension Date {
    enum TimestampPrecision {
        case hour
        case minute
        case second
    }

    /// Returns a localized string representation of the date with the specified time precision.
    /// - Parameter precision: The level of detail for the time component.
    /// - Returns: A formatted string like "May 12, 2026 at 10 AM" (.hour), "10:08 AM" (.minute), or "10:08:51 AM" (.second).
    func formattedTimestamp(precision: TimestampPrecision = .minute) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = .current
        
        switch precision {
        case .hour:
            formatter.dateFormat = "MMM d, yyyy 'at' h a" // e.g., May 12, 2026 at 10 AM
        case .minute:
            formatter.timeStyle = .short // e.g., 10:08 AM (removes seconds)
        case .second:
            formatter.timeStyle = .medium // e.g., 10:08:51 AM
        }
        return formatter.string(from: self)
    }
}
