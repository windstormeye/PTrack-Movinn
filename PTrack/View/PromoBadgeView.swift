//
//  PromoBadgeView.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import UIKit

final class PromoBadgeView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = titleLabel.intrinsicContentSize
        return CGSize(width: labelSize.width + 22, height: 24)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.height / 2
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds.insetBy(dx: -1.5, dy: -1.5),
            cornerRadius: bounds.height / 2 + 1.5
        ).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window == nil {
            layer.removeAnimation(forKey: AnimationKey.shake)
        } else {
            startAnimationsIfNeeded()
        }
    }

    func configure(text: String) {
        titleLabel.text = text
        invalidateIntrinsicContentSize()
        resumeAnimations()
    }

    func resumeAnimations() {
        startAnimationsIfNeeded()
    }

    func stopAnimations() {
        layer.removeAnimation(forKey: AnimationKey.shake)
    }

    private func configureViews() {
        isUserInteractionEnabled = false
        clipsToBounds = false
        transform = CGAffineTransform(rotationAngle: -0.16)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        layer.shadowColor = UIColor(red: 1, green: 0.74, blue: 0.12, alpha: 1).cgColor
        layer.shadowOpacity = 0.72
        layer.shadowRadius = 11
        layer.shadowOffset = .zero

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.colors = [
            UIColor(red: 1.0, green: 0.92, blue: 0.38, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.66, blue: 0.08, alpha: 1).cgColor,
            UIColor(red: 0.93, green: 0.48, blue: 0.02, alpha: 1).cgColor
        ]
        layer.insertSublayer(gradientLayer, at: 0)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .black)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78

        addSubview(titleLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    private func startAnimationsIfNeeded() {
        guard window != nil,
              !UIAccessibility.isReduceMotionEnabled,
              layer.animation(forKey: AnimationKey.shake) == nil else {
            return
        }

        let shakeAnimation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shakeAnimation.values = [0, -2.4, 2.4, -1.5, 1.5, 0, 0]
        shakeAnimation.keyTimes = [0, 0.07, 0.14, 0.23, 0.32, 0.4, 1]
        shakeAnimation.duration = 1.9
        shakeAnimation.beginTime = CACurrentMediaTime() + 0.25
        shakeAnimation.repeatCount = .infinity
        shakeAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]

        layer.add(shakeAnimation, forKey: AnimationKey.shake)
    }
}

private enum AnimationKey {
    static let shake = "promoBadgeShake"
}
