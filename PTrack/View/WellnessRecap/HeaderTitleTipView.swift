//
//  HeaderTitleTipView.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  首次引导气泡:告诉用户点击首页标题可以查看指导建议。
//  只出现一次(记录在 UserDefaults,卸载重装才会重来)。

import SnapKit
import UIKit

final class HeaderTitleTipView: UIView {
    private enum Metrics {
        static let arrowWidth: CGFloat = 16
        static let arrowHeight: CGFloat = 8
        static let cornerRadius: CGFloat = 12
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 10
    }

    /// 调整引导文案或时机时递增版本号,让气泡重新出现一次。
    private static let shownKey = "wellnessRecap.headerTipShown.v2"

    static var hasShown: Bool {
        UserDefaults.standard.bool(forKey: shownKey)
    }

    private static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }

    private let bubbleLayer = CAShapeLayer()
    private let messageLabel = UILabel()
    private var arrowCenterX: CGFloat = 0

    private init(message: String) {
        super.init(frame: .zero)
        backgroundColor = .clear

        bubbleLayer.fillColor = AppColors.solidForeground.cgColor
        bubbleLayer.shadowColor = UIColor.black.cgColor
        bubbleLayer.shadowOpacity = 0.18
        bubbleLayer.shadowRadius = 10
        bubbleLayer.shadowOffset = CGSize(width: 0, height: 4)
        layer.addSublayer(bubbleLayer)

        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = AppColors.solidBackground
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)

        messageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Metrics.horizontalPadding)
            make.top.equalToSuperview().offset(Metrics.arrowHeight + Metrics.verticalPadding)
            make.bottom.equalToSuperview().inset(Metrics.verticalPadding)
        }

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBubblePath()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        bubbleLayer.fillColor = AppColors.solidForeground.cgColor
    }

    private func updateBubblePath() {
        let bodyRect = CGRect(
            x: 0,
            y: Metrics.arrowHeight,
            width: bounds.width,
            height: max(bounds.height - Metrics.arrowHeight, 0)
        )
        let path = UIBezierPath(roundedRect: bodyRect, cornerRadius: Metrics.cornerRadius)

        let apexX = min(max(arrowCenterX, Metrics.cornerRadius + Metrics.arrowWidth), bounds.width - Metrics.cornerRadius - Metrics.arrowWidth)
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: apexX - Metrics.arrowWidth / 2, y: Metrics.arrowHeight))
        arrow.addLine(to: CGPoint(x: apexX, y: 0))
        arrow.addLine(to: CGPoint(x: apexX + Metrics.arrowWidth / 2, y: Metrics.arrowHeight))
        arrow.close()
        path.append(arrow)

        bubbleLayer.path = path.cgPath
        bubbleLayer.frame = bounds
    }

    @objc private func handleTap() {
        dismiss()
    }

    /// 仅在用户点击气泡或点击标题后调用,不会自动消失。
    func dismiss() {
        guard superview != nil else {
            return
        }
        UIView.animate(
            withDuration: 0.22,
            animations: {
                self.alpha = 0
                self.transform = CGAffineTransform(translationX: 0, y: -6)
            },
            completion: { _ in
                self.removeFromSuperview()
            }
        )
    }

    /// 在 `anchorView` 下方展示一次引导气泡;已展示过则什么都不做。
    @discardableResult
    static func showOnce(
        in containerView: UIView,
        below anchorView: UIView,
        message: String
    ) -> HeaderTitleTipView? {
        guard !hasShown else {
            return nil
        }

        let tipView = HeaderTitleTipView(message: message)
        containerView.addSubview(tipView)

        let anchorFrame = anchorView.convert(anchorView.bounds, to: containerView)
        tipView.snp.makeConstraints { make in
            make.top.equalTo(containerView.snp.top).offset(anchorFrame.maxY + 4)
            make.leading.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualToSuperview().inset(16)
            make.width.lessThanOrEqualTo(300)
        }
        containerView.layoutIfNeeded()
        // 气泡确实布局出来了才算展示过,避免异常情况下白白消耗掉这一次引导。
        markShown()
        // 箭头指向锚点中心。
        tipView.arrowCenterX = anchorFrame.midX - tipView.frame.minX
        tipView.setNeedsLayout()

        tipView.alpha = 0
        tipView.transform = CGAffineTransform(translationX: 0, y: -6)
        UIView.animate(withDuration: 0.28, delay: 0.15, options: [.curveEaseOut]) {
            tipView.alpha = 1
            tipView.transform = .identity
        }
        return tipView
    }
}
