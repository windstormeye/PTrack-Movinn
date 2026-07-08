//
//  DemoModeCoordinator.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import UIKit

enum DemoModeCoordinator {
    @MainActor
    static func activate(from presenter: UIViewController) {
        DemoModeStore.setActive(true)
        present(from: presenter, animated: true)
    }

    @MainActor
    static func presentIfNeeded(in window: UIWindow, animated: Bool = false) {
        guard DemoModeStore.isActive else {
            return
        }

        present(from: window.rootViewController, animated: animated)
    }

    @MainActor
    static func present(from presenter: UIViewController?, animated: Bool) {
        guard let presenter else {
            return
        }

        let topViewController = topMostViewController(from: presenter)
        guard !containsDemoModeViewController(topViewController) else {
            return
        }

        let demoViewController = DemoModeViewController()
        demoViewController.modalPresentationStyle = .fullScreen
        demoViewController.modalTransitionStyle = .coverVertical
        topViewController.present(demoViewController, animated: animated)
    }

    @MainActor
    private static func topMostViewController(from rootViewController: UIViewController) -> UIViewController {
        if let presentedViewController = rootViewController.presentedViewController {
            return topMostViewController(from: presentedViewController)
        }

        if let navigationController = rootViewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topMostViewController(from: visibleViewController)
        }

        if let tabBarController = rootViewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return topMostViewController(from: selectedViewController)
        }

        return rootViewController
    }

    private static func containsDemoModeViewController(_ viewController: UIViewController) -> Bool {
        if viewController is DemoModeViewController {
            return true
        }

        if let navigationController = viewController as? UINavigationController {
            return navigationController.viewControllers.contains { $0 is DemoModeViewController }
        }

        return false
    }
}
