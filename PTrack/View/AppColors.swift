//
//  AppColors.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import UIKit

enum AppColors {
    static let movinnGreen = UIColor(red: 141 / 255, green: 189 / 255, blue: 0, alpha: 1)
    static let stravaOrange = UIColor(red: 252 / 255, green: 76 / 255, blue: 2 / 255, alpha: 1)

    static let solidBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .black : .white
    }

    static let solidForeground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark ? .white : .black
    }

    static let cardBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.2, alpha: 1)
            : UIColor(white: 0.945, alpha: 1)
    }

    static let groupedCardBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.035, alpha: 1)
            : UIColor(white: 0.965, alpha: 1)
    }

    static let toolbarBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.06, alpha: 1)
            : .white
    }

    static let sharePageBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : UIColor(white: 0.94, alpha: 1)
    }

    static let shareActionBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.2, alpha: 1)
            : .white
    }

    static let placeholderBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 0.2, alpha: 1)
            : UIColor(white: 0.91, alpha: 1)
    }

    static func background(alpha: CGFloat) -> UIColor {
        solidBackground.withAlphaComponent(alpha)
    }

    static func foreground(alpha: CGFloat) -> UIColor {
        solidForeground.withAlphaComponent(alpha)
    }

    static func statusIndicatorBorderColor(for traitCollection: UITraitCollection) -> CGColor {
        solidBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.9).cgColor
    }
}

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var titleKey: AppTextKey {
        switch self {
        case .system:
            return .appearanceSystem
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

final class AppAppearanceStore {
    static let shared = AppAppearanceStore()
    static let appearanceDidChangeNotification = Notification.Name("studio.pj.PTrack.appearanceDidChange")

    private let defaults: UserDefaults
    private let key = "studio.pj.PTrack.appAppearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearance: AppAppearanceMode {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let appearance = AppAppearanceMode(rawValue: rawValue) else {
                return .system
            }

            return appearance
        }
        set {
            guard newValue != appearance else {
                return
            }

            defaults.set(newValue.rawValue, forKey: key)
            applyToConnectedWindows()
            NotificationCenter.default.post(name: Self.appearanceDidChangeNotification, object: newValue)
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        appearance.userInterfaceStyle
    }

    func apply(to window: UIWindow) {
        window.overrideUserInterfaceStyle = userInterfaceStyle
    }

    func applyToConnectedWindows() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { window in
                apply(to: window)
                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
    }

    func preferredStatusBarStyle(for traitCollection: UITraitCollection) -> UIStatusBarStyle {
        let userInterfaceStyle = self.userInterfaceStyle == .unspecified
            ? traitCollection.userInterfaceStyle
            : self.userInterfaceStyle

        return userInterfaceStyle == .dark ? .lightContent : .darkContent
    }
}
