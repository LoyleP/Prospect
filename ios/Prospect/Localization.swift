// Localization.swift
// The app's language: English by default, switchable in the app (onboarding and profile), applied live.
// Strings live in Localizable.xcstrings, keyed by their English text. `L("…")` looks one up in the chosen
// language, so it also works for Strings that SwiftUI would never localize on its own (button titles passed to
// custom views, error messages, notifications, CSV headers).
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, fr

    var id: String { rawValue }

    /// Written in its own language, so it can always be recognised.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        }
    }

    var locale: Locale { Locale(identifier: rawValue == "fr" ? "fr_FR" : "en_US") }

    /// The folder in the app bundle that holds this language's strings.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

enum Language {
    private static let key = "appLanguage"

    /// Read often (every `L()`), written rarely (the picker).
    nonisolated(unsafe) private static var cached: AppLanguage?

    /// English unless the person picked another language.
    static var current: AppLanguage {
        get {
            if let cached { return cached }
            let saved = UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init(rawValue:)) ?? .en
            cached = saved
            return saved
        }
        set {
            cached = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

extension Language {
    /// "50 %" in French (a space before the sign), "50%" in English.
    static func percent(_ value: Int) -> String { current == .fr ? "\(value) %" : "\(value)%" }
    /// "9 h" in French, "9:00" in English.
    static func hour(_ value: Int) -> String { current == .fr ? "\(value) h" : "\(value):00" }
}

/// A formatter (or anything costly to build) kept once per language, so it follows the language the person picks.
final class PerLanguage<Value>: @unchecked Sendable {
    private var values: [AppLanguage: Value] = [:]
    private let lock = NSLock()
    private let make: (AppLanguage) -> Value

    init(_ make: @escaping (AppLanguage) -> Value) { self.make = make }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        let language = Language.current
        if let existing = values[language] { return existing }
        let created = make(language)
        values[language] = created
        return created
    }
}

/// "prospect" or "prospects" by the language's own rule (French counts 0 as singular, English does not).
func prospectsNoun(_ count: Int) -> String {
    let singular = Language.current == .fr ? count <= 1 : count == 1
    return singular ? L("prospect") : L("prospects")
}

/// The string for `key` in the app's current language. Falls back to the key itself (the English text).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Language.current.bundle, locale: Language.current.locale)
}
