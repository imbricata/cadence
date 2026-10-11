import Foundation

public enum GoogleAPIError: Error, LocalizedError {
    case unauthorized
    case http(Int, String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Google sign-in expired. Please reconnect."
        case .http(let code, let msg): return "Google API error \(code): \(msg)"
        case .decoding(let m): return "Google API decoding error: \(m)"
        }
    }

    public var isAuthError: Bool {
        if case .http(let code, _) = self { return code == 401 || code == 403 }
        if case .unauthorized = self { return true }
        return false
    }
}

/// ISO-8601 / RFC 3339 formatting used by the Google Calendar API.
public enum GoogleDateFormat {
    public static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        f.timeZone = .current
        return f.string(from: date)
    }

    public static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        if let d = f.date(from: s) { return d }
        let g = DateFormatter()
        g.locale = Locale(identifier: "en_US_POSIX")
        g.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return g.date(from: s)
    }
}