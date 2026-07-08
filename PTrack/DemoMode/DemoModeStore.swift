//
//  DemoModeStore.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import Foundation

enum DemoModeStore {
    static let didChangeNotification = Notification.Name("studio.pj.PTrack.demoModeDidChange")

    private static let isActiveKey = "studio.pj.PTrack.demoMode.isActive"
    private static let primaryDataSourceSelectedKey = "studio.pj.PTrack.demoMode.primaryDataSourceSelected"

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: isActiveKey)
    }

    static var hasSelectedPrimaryDataSource: Bool {
        UserDefaults.standard.bool(forKey: primaryDataSourceSelectedKey)
    }

    static func setActive(_ isActive: Bool) {
        guard self.isActive != isActive else {
            return
        }

        UserDefaults.standard.set(isActive, forKey: isActiveKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: isActive)
    }

    static func markPrimaryDataSourceSelected() {
        guard !hasSelectedPrimaryDataSource else {
            return
        }

        UserDefaults.standard.set(true, forKey: primaryDataSourceSelectedKey)
        UserDefaults.standard.synchronize()
    }
}
