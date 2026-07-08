//
//  DemoModeViewController.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import UIKit

final class DemoModeViewController: UIViewController {
    private let workouts = DemoModeSampleData.workouts
    private let exitFloatingButton = DemoModeExitFloatingButton()
    private lazy var demoNavigationController: UINavigationController = {
        let homeViewController = DemoModeHomeViewController(workouts: workouts)
        let navigationController = UINavigationController(rootViewController: homeViewController)
        navigationController.navigationBar.prefersLargeTitles = true
        return navigationController
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = .systemBackground
        configureChildNavigationController()
        configureExitFloatingButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        exitFloatingButton.placeIfNeeded(in: view.bounds, safeAreaInsets: view.safeAreaInsets)
        view.bringSubviewToFront(exitFloatingButton)
    }

    private func configureChildNavigationController() {
        addChild(demoNavigationController)
        view.addSubview(demoNavigationController.view)
        demoNavigationController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            demoNavigationController.view.topAnchor.constraint(equalTo: view.topAnchor),
            demoNavigationController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            demoNavigationController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            demoNavigationController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        demoNavigationController.didMove(toParent: self)
    }

    private func configureExitFloatingButton() {
        exitFloatingButton.addTarget(self, action: #selector(handleExitButtonTap), for: .primaryActionTriggered)
        view.addSubview(exitFloatingButton)
    }

    @objc private func handleExitButtonTap() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.demoModeExitTitle),
            message: AppLocalization.text(.demoModeExitMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.cancel), style: .cancel))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.demoModeExit),
            style: .destructive
        ) { [weak self] _ in
            DemoModeStore.setActive(false)
            self?.dismiss(animated: true)
        })

        topMostViewController(from: demoNavigationController).present(alertController, animated: true)
    }

    private func topMostViewController(from viewController: UIViewController) -> UIViewController {
        if let presentedViewController = viewController.presentedViewController {
            return topMostViewController(from: presentedViewController)
        }

        if let navigationController = viewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return topMostViewController(from: visibleViewController)
        }

        return viewController
    }
}
