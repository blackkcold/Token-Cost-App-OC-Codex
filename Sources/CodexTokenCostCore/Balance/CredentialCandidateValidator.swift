import Foundation

public enum CredentialCandidateValidation: Equatable, Sendable {
    case valid
    case invalid
    case unavailable
}

public protocol CredentialCandidateValidating: Sendable {
    func validateGo(workspaceID: String, cookie: String) async -> CredentialCandidateValidation
    func validateOllama(cookie: String) async -> CredentialCandidateValidation
}

public protocol BrowserCredentialCandidateProviding: Sendable {
    func goCandidates() -> [BrowserCookieExtractor.GoCredentialCandidate]
    func ollamaCandidates() -> [BrowserCookieExtractor.OllamaCookieCandidate]
}

public struct LiveBrowserCredentialCandidateProvider: BrowserCredentialCandidateProviding {
    public init() {}

    public func goCandidates() -> [BrowserCookieExtractor.GoCredentialCandidate] {
        BrowserCookieExtractor.credentialCandidates()
    }

    public func ollamaCandidates() -> [BrowserCookieExtractor.OllamaCookieCandidate] {
        BrowserCookieExtractor.ollamaCookieCandidates()
    }
}

public struct LiveCredentialCandidateValidator: CredentialCandidateValidating {
    public init() {}

    public func validateGo(workspaceID: String, cookie: String) async -> CredentialCandidateValidation {
        let baseURL = URL(string: "https://opencode.ai/workspace")!
        let url = baseURL
            .appendingPathComponent(workspaceID, isDirectory: true)
            .appendingPathComponent("go", isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(normalizedGoCookie(cookie), forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        return await validate(request: request) { data, response in
            if Self.isAuthenticationRedirect(response) || [401, 403].contains(response.statusCode) {
                return .invalid
            }
            guard response.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return response.statusCode >= 500 ? .unavailable : .invalid
            }
            if html.contains("rollingUsage") || html.contains("weeklyUsage") || html.contains("monthlyUsage") {
                return .valid
            }
            return Self.looksLikeLoginPage(html) ? .invalid : .invalid
        }
    }

    public func validateOllama(cookie: String) async -> CredentialCandidateValidation {
        guard let url = URL(string: "https://ollama.com/settings") else {
            return .unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        return await validate(request: request) { data, response in
            if Self.isAuthenticationRedirect(response) || [401, 403].contains(response.statusCode) {
                return .invalid
            }
            guard response.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return response.statusCode >= 500 ? .unavailable : .invalid
            }
            return Self.looksLikeLoginPage(html) ? .invalid : .valid
        }
    }

    private func validate(
        request: URLRequest,
        classify: (Data, HTTPURLResponse) -> CredentialCandidateValidation
    ) async -> CredentialCandidateValidation {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unavailable
            }
            return classify(data, httpResponse)
        } catch {
            return .unavailable
        }
    }

    private func normalizedGoCookie(_ cookie: String) -> String {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("auth=") ? trimmed : "auth=\(trimmed)"
    }

    private static func isAuthenticationRedirect(_ response: HTTPURLResponse) -> Bool {
        guard let url = response.url else { return false }
        let path = url.path.lowercased()
        return path.contains("/login") || path.contains("/signin") || path.contains("/auth")
    }

    private static func looksLikeLoginPage(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        return lowercased.contains("sign in") || lowercased.contains("log in")
    }

    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
}

enum CredentialCandidateResolver {
    enum Resolution<Candidate: Sendable>: Sendable {
        case valid(Candidate)
        case exhausted
        case unavailable
    }

    static func firstValid<Candidate: Sendable>(
        _ candidates: [Candidate],
        validate: (Candidate) async -> CredentialCandidateValidation
    ) async -> Resolution<Candidate> {
        for candidate in candidates {
            switch await validate(candidate) {
            case .valid:
                return .valid(candidate)
            case .invalid:
                continue
            case .unavailable:
                return .unavailable
            }
        }
        return .exhausted
    }
}
