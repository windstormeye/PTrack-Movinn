//
//  AppMapDisplayStyle.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import Foundation
import UIKit

enum AppMapDisplayStyle: String, CaseIterable {
    case appDefault
    case standard
    case satellite
    case dark

    static let menuCases: [AppMapDisplayStyle] = [.dark, .satellite, .standard, .appDefault]

    var title: String {
        switch self {
        case .appDefault:
            return "默认"
        case .standard:
            return "标准"
        case .satellite:
            return "卫星"
        case .dark:
            return "暗色"
        }
    }
}

final class AppMapDisplayStyleStore {
    static let shared = AppMapDisplayStyleStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func heatmapStyle() -> AppMapDisplayStyle {
        style(forKey: Keys.heatmapStyle)
    }

    func setHeatmapStyle(_ style: AppMapDisplayStyle) {
        setStyle(style, forKey: Keys.heatmapStyle)
    }

    func routeDetailStyle() -> AppMapDisplayStyle {
        style(forKey: Keys.routeDetailStyle)
    }

    func setRouteDetailStyle(_ style: AppMapDisplayStyle) {
        setStyle(style, forKey: Keys.routeDetailStyle)
    }

    private func style(forKey key: String) -> AppMapDisplayStyle {
        guard let rawValue = defaults.string(forKey: key),
              let style = AppMapDisplayStyle(rawValue: rawValue) else {
            return .appDefault
        }

        return style
    }

    private func setStyle(_ style: AppMapDisplayStyle, forKey key: String) {
        defaults.set(style.rawValue, forKey: key)
    }

    private enum Keys {
        static let heatmapStyle = "studio.pj.PTrack.mapStyle.heatmap"
        static let routeDetailStyle = "studio.pj.PTrack.mapStyle.routeDetail"
    }
}
