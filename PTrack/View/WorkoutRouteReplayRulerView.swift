//
//  WorkoutRouteReplayRulerView.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import SnapKit
import UIKit

final class WorkoutRouteReplayRulerView: UIControl {
    private let profileView = ElevationProfileView()
    private let indicatorView = UIView()
    private let startLabel = UILabel()
    private let endLabel = UILabel()

    private var indicatorCenterXConstraint: Constraint?
    private let horizontalPadding: CGFloat = 2
    private var peakProgress: CGFloat?
    private var isPeakActive = false
    private let peakFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

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

    func configure(totalDistanceText: String, elevationSamples: [RouteElevationSample] = []) {
        startLabel.text = "0km"
        endLabel.text = totalDistanceText
        peakProgress = Self.peakProgress(for: elevationSamples)
        isPeakActive = false
        profileView.configure(samples: elevationSamples)
        profileView.setPeakHighlighted(false, animated: false)
    }

    func setProgress(_ progress: CGFloat, sendsAction: Bool = false) {
        setProgress(progress, sendsAction: sendsAction, allowsPeakCrossing: false)
    }

    private func setProgress(
        _ progress: CGFloat,
        sendsAction: Bool,
        allowsPeakCrossing: Bool
    ) {
        let previousProgress = self.progress
        let targetProgress = min(max(progress, 0), 1)
        let peakHit = peakAdjustedProgress(
            from: previousProgress,
            to: targetProgress,
            allowsSnap: sendsAction,
            allowsCrossing: allowsPeakCrossing
        )

        self.progress = peakHit.progress
        updateProgressLayout(flushLayout: true)
        setPeakActive(peakHit.isPeakPosition, shouldEmitFeedback: sendsAction && peakHit.didHitPeak)

        if sendsAction {
            sendActions(for: .valueChanged)
        }
    }

    private func configureViews() {
        profileView.backgroundColor = .clear

        indicatorView.backgroundColor = UIColor.label.withAlphaComponent(0.58)
        indicatorView.layer.cornerRadius = 1
        indicatorView.isUserInteractionEnabled = false

        startLabel.textColor = .secondaryLabel
        startLabel.font = .preferredFont(forTextStyle: .caption1)

        endLabel.textColor = .secondaryLabel
        endLabel.font = .preferredFont(forTextStyle: .caption1)
        endLabel.textAlignment = .right

        addSubview(profileView)
        addSubview(indicatorView)
        addSubview(startLabel)
        addSubview(endLabel)

        profileView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(70)
        }

        indicatorView.snp.makeConstraints { make in
            make.top.bottom.equalTo(profileView).inset(2)
            indicatorCenterXConstraint = make.centerX.equalTo(profileView.snp.leading).offset(0).constraint
            make.width.equalTo(2)
        }

        startLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.top.equalTo(profileView.snp.bottom).offset(8)
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
        let profileWidth = profileView.bounds.width
        guard profileWidth > 0 else {
            return
        }

        let drawableWidth = max(profileWidth - horizontalPadding * 2, 1)
        indicatorCenterXConstraint?.update(offset: horizontalPadding + drawableWidth * progress)
        if flushLayout {
            layoutIfNeeded()
        }
    }

    private func setPeakActive(_ active: Bool, shouldEmitFeedback: Bool) {
        guard active != isPeakActive else {
            return
        }

        isPeakActive = active
        profileView.setPeakHighlighted(active, animated: true)

        if active, shouldEmitFeedback {
            peakFeedbackGenerator.impactOccurred(intensity: 0.82)
            peakFeedbackGenerator.prepare()
        }
    }

    private func peakAdjustedProgress(
        from previousProgress: CGFloat,
        to targetProgress: CGFloat,
        allowsSnap: Bool,
        allowsCrossing: Bool
    ) -> PeakHit {
        guard allowsSnap,
              let peakProgress,
              profileView.bounds.width > 0 else {
            return PeakHit(progress: targetProgress, isPeakPosition: false, didHitPeak: false)
        }

        let tolerance = peakSinglePositionTolerance()
        let isOnPeakPosition = abs(targetProgress - peakProgress) <= tolerance
        let crossesPeak = allowsCrossing
            && ((previousProgress < peakProgress && targetProgress > peakProgress)
                || (previousProgress > peakProgress && targetProgress < peakProgress))

        guard isOnPeakPosition || crossesPeak else {
            return PeakHit(progress: targetProgress, isPeakPosition: false, didHitPeak: false)
        }

        return PeakHit(progress: peakProgress, isPeakPosition: true, didHitPeak: true)
    }

    private func peakSinglePositionTolerance() -> CGFloat {
        let drawableWidth = max(profileView.bounds.width - horizontalPadding * 2, 1)
        return 1 / drawableWidth
    }

    @objc private func handleProgressGesture(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            peakFeedbackGenerator.prepare()
        }

        let location = recognizer.location(in: profileView)
        let drawableWidth = max(profileView.bounds.width - horizontalPadding * 2, 1)
        let allowsPeakCrossing = recognizer is UIPanGestureRecognizer && recognizer.state == .changed
        setProgress(
            (location.x - horizontalPadding) / drawableWidth,
            sendsAction: true,
            allowsPeakCrossing: allowsPeakCrossing
        )
    }

    private static func peakProgress(for samples: [RouteElevationSample]) -> CGFloat? {
        guard samples.count > 1,
              let totalDistance = samples.last?.distanceMeters,
              totalDistance > 0,
              let peakIndex = samples.indices.max(by: { samples[$0].altitudeMeters < samples[$1].altitudeMeters }) else {
            return nil
        }

        return CGFloat(samples[peakIndex].distanceMeters / totalDistance)
    }
}
