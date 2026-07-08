//
//  DemoModeExitFloatingButton.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import UIKit

final class DemoModeExitFloatingButton: UIControl {
    private let iconView = UIImageView()
    private var hasPlacedInitialFrame = false
    private let buttonSide: CGFloat = 46

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func placeIfNeeded(in bounds: CGRect, safeAreaInsets: UIEdgeInsets) {
        if !hasPlacedInitialFrame {
            hasPlacedInitialFrame = true
            frame = CGRect(
                x: bounds.maxX - safeAreaInsets.right - buttonSide - 18,
                y: bounds.minY + safeAreaInsets.top + 78,
                width: buttonSide,
                height: buttonSide
            )
        }

        frame = clampedFrame(frame, in: bounds, safeAreaInsets: safeAreaInsets)
    }

    private func configureView() {
        backgroundColor = .systemRed
        layer.cornerRadius = buttonSide / 2
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)

        iconView.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        )
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false

        addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 19),
            iconView.heightAnchor.constraint(equalToConstant: 19)
        ])

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        accessibilityLabel = AppLocalization.text(.demoModeExit)
        accessibilityTraits.insert(.button)
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .primaryActionTriggered)
        return true
    }

    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else {
            return
        }

        sendActions(for: .primaryActionTriggered)
    }

    @objc private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let superview else {
            return
        }

        let translation = gestureRecognizer.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gestureRecognizer.setTranslation(.zero, in: superview)
        frame = clampedFrame(frame, in: superview.bounds, safeAreaInsets: superview.safeAreaInsets)
    }

    private func clampedFrame(
        _ frame: CGRect,
        in bounds: CGRect,
        safeAreaInsets: UIEdgeInsets
    ) -> CGRect {
        let margin: CGFloat = 10
        let minX = bounds.minX + safeAreaInsets.left + margin
        let maxX = bounds.maxX - safeAreaInsets.right - margin - frame.width
        let minY = bounds.minY + safeAreaInsets.top + margin
        let maxY = bounds.maxY - safeAreaInsets.bottom - margin - frame.height
        return CGRect(
            x: min(max(frame.minX, minX), max(minX, maxX)),
            y: min(max(frame.minY, minY), max(minY, maxY)),
            width: frame.width,
            height: frame.height
        )
    }
}
