import Foundation

public struct InboxSortResult: Codable, Sendable {
    public var kind: ItemKind
    public var areaId: String
    public var title: String
    public var matchesExistingActivityId: String?
    public var dueDate: String?
    public var confidence: String
}

public struct ListEntry: Codable, Sendable {
    public var id: String
    public var title: String
}

public struct InboxSortRequest: Sendable {
    public var note: String
    public var areas: [ListEntry]
    public var activitiesByArea: [String: [ListEntry]]
    public var today: String
}

public enum OpenRouterError: Error, LocalizedError {
    case emptyContent(String)
    public var errorDescription: String? {
        if case .emptyContent(let m) = self { return m }
        return "Sorting failed."
    }
}

public protocol InboxSorting: Sendable {
    func sort(_ request: InboxSortRequest, apiKey: String, model: String) async throws -> (InboxSortResult, Int, Int)
}

public struct OpenRouterClient: InboxSorting {
    public init() {}

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Returns the sort result and token usage cost estimate.
    public func sort(_ request: InboxSortRequest, apiKey: String, model: String) async throws -> (InboxSortResult, Int, Int) {
        let body = Self.makeBody(request, model: model)
        let data = try await Self.post(body, apiKey: apiKey)
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            struct Usage: Decodable { let prompt_tokens: Int?; let completion_tokens: Int? }
            let choices: [Choice]
            let usage: Usage?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw OpenRouterError.emptyContent("empty response")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else { throw OpenRouterError.emptyContent("bad content") }
        let result = try JSONDecoder().decode(InboxSortResult.self, from: jsonData)
        return (result, response.usage?.prompt_tokens ?? 0, response.usage?.completion_tokens ?? 0)
    }

    private static func makeBody(_ request: InboxSortRequest, model: String) -> Data {
        var system = "You sort personal inbox notes into structured items. "
        system += "Return only the requested JSON. Do not invent areas. Today is \(request.today).\n"
        system += "Areas: "
        system += request.areas.map { "\($0.title) (id: \($0.id))" }.joined(separator: ", ")
        if !request.activitiesByArea.isEmpty {
            system += "\nExisting activities:\n"
            for (areaId, acts) in request.activitiesByArea {
                system += "- area \(areaId): " + acts.map { "\($0.title) (id: \($0.id))" }.joined(separator: ", ") + "\n"
            }
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": ["task", "activity"]],
                "areaId": ["type": "string"],
                "title": ["type": "string", "maxLength": 60],
                "matchesExistingActivityId": ["type": ["string", "null"]],
                "dueDate": ["type": ["string", "null"], "description": "YYYY-MM-DD or null"],
                "confidence": ["type": "string", "enum": ["high", "low"]]
            ],
            "required": ["kind", "areaId", "title", "matchesExistingActivityId", "dueDate", "confidence"],
            "additionalProperties": false
        ]

        let payload: [String: Any] = [
            "model": model,
            "models": [model, OpenRouterSettings.fallbackModel],
            "temperature": 0,
            "max_tokens": 150,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "inbox_sort",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": request.note]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func post(_ body: Data, apiKey: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw OpenRouterError.emptyContent("HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0): \(msg)")
        }
        return data
    }
}
