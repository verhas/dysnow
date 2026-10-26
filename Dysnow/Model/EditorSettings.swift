import AppKit

/// How the text is shown, and how the app looks: kept in the settings.
enum EditorSettings {
    static let fontKey = "editor.font"
    static let sizeKey = "editor.fontSize"
    static let themeKey = "appearance.theme"
    static let defaultSize = 15.0

    /// The editor's font: a family, or the system's when empty or gone.
    static func font(family: String, size: Double) -> NSFont {
        let size = CGFloat(size > 0 ? size : defaultSize)
        guard !family.isEmpty,
              let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
        else { return .systemFont(ofSize: size) }
        return font
    }

    /// The editor's font, as the settings have it now.
    static var font: NSFont {
        let defaults = UserDefaults.standard
        return font(family: defaults.string(forKey: fontKey) ?? "", size: defaults.double(forKey: sizeKey))
    }

    /// The families installed, by name.
    static var families: [String] {
        NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Makes the app look as the theme in the settings says.
    @MainActor
    static func applyTheme() {
        let theme = UserDefaults.standard.string(forKey: themeKey).flatMap(Theme.init(rawValue:)) ?? .system
        NSApp.appearance = theme.appearance
    }
}
