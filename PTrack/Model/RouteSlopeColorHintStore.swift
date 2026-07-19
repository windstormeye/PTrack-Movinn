//
//  RouteSlopeColorHintStore.swift
//  PTrack
//
//  Created by Codex on 2026/7/19.
//

import Foundation

enum RouteSlopeColorHintStore {
    private static let hasShownKey = "studio.pj.PTrack.routeSlopeColorHint.hasShown"

    /// Returns `true` exactly once for a given UserDefaults domain and records
    /// the consumption before the caller presents the hint.
    @discardableResult
    static func consumeShouldShow(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !defaults.bool(forKey: hasShownKey) else {
            return false
        }

        defaults.set(true, forKey: hasShownKey)
        return true
    }
}
