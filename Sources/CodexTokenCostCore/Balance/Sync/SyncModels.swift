import Foundation

/// 同步协议明文 payload（见 `android/docs/sync-protocol.md` §4）。
public struct SyncPayload: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Date
    public var providers: Providers

    public init(version: Int, updatedAt: Date, providers: Providers) {
        self.version = version
        self.updatedAt = updatedAt
        self.providers = providers
    }

    public struct Providers: Codable, Equatable, Sendable {
        public var opencodeGo: GoCredentials?
        public var ollama: CookieCredentials?
        public var codex: TokenCredentials?
        public var deepseek: TokenCredentials?

        public init(
            opencodeGo: GoCredentials? = nil,
            ollama: CookieCredentials? = nil,
            codex: TokenCredentials? = nil,
            deepseek: TokenCredentials? = nil
        ) {
            self.opencodeGo = opencodeGo
            self.ollama = ollama
            self.codex = codex
            self.deepseek = deepseek
        }

        private enum CodingKeys: String, CodingKey {
            case opencodeGo = "opencode_go"
            case ollama, codex, deepseek
        }

        /// 是否有任一凭证可同步。
        public var isEmpty: Bool {
            opencodeGo == nil && ollama == nil && codex == nil && deepseek == nil
        }
    }

    public struct GoCredentials: Codable, Equatable, Sendable {
        public var workspaceID: String?
        public var cookie: String?
        public var apiKey: String?

        public init(workspaceID: String?, cookie: String?, apiKey: String? = nil) {
            self.workspaceID = workspaceID
            self.cookie = cookie
            self.apiKey = apiKey
        }
    }

    public struct CookieCredentials: Codable, Equatable, Sendable {
        public var cookie: String?

        public init(cookie: String?) {
            self.cookie = cookie
        }
    }

    public struct TokenCredentials: Codable, Equatable, Sendable {
        public var authToken: String?
        public var apiKey: String?

        public init(authToken: String? = nil, apiKey: String? = nil) {
            self.authToken = authToken
            self.apiKey = apiKey
        }
    }
}
