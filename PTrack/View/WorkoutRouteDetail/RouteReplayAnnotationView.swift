//
//  RouteReplayAnnotationView.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import SnapKit
import UIKit

final class RouteReplayAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteReplayAnnotationView"

    private enum Constants {
        static let defaultCenterOffset = CGPoint(x: 0, y: -18)
        static let pinCenterOffset = CGPoint(x: 0, y: -40)
        static let pinEmoji = "📍"
    }

    private let statusContainerView = UIView()
    private let statusLabel = UILabel()
    private let emojiLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureBaseView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBaseView()
    }

    func configure(emoji: String, statusText: String, isFacingLeft: Bool) {
        emojiLabel.text = emoji
        statusLabel.text = statusText
        centerOffset = emoji == Constants.pinEmoji ? Constants.pinCenterOffset : Constants.defaultCenterOffset
        emojiLabel.transform = emoji == Constants.pinEmoji || isFacingLeft ? .identity : CGAffineTransform(scaleX: -1, y: 1)
    }

    private func configureBaseView() {
        bounds = CGRect(x: 0, y: 0, width: 150, height: 80)
        centerOffset = Constants.defaultCenterOffset
        collisionMode = .circle
        displayPriority = .required
        zPriority = .max
        backgroundColor = .clear
        clipsToBounds = false

        statusContainerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        statusContainerView.layer.cornerRadius = 13
        statusContainerView.layer.shadowColor = UIColor.black.cgColor
        statusContainerView.layer.shadowOpacity = 0.14
        statusContainerView.layer.shadowRadius = 5
        statusContainerView.layer.shadowOffset = CGSize(width: 0, height: 2)

        statusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        emojiLabel.font = .systemFont(ofSize: 31)
        emojiLabel.textAlignment = .center
        emojiLabel.layer.shadowColor = UIColor.black.cgColor
        emojiLabel.layer.shadowOpacity = 0.22
        emojiLabel.layer.shadowRadius = 3
        emojiLabel.layer.shadowOffset = CGSize(width: 0, height: 1)

        addSubview(statusContainerView)
        statusContainerView.addSubview(statusLabel)
        addSubview(emojiLabel)

        statusContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.height.equalTo(26)
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        statusLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
        }

        emojiLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
            make.size.equalTo(44)
        }
    }
}
