//
//  Toast.swift
//  PTrack
//
//  Created by Codex on 2026/6/16.
//

import UIKit

enum Toast {
    private static weak var currentToastView: UIView?
    private static var dismissWorkItem: DispatchWorkItem?

    static func show(
        _ message: String,
        in view: UIView? = nil,
        duration: TimeInterval = 2.0
    ) {
        if Thread.isMainThread {
            showOnMain(message, in: view, duration: duration)
        } else {
            DispatchQueue.main.async {
                showOnMain(message, in: view, duration: duration)
            }
        }
    }

    private static func showOnMain(
        _ message: String,
        in view: UIView?,
        duration: TimeInterval
    ) {
        guard let containerView = view ?? activeWindow else {
            return
        }

        dismissWorkItem?.cancel()
        currentToastView?.removeFromSuperview()

        let toastView = UIView()
        toastView.backgroundColor = AppColors.foreground(alpha: 0.84)
        toastView.layer.cornerRadius = 18
        toastView.layer.masksToBounds = true
        toastView.isUserInteractionEnabled = false
        toastView.alpha = 0
        toastView.transform = CGAffineTransform(translationX: 0, y: 18)
        toastView.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textColor = AppColors.solidBackground
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        toastView.addSubview(messageLabel)
        containerView.addSubview(toastView)

        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -10),

            toastView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 24),
            toastView.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -24),
            toastView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        currentToastView = toastView
        containerView.layoutIfNeeded()

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            toastView.alpha = 1
            toastView.transform = .identity
        }

        let workItem = DispatchWorkItem {
            hide(toastView)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private static func hide(_ toastView: UIView) {
        guard currentToastView === toastView else {
            return
        }

        dismissWorkItem = nil
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            toastView.alpha = 0
            toastView.transform = CGAffineTransform(translationX: 0, y: 12)
        } completion: { _ in
            guard currentToastView === toastView else {
                return
            }

            toastView.removeFromSuperview()
            currentToastView = nil
        }
    }

    private static var activeWindow: UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  scene.activationState == .foregroundActive,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                continue
            }

            return window
        }

        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { !$0.isHidden })
    }
}
