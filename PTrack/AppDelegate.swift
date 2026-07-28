//
//  AppDelegate.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if #available(iOS 26.0, *) {
            configureMainMenu()
        }

        RouteCollectionCloudSyncCoordinator.shared.startIfEnabled()
        HeatmapRouteCacheStore.shared.prewarmCompleteRouteCache()
        Task { @MainActor in
            _ = ProSubscriptionManager.shared
        }
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        removeAllMainMenuEntries(from: builder)
    }

    @available(iOS 26.0, *)
    private func configureMainMenu() {
        let configuration = UIMainMenuSystem.Configuration()
        configuration.newScenePreference = .removed
        configuration.documentPreference = .removed
        configuration.printingPreference = .removed
        configuration.findingPreference = .removed
        configuration.toolbarPreference = .removed
        configuration.sidebarPreference = .removed
        configuration.inspectorPreference = .removed
        configuration.textFormattingPreference = .removed

        UIMainMenuSystem.shared.setBuildConfiguration(configuration) { [weak self] builder in
            self?.removeAllMainMenuEntries(from: builder)
        }
    }

    private func removeAllMainMenuEntries(from builder: UIMenuBuilder) {
        guard builder.system == UIMenuSystem.main else {
            return
        }

        for identifier in suppressedTopLevelMenuIdentifiers {
            builder.remove(menu: identifier)
        }
        builder.replaceChildren(ofMenu: .root) { _ in [] }
    }

    private var suppressedTopLevelMenuIdentifiers: [UIMenu.Identifier] {
        [.application, .file, .edit, .view, .format, .window, .help]
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        WorkoutRouteSnapshotRenderer.clearMemoryCache()
        WorkoutRoutePathView.clearMemoryCache()
        RouteMediaStore.clearMemoryCache()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}
