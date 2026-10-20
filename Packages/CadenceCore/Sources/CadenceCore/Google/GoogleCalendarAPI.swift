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

    /// True only when signing in again would help. Rate limits and quota 403s are not auth errors.
    public var isAuthError: Bool {
        switch self {
        case .unauthorized: return true
        case .http(let code, let msg):
            if code == 401 { return true }
            let m = msg.lowercased()
            return code == 403 && (m.contains("insufficient") || m.contains("scope"))
        case .decoding: return false
        }
    }
}

/// ISO-8601 / RFC 3339 formatting used by the Google Calendar API.
public enum GoogleDateFormat {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let plain = make("yyyy-MM-dd'T'HH:mm:ssXXXXX")
    private static let fractional = make("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
    private static let lock = NSLock()

    public static func format(_ date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        plain.timeZone = .current
        return plain.string(from: date)
    }

    public static func parse(_ s: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return plain.date(from: s) ?? fractional.date(from: s)
    }
}

/// Network failures that mean "offline", not "signed out".
public func isOfflineError(_ error: Error) -> Bool {
    guard let e = error as? URLError else { return false }
    switch e.code {
    case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
         .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
        return true
    default:
        return false
    }
}
