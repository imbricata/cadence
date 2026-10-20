import Foundation

public struct DriveFile: Codable, Sendable {
    public var id: String
    public var name: String
}

public struct DriveAPI: Sendable {
    public init() {}

    private static let base = "https://www.googleapis.com/drive/v3"
    private static let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    static let appDataFolder = "appDataFolder"

    public func listFiles(accessToken: String) async throws -> [String: String] {
        var comps = URLComponents(string: Self.base + "/files")!
        comps.queryItems = [
            URLQueryItem(name: "spaces", value: Self.appDataFolder),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        struct FileList: Decodable { let files: [DriveFile] }
        let files = try JSONDecoder().decode(FileList.self, from: data).files
        return Dictionary(uniqueKeysWithValues: files.map { ($0.name, $0.id) })
    }

    public func downloadFile(accessToken: String, fileId: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.base + "/files/\(fileId)?alt=media")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    public func createFile(accessToken: String, name: String, data: Data) async throws -> String {
        let boundary = "cadence-\(UUID().uuidString)"
        var body = Data()
        let meta = "{\"name\":\"\(name)\",\"parents\":[\"\(Self.appDataFolder)\"]}"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(meta.data(using: .utf8)!)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: Self.uploadBase + "/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data2, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data2)
        struct Created: Decodable { let id: String }
        return try JSONDecoder().decode(Created.self, from: data2).id
    }

    public func updateFile(accessToken: String, fileId: String, data: Data) async throws {
        var request = URLRequest(url: URL(string: Self.uploadBase + "/files/\(fileId)?uploadType=media")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (data2, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data2)
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DriveAPIError.http(0, "no response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw DriveAPIError.unauthorized }
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw DriveAPIError.http(http.statusCode, msg)
        }
    }
}

public enum DriveAPIError: Error, LocalizedError {
    case unauthorized
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Google sign-in expired."
        case .http(let c, let m): return "Google Drive error \(c): \(m)"
        }
    }

    public var isAuthError: Bool {
        switch self {
        case .unauthorized: return true
        case .http(let c, _): return c == 401
        }
    }
}