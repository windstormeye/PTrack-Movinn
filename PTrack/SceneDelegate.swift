//
//  SceneDelegate.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let rootViewController = ViewController()
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationController.navigationBar.prefersLargeTitles = true

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        AppAppearanceStore.shared.apply(to: window)
        window.makeKeyAndVisible()
        self.window = window

        if !connectionOptions.urlContexts.isEmpty {
            handleURLContexts(connectionOptions.urlContexts)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        RouteCollectionCloudSyncCoordinator.shared.startIfEnabled()
        notifyPendingSharedRoutesDidChangeIfNeeded()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        RouteCollectionCloudSyncCoordinator.shared.startIfEnabled()
        notifyPendingSharedRoutesDidChangeIfNeeded()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleURLContexts(URLContexts)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

private extension SceneDelegate {
    func notifyPendingSharedRoutesDidChangeIfNeeded() {
        guard SharedRouteImportInbox.hasUnseenRoute || !SharedRouteImportInbox.pendingGPXFileURLs().isEmpty else {
            return
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: SharedRouteImportInbox.pendingRoutesDidChangeNotification,
                object: nil
            )
        }
    }

    func handleURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        let shouldOpenRouteCollection = urlContexts.contains { context in
            isRouteCollectionImportURL(context.url)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: SharedRouteImportInbox.pendingRoutesDidChangeNotification,
                object: nil
            )

            if shouldOpenRouteCollection {
                SharedRouteImportInbox.requestRouteCollectionOpen()
            }
        }
    }

    func isRouteCollectionImportURL(_ url: URL) -> Bool {
        guard url.scheme == "ptrack" else {
            return false
        }

        if url.host == "pj.studio" && url.path == "/routes/import" {
            return true
        }

        return url.host == "routes" && url.path == "/import"
    }
}
