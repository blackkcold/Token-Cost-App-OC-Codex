import Foundation

public enum BalanceRelayEndpoint {
    public static let infoPlistKey = "RelayBaseURL"
    public static let environmentKey = "RELAY_BASE_URL"

    public static func configuredURL(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
#if DEBUG
        if let value = environment[environmentKey], let url = validatedURL(value, allowInsecure: true) {
            return url
        }
#endif
        guard let value = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        return validatedURL(value, allowInsecure: false)
    }

    public static func validatedURL(_ value: String, allowInsecure: Bool) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host != nil,
              url.query == nil,
              url.fragment == nil
        else { return nil }
        if url.scheme == "https" {
            return url
        }
        if allowInsecure, url.scheme == "http" {
            return url
        }
        return nil
    }

    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ url: URL) -> String {
        url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
