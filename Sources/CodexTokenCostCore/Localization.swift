import Foundation
import os

public enum AppDisplayLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    public var displayName: String {
        switch self {
        case .zhHans:
            return AppLocalization.text("language.chineseSimplified")
        case .en:
            return AppLocalization.text("language.english")
        }
    }
}

public enum AppLocalization {
    private static let lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var _currentLanguage: AppDisplayLanguage = .zhHans

    public static var currentLanguage: AppDisplayLanguage {
        get { lock.withLock { _currentLanguage } }
        set { lock.withLock { _currentLanguage = newValue } }
    }

    public static func setLanguage(_ language: AppDisplayLanguage) {
        currentLanguage = language
    }

    public static func text(_ key: String) -> String {
        localizedString(for: key)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(for: key)
        return String(format: format, locale: currentLanguage.locale, arguments: arguments)
    }

    public static func localizedString(for key: String) -> String {
        let languageBundle = bundle(for: currentLanguage)
        let value = languageBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        if value == key, currentLanguage != .zhHans {
            let fallbackBundle = bundle(for: .zhHans)
            return fallbackBundle.localizedString(forKey: key, value: key, table: "Localizable")
        }
        return value
    }

    private static func bundle(for language: AppDisplayLanguage) -> Bundle {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let currentDirectoryCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
        if let bundle = Bundle(url: currentDirectoryCandidate) {
            return bundle
        }

        return .main
    }
}
