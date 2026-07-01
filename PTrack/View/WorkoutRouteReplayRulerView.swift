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

    private struct SnapPoint {
        let progress: CGFloat
        let markerKind: PeakMarkerKind
    }

    private var indicatorCenterXConstraint: Constraint?
    private let horizontalPadding: CGFloat = 2
    private var snapPoints: [SnapPoint] = []
    private var activeSnapProgress: CGFloat?
    private var activeMarkerKind: PeakMarkerKind?
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
        snapPoints = Self.snapPoints(for: elevationSamples)
        activeSnapProgress = nil
        activeMarkerKind = nil
        profileView.configure(samples: elevationSamples)
        profileView.setHighlightedPeak(nil, animated: false)
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
        setActiveSnap(
            progress: peakHit.snapProgress,
            markerKind: peakHit.markerKind,
            shouldEmitFeedback: sendsAction && peakHit.didHitPeak
        )

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
        insertSubview(indicatorView, belowSubview: profileView)
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

    private func setActiveSnap(
        progress: CGFloat?,
        markerKind: PeakMarkerKind?,
        shouldEmitFeedback: Bool
    ) {
        let didChangeSnap = activeSnapProgress != progress
        activeSnapProgress = progress

        if markerKind != activeMarkerKind {
            activeMarkerKind = markerKind
            profileView.setHighlightedPeak(markerKind, animated: true)
        }

        if progress != nil, didChangeSnap, shouldEmitFeedback {
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
              !snapPoints.isEmpty,
              profileView.bounds.width > 0 else {
            return PeakHit(progress: targetProgress, snapProgress: nil, markerKind: nil, didHitPeak: false)
        }

        let tolerance = peakSinglePositionTolerance()
        let hitSnapPoints = snapPoints.filter { snapPoint in
            isSnapPoint(
                snapPoint.progress,
                hitFrom: previousProgress,
                to: targetProgress,
                tolerance: tolerance,
                allowsCrossing: allowsCrossing
            )
        }
        guard let snapPoint = hitSnapPoints.min(by: { lhs, rhs in
            abs(lhs.progress - targetProgress) < abs(rhs.progress - targetProgress)
        }) else {
            return PeakHit(progress: targetProgress, snapProgress: nil, markerKind: nil, didHitPeak: false)
        }

        return PeakHit(
            progress: snapPoint.progress,
            snapProgress: snapPoint.progress,
            markerKind: snapPoint.markerKind,
            didHitPeak: true
        )
    }

    private func isSnapPoint(
        _ snapProgress: CGFloat,
        hitFrom previousProgress: CGFloat,
        to targetProgress: CGFloat,
        tolerance: CGFloat,
        allowsCrossing: Bool
    ) -> Bool {
        if abs(targetProgress - snapProgress) <= tolerance {
            return true
        }

        return allowsCrossing
            && ((previousProgress < snapProgress && targetProgress > snapProgress)
                || (previousProgress > snapProgress && targetProgress < snapProgress))
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

    private static func snapPoints(for samples: [RouteElevationSample]) -> [SnapPoint] {
        var points: [SnapPoint] = []
        if let altitudePeakProgress = altitudePeakProgress(for: samples) {
            points.append(SnapPoint(progress: altitudePeakProgress, markerKind: .altitude))
        }
        if let heartRatePeakProgress = metricPeakProgress(
            for: samples,
            requiresPositiveValue: true,
            value: \.heartRateBeatsPerMinute
        ) {
            points.append(SnapPoint(progress: heartRatePeakProgress, markerKind: .heartRate))
        }
        if let powerPeakProgress = metricPeakProgress(
            for: samples,
            requiresPositiveValue: true,
            value: \.powerWatts
        ) {
            points.append(SnapPoint(progress: powerPeakProgress, markerKind: .power))
        }

        return mergedSnapPoints(points)
    }

    private static func altitudePeakProgress(for samples: [RouteElevationSample]) -> CGFloat? {
        guard samples.count > 1,
              let totalDistance = samples.last?.distanceMeters,
              totalDistance > 0,
              let peakIndex = samples.indices.max(by: { samples[$0].altitudeMeters < samples[$1].altitudeMeters }) else {
            return nil
        }

        return CGFloat(samples[peakIndex].distanceMeters / totalDistance)
    }

    private static func metricPeakProgress(
        for samples: [RouteElevationSample],
        requiresPositiveValue: Bool,
        value: KeyPath<RouteElevationSample, Double?>
    ) -> CGFloat? {
        guard samples.count > 1,
              let totalDistance = samples.last?.distanceMeters,
              totalDistance > 0,
              let peakIndex = samples.indices
                .compactMap({ index -> (index: Int, value: Double)? in
                    guard let sampleValue = samples[index][keyPath: value],
                          sampleValue.isFinite,
                          !requiresPositiveValue || sampleValue > 0 else {
                        return nil
                    }
                    return (index, sampleValue)
                })
                .max(by: { lhs, rhs in lhs.value < rhs.value })?
                .index else {
            return nil
        }

        return CGFloat(samples[peakIndex].distanceMeters / totalDistance)
    }

    private static func mergedSnapPoints(_ points: [SnapPoint]) -> [SnapPoint] {
        points.reduce(into: []) { result, point in
            if let index = result.firstIndex(where: { abs($0.progress - point.progress) < 0.000_001 }) {
                result[index] = SnapPoint(
                    progress: result[index].progress,
                    markerKind: mergedMarkerKind(result[index].markerKind, point.markerKind)
                )
            } else {
                result.append(point)
            }
        }
    }

    private static func mergedMarkerKind(
        _ existingKind: PeakMarkerKind,
        _ newKind: PeakMarkerKind
    ) -> PeakMarkerKind {
        if existingKind == .altitude || newKind == .altitude {
            return .altitude
        }
        if existingKind == .heartRate || newKind == .heartRate {
            return .heartRate
        }
        return .power
    }
}
