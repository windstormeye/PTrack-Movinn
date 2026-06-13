//
//  WorkoutRouteReplayRulerView.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import SnapKit
import UIKit

final class WorkoutRouteReplayRulerView: UIControl {
    private let trackView = UIView()
    private let progressView = UIView()
    private let thumbView = UIView()
    private let startLabel = UILabel()
    private let endLabel = UILabel()

    private var progressWidthConstraint: Constraint?
    private var thumbCenterXConstraint: Constraint?

    private(set) var progress: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateProgressLayout(flushLayout: false)
    }

    func configure(totalDistanceText: String) {
        startLabel.text = "0km"
        endLabel.text = totalDistanceText
    }

    func setProgress(_ progress: CGFloat, sendsAction: Bool = false) {
        self.progress = min(max(progress, 0), 1)
        updateProgressLayout(flushLayout: true)

        if sendsAction {
            sendActions(for: .valueChanged)
        }
    }

    private func configureViews() {
        trackView.backgroundColor = UIColor.label.withAlphaComponent(0.12)
        trackView.layer.cornerRadius = 2

        progressView.backgroundColor = .label
        progressView.layer.cornerRadius = 2

        thumbView.backgroundColor = .label
        thumbView.layer.cornerRadius = 8

        startLabel.textColor = .secondaryLabel
        startLabel.font = .preferredFont(forTextStyle: .caption1)

        endLabel.textColor = .secondaryLabel
        endLabel.font = .preferredFont(forTextStyle: .caption1)
        endLabel.textAlignment = .right

        addSubview(trackView)
        trackView.addSubview(progressView)
        addSubview(thumbView)
        addSubview(startLabel)
        addSubview(endLabel)

        trackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(4)
        }

        progressView.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview()
            progressWidthConstraint = make.width.equalTo(0).constraint
        }

        thumbView.snp.makeConstraints { make in
            make.centerY.equalTo(trackView)
            thumbCenterXConstraint = make.centerX.equalTo(trackView.snp.leading).offset(0).constraint
            make.size.equalTo(16)
        }

        startLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.top.equalTo(trackView.snp.bottom).offset(11)
        }

        endLabel.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview()
            make.centerY.equalTo(startLabel)
            make.leading.greaterThanOrEqualTo(startLabel.snp.trailing).offset(12)
        }

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleProgressGesture(_:)))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleProgressGesture(_:)))
        addGestureRecognizer(panGesture)
        addGestureRecognizer(tapGesture)
    }

    private func updateProgressLayout(flushLayout: Bool) {
        let trackWidth = trackView.bounds.width
        guard trackWidth > 0 else {
            return
        }

        let progressX = trackWidth * progress
        progressWidthConstraint?.update(offset: progressX)
        thumbCenterXConstraint?.update(offset: progressX)
        if flushLayout {
            layoutIfNeeded()
        }
    }

    @objc private func handleProgressGesture(_ recognizer: UIGestureRecognizer) {
        let location = recognizer.location(in: trackView)
        let trackWidth = max(trackView.bounds.width, 1)
        setProgress(location.x / trackWidth, sendsAction: true)
    }
}
