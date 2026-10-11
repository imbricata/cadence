import Foundation
import Security

public enum OpenRouterKeychain {
    private static let service = "com.cadence.openrouter"
    private static let account = "apikey"

    public static func key() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func setKey(_ key: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var attrs = query
        attrs[kSecValueData as String] = key.data(using: .utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }
}

public enum OpenRouterSettings {
    private static let modelKey = "or.model"
    private static let capKey = "or.cap"
    private static let costKey = "or.cost"

    public static let defaultModel = "google/gemini-2.5-flash-lite"
    public static let fallbackModel = "openai/gpt-5-nano"

    public static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    public static var monthlyCapUSD: Double {
        get { UserDefaults.standard.double(forKey: capKey) == 0 ? 1.0 : UserDefaults.standard.double(forKey: capKey) }
        set { UserDefaults.standard.set(newValue, forKey: capKey) }
    }
}

public enum CostTracker {
    /// Rough USD per 1M tokens: (input, output). Estimates only.
    private static let prices: [String: (Double, Double)] = [
        "google/gemini-2.5-flash-lite": (0.10, 0.40),
        "openai/gpt-5-nano": (0.40, 1.60)
    ]
    private static let defaultPrice: (Double, Double) = (0.30, 1.20)

    private static var monthKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: .now)
    }

    private static var totals: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: "or.cost") as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "or.cost") }
    }

    public static var monthCostUSD: Double {
        totals[monthKey] ?? 0
    }

    public static func record(model: String?, inputTokens: Int, outputTokens: Int) {
        let (ip, op) = price(for: model)
        let cost = Double(inputTokens) / 1_000_000 * ip + Double(outputTokens) / 1_000_000 * op
        var t = totals
        t[monthKey] = (t[monthKey] ?? 0) + cost
        totals = t
    }

    public static func reset() {
        totals = [:]
    }

    public static func isOverCap() -> Bool {
        OpenRouterSettings.monthlyCapUSD > 0 && monthCostUSD >= OpenRouterSettings.monthlyCapUSD
    }

    private static func price(for model: String?) -> (Double, Double) {
        guard let model else { return defaultPrice }
        if let p = prices[model] { return p }
        if model.hasPrefix("google/") { return (0.10, 0.40) }
        if model.hasPrefix("openai/") { return (0.40, 1.60) }
        return defaultPrice
    }
}