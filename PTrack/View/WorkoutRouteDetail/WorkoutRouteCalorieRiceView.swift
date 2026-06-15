//
//  WorkoutRouteCalorieRiceView.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/15.
//

import SnapKit
import UIKit

final class WorkoutRouteCalorieRiceView: UIView {
    private let titleLabel = UILabel()
    private let gravityMotionEffect = GravityTiltMotionEffect()
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private lazy var animator = UIDynamicAnimator(referenceView: self)
    private var gravityBehavior: UIGravityBehavior?
    private var collisionBehavior: UICollisionBehavior?
    private var itemBehavior: UIDynamicItemBehavior?
    private var riceBodies: [RiceBodyView] = []
    private var needsInitialRiceLayout = false
    private var previousBoundsSize: CGSize = .zero
    private var tiltGravityX: CGFloat = 0
    private var tiltGravityY: CGFloat = 0.2
    private var calibratedViewerOffset: UIOffset?
    private var lastSideImpactTime: CFTimeInterval = 0

    private let bodySize = CGSize(width: 24, height: 18)
    private let gravityMagnitude: CGFloat = 1.85
    private let horizontalGravityMultiplier: CGFloat = 1.45
    private let verticalGravityMultiplier: CGFloat = 1.65
    private let restingVerticalGravity: CGFloat = 0.18
    private let tiltDeadZone: CGFloat = 0.04
    private let sideImpactVelocityThreshold: CGFloat = 85
    private let sideImpactMinimumInterval: CFTimeInterval = 0.14

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.size != .zero else {
            return
        }

        if needsInitialRiceLayout || previousBoundsSize != bounds.size {
            previousBoundsSize = bounds.size
            layoutRiceLabels()
            resetPhysics()
            needsInitialRiceLayout = false
        }
    }

    func configure(caloriesKilocalories: Double) {
        titleLabel.text = AppLocalization.format(.burnedCaloriesFormat, caloriesKilocalories)
        calibratedViewerOffset = nil
        rebuildRiceLabels(count: riceBowlCount(for: caloriesKilocalories))
    }

    private func configureView() {
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = UIColor(
            red: 0.945,
            green: 0.948,
            blue: 0.938,
            alpha: 0.96
        )
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.white.withAlphaComponent(0.62).cgColor
        layer.borderWidth = 0.8

        gravityMotionEffect.onOffsetChanged = { [weak self] viewerOffset in
            self?.updateGravity(for: viewerOffset)
        }
        addMotionEffect(gravityMotionEffect)
        impactFeedbackGenerator.prepare()

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.black.withAlphaComponent(0.58)
        titleLabel.textAlignment = .right
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().inset(12)
        }
    }

    private func rebuildRiceLabels(count: Int) {
        animator.removeAllBehaviors()
        gravityBehavior = nil
        collisionBehavior = nil
        itemBehavior = nil

        riceBodies.forEach { $0.removeFromSuperview() }
        riceBodies = (0..<count).map { _ in
            let body = RiceBodyView(bodySize: bodySize)
            addSubview(body)
            return body
        }

        bringSubviewToFront(titleLabel)
        needsInitialRiceLayout = true
        setNeedsLayout()
    }

    private func riceBowlCount(for caloriesKilocalories: Double) -> Int {
        let rawCount = Int((caloriesKilocalories / 200).rounded())
        return min(max(rawCount, 1), 24)
    }

    private func layoutRiceLabels() {
        let clusterCenterX = bounds.width * 0.75
        let baseY = bounds.height - bodySize.height - 12
        let columnSpacing = bodySize.width * 0.66
        let rowSpacing = bodySize.height * 0.74

        for (index, body) in riceBodies.enumerated() {
            let row = index / 6
            let column = index % 6
            let remainingCount = riceBodies.count - row * 6
            let rowCount = min(6, remainingCount)
            let rowWidth = CGFloat(rowCount - 1) * columnSpacing
            let jitterX: CGFloat = index.isMultiple(of: 2) ? -2 : 2
            let x = clusterCenterX - rowWidth / 2 + CGFloat(column) * columnSpacing + jitterX
            let y = baseY - CGFloat(row) * rowSpacing

            body.frame = CGRect(
                x: min(max(x, 8), max(bounds.width - bodySize.width - 8, 8)),
                y: min(max(y, 30), max(bounds.height - bodySize.height - 8, 30)),
                width: bodySize.width,
                height: bodySize.height
            )
        }
    }

    private func resetPhysics() {
        animator.removeAllBehaviors()

        guard !riceBodies.isEmpty, bounds.size != .zero else {
            return
        }

        let gravity = UIGravityBehavior(items: riceBodies)
        gravity.gravityDirection = normalizedGravityDirection()
        gravity.magnitude = gravityMagnitude

        let collision = UICollisionBehavior(items: riceBodies)
        collision.translatesReferenceBoundsIntoBoundary = true

        let item = UIDynamicItemBehavior(items: riceBodies)
        item.elasticity = 0.34
        item.friction = 0.04
        item.density = 0.8
        item.resistance = 0.12
        item.angularResistance = 0.18
        item.allowsRotation = true
        item.action = { [weak self, weak item] in
            guard let item else {
                return
            }

            self?.handleSideImpacts(itemBehavior: item)
        }

        for (index, body) in riceBodies.enumerated() {
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            item.addLinearVelocity(CGPoint(x: direction * 8, y: -16), for: body)
            item.addAngularVelocity(direction * 0.8, for: body)
        }

        animator.addBehavior(gravity)
        animator.addBehavior(collision)
        animator.addBehavior(item)

        gravityBehavior = gravity
        collisionBehavior = collision
        itemBehavior = item
    }

    private func updateGravity(for viewerOffset: UIOffset) {
        if calibratedViewerOffset == nil {
            calibratedViewerOffset = viewerOffset
        }

        let calibratedOffset = calibratedViewerOffset ?? .zero
        let horizontalDelta = easedTilt(deadZone(viewerOffset.horizontal - calibratedOffset.horizontal))
        let verticalDelta = easedTilt(deadZone(viewerOffset.vertical - calibratedOffset.vertical))

        tiltGravityX = min(max(horizontalDelta, -1), 1) * horizontalGravityMultiplier
        tiltGravityY = restingVerticalGravity + min(max(verticalDelta, -1), 1) * verticalGravityMultiplier
        gravityBehavior?.gravityDirection = normalizedGravityDirection()
        gravityBehavior?.magnitude = gravityMagnitude
    }

    private func normalizedGravityDirection() -> CGVector {
        let length = max(hypot(tiltGravityX, tiltGravityY), 0.01)
        return CGVector(dx: tiltGravityX / length, dy: tiltGravityY / length)
    }

    private func deadZone(_ value: CGFloat) -> CGFloat {
        abs(value) < tiltDeadZone ? 0 : value
    }

    private func easedTilt(_ value: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        let magnitude = min(abs(value), 1)
        return sign * pow(magnitude, 1.35)
    }

    private func handleSideImpacts(itemBehavior: UIDynamicItemBehavior) {
        guard window != nil, bounds.width > 0 else {
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastSideImpactTime >= sideImpactMinimumInterval else {
            return
        }

        let didHitSide = riceBodies.contains { body in
            let velocityX = itemBehavior.linearVelocity(for: body).x
            let hitLeft = body.frame.minX <= 1 && velocityX < -sideImpactVelocityThreshold
            let hitRight = body.frame.maxX >= bounds.width - 1 && velocityX > sideImpactVelocityThreshold
            return hitLeft || hitRight
        }

        guard didHitSide else {
            return
        }

        lastSideImpactTime = now
        impactFeedbackGenerator.impactOccurred(intensity: 0.55)
        impactFeedbackGenerator.prepare()
    }
}

private final class GravityTiltMotionEffect: UIMotionEffect {
    var onOffsetChanged: ((UIOffset) -> Void)?

    override func keyPathsAndRelativeValues(forViewerOffset viewerOffset: UIOffset) -> [String: Any]? {
        onOffsetChanged?(viewerOffset)
        return [
            "center.x": 0,
            "center.y": 0
        ]
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let effect = GravityTiltMotionEffect()
        effect.onOffsetChanged = onOffsetChanged
        return effect
    }
}

private final class RiceBodyView: UIView {
    private let emojiLabel = UILabel()

    init(bodySize: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: bodySize))
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emojiLabel.frame = CGRect(
            x: (bounds.width - 44) / 2,
            y: -20,
            width: 44,
            height: 44
        )
    }

    private func configureView() {
        clipsToBounds = false
        backgroundColor = .clear

        emojiLabel.text = "🍚"
        emojiLabel.font = .systemFont(ofSize: 34)
        emojiLabel.textAlignment = .center
        emojiLabel.isUserInteractionEnabled = false
        addSubview(emojiLabel)
    }
}
