import Foundation
import AuthenticationServices
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public enum GoogleAuthError: Error, LocalizedError {
    case missingClientID
    case cancelled
    case notSignedIn
    case invalidGrant
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientID: return "Google Client ID is not configured."
        case .cancelled: return "Sign-in cancelled."
        case .notSignedIn: return "Not signed in to Google."
        case .invalidGrant: return "Google sign-in expired. Please reconnect."
        case .badResponse(let m): return "Google sign-in failed: \(m)"
        }
    }
}

public enum GoogleAuthConfig {
    /// iOS-type OAuth clients redirect to the reversed client ID scheme.
    public static var reversedClientID: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }
    public static var redirectURI: String { "\(reversedClientID):/oauth2redirect" }
    public static var callbackScheme: String { reversedClientID }
    public static let scopes = [
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/drive.appdata"
    ]
    public static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    public static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
    }
}

@MainActor
@Observable
public final class GoogleAuth {
    public static let shared = GoogleAuth()

    public private(set) var tokens: OAuthTokens?

    public init(loadFromKeychain: Bool = true) {
        tokens = loadFromKeychain ? KeychainStore.load() : nil
    }

    public var isAuthorized: Bool {
        tokens?.accessToken.isEmpty == false
    }

    public func authorize() async throws {
        let clientID = GoogleAuthConfig.clientID
        guard !clientID.isEmpty else { throw GoogleAuthError.missingClientID }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(verifier: verifier)
        let state = UUID().uuidString

        var comps = URLComponents(string: GoogleAuthConfig.authEndpoint)!
        let scopeString = GoogleAuthConfig.scopes.joined(separator: " ")
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopeString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        let code = try await presentAuth(url: comps.url!)

        let response = try await Self.exchangeCode(code, verifier: verifier, clientID: clientID)
        tokens = response
        KeychainStore.save(response)
    }

    public func accessToken() async throws -> String {
        guard var t = tokens else { throw GoogleAuthError.notSignedIn }
        if t.expiresAt.timeIntervalSinceNow < 90, let refresh = t.refreshToken {
            t = try await Self.refreshToken(refresh, clientID: GoogleAuthConfig.clientID)
            tokens = t
            KeychainStore.save(t)
        }
        return t.accessToken
    }

    public func signOut() {
        tokens = nil
        KeychainStore.clear()
    }

    // MARK: - Internals

    private func presentAuth(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(GoogleAuthConfig.callbackScheme)
            ) { @Sendable callbackURL, error in
                // Called by AuthenticationServices on an arbitrary XPC queue, so this
                // closure must NOT inherit this class's @MainActor isolation.
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: GoogleAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: GoogleAuthError.badResponse(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    continuation.resume(throwing: GoogleAuthError.badResponse("bad callback URL"))
                    return
                }
                let items = comps.queryItems ?? []
                if let err = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: GoogleAuthError.badResponse(err))
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleAuthError.badResponse("missing authorization code"))
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = AuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                continuation.resume(throwing: GoogleAuthError.badResponse("could not start auth session"))
            }
        }
    }

    private static func exchangeCode(_ code: String, verifier: String, clientID: String) async throws -> OAuthTokens {
        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": GoogleAuthConfig.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        return try await postToken(body: body)
    }

    private static func refreshToken(_ refreshToken: String, clientID: String) async throws -> OAuthTokens {
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token"
        ]
        var new = try await postToken(body: body)
        new.refreshToken = refreshToken
        return new
    }

    private static func postToken(body: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: GoogleAuthConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = body.map { "\($0.key)=\(Self.percentEncode($0.value))" }.joined(separator: "&")
        request.httpBody = form.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            if msg.contains("invalid_grant") { throw GoogleAuthError.invalidGrant }
            throw GoogleAuthError.badResponse(msg)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
            let scope: String?
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(token.expires_in - 60),
            scopes: token.scope?.components(separatedBy: " ") ?? GoogleAuthConfig.scopes
        )
    }

    // MARK: - PKCE helpers

    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func makeCodeChallenge(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let win = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) { return win }
        if let win = scenes.first?.windows.first { return win }
        if let scene = scenes.first { return UIWindow(windowScene: scene) }
        preconditionFailure("Sign-in needs a visible window")
        #elseif os(macOS)
        return NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        #endif
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}