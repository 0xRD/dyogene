import Foundation

/// How long something has gone unused, as a level from 0 (used today) to 1 (three years or more).
/// The scale is logarithmic so that the first months matter as much as the last years.
public enum Dust {
    public static let day: Double = 86_400
    /// Ages at which the legend puts a mark.
    public static let legend: [(label: String, age: Double)] = [
        ("Today", 0), ("1 month", 30 * day), ("6 months", 182 * day), ("1 year", 365 * day), ("3 years+", 3 * 365 * day),
    ]
    private static let fullAge = 3 * 365 * day

    /// 0...1. Unknown dates (0) count as fresh: never accuse something without evidence.
    public static func level(lastUsed: Double, now: Double) -> Double {
        guard lastUsed > 0 else { return 0 }
        let age = max(0, now - lastUsed)
        let days = age / day
        let full = fullAge / day
        return min(1, log1p(days) / log1p(full))
    }

    /// Age in seconds for a level, the inverse of `level`.
    public static func age(forLevel level: Double) -> Double {
        expm1(level * log1p(fullAge / day)) * day
    }
}

/// English, locale-independent formatting shared by the app and the CLI.
public enum Format {
    /// Decimal units, as Finder shows them.
    public static func bytes(_ value: UInt64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var unit = 0
        while amount >= 1000 && unit < units.count - 1 {
            amount /= 1000
            unit += 1
        }
        if unit == 0 { return value == 1 ? "1 byte" : "\(value) bytes" }
        let digits = amount < 10 ? 1 : 0
        return String(format: "%.\(digits)f %@", amount, units[unit])
    }

    /// "today", "3 days ago", "5 months ago", "2 years ago"; "unknown" for 0.
    public static func age(lastUsed: Double, now: Double) -> String {
        guard lastUsed > 0 else { return "unknown" }
        let days = Int(max(0, now - lastUsed) / Dust.day)
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<30: return "\(days) days ago"
        case 30..<365:
            let months = days / 30
            return months == 1 ? "1 month ago" : "\(months) months ago"
        default:
            let years = days / 365
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    public static func date(_ seconds: Double) -> String {
        guard seconds > 0 else { return "unknown" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    public static func count(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func percent(_ part: UInt64, of whole: UInt64) -> String {
        guard whole > 0 else { return "0%" }
        let value = Double(part) / Double(whole) * 100
        if value > 0 && value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    /// Parses "500MB", "1.5 GB", "200k" into bytes (decimal units).
    public static func parseBytes(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = trimmed.prefix { $0.isNumber || $0 == "." }
        guard let number = Double(digits) else { return nil }
        let unit = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        let factor: Double
        switch unit {
        case "", "b", "bytes": factor = 1
        case "k", "kb": factor = 1e3
        case "m", "mb": factor = 1e6
        case "g", "gb": factor = 1e9
        case "t", "tb": factor = 1e12
        default: return nil
        }
        return UInt64(number * factor)
    }

    /// Parses "30d", "6m", "1y", "2w" into seconds.
    public static func parseAge(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let last = trimmed.last, let number = Double(trimmed.dropLast()) else { return nil }
        switch last {
        case "d": return number * Dust.day
        case "w": return number * 7 * Dust.day
        case "m": return number * 30 * Dust.day
        case "y": return number * 365 * Dust.day
        default: return nil
        }
    }
}
