//
//  WorkoutRouteReplayRulerView.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import SnapKit
import UIKit

final class WorkoutRouteReplayRulerView: UIControl {
    private let profileView = ElevationProfileView()
    private let indicatorView = UIView()
    private let distanceScaleView = RouteDistanceScaleView()

    private struct SnapPoint {
        let progress: CGFloat
        let markerKind: PeakMarkerKind
    }

    private enum BoundaryPanSide {
        case lower
        case upper
    }

    private struct BoundaryPanContext {
        let range: ClosedRange<CLLocationDistance>
        let side: BoundaryPanSide
        let thresholdDistance: CLLocationDistance
    }

    private var indicatorCenterXConstraint: Constraint?
    private let horizontalPadding: CGFloat = 2
    private let maximumRenderedSampleCount = 600
    private var elevationSamples: [RouteElevationSample] = []
    private var peakSamples = ElevationProfileView.PeakSamples(samples: [])
    private var totalDistanceMeters: CLLocationDistance = 0
    private var totalDistanceText = "0km"
    private var visibleDistanceRange: ClosedRange<CLLocationDistance> = 0...0
    private var segmentBoundaryDistanceRanges: [ClosedRange<CLLocationDistance>] = []
    private var snapPoints: [SnapPoint] = []
    private var activeSnapProgress: CGFloat?
    private var activeMarkerKind: PeakMarkerKind?
    private var boundaryPanContext: BoundaryPanContext?
    private var indicatorVisibilityRequested = true
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

    func configure(
        totalDistanceText: String,
        totalDistanceMeters: CLLocationDistance? = nil,
        elevationSamples: [RouteElevationSample] = [],
        globalPeakSamples: ElevationProfileView.PeakSamples? = nil,
        segmentBoundaryDistanceRanges: [ClosedRange<CLLocationDistance>] = []
    ) {
        self.totalDistanceText = totalDistanceText
        self.elevationSamples = elevationSamples
            .enumerated()
            .filter { $0.element.distanceMeters.isFinite && $0.element.altitudeMeters.isFinite }
            .sorted { lhs, rhs in
                if lhs.element.distanceMeters != rhs.element.distanceMeters {
                    return lhs.element.distanceMeters < rhs.element.distanceMeters
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let inferredDistance = self.elevationSamples.last?.distanceMeters ?? 0
        let requestedDistance = totalDistanceMeters.flatMap { $0.isFinite ? $0 : nil } ?? inferredDistance
        self.totalDistanceMeters = max(requestedDistance, inferredDistance, 0)
        self.segmentBoundaryDistanceRanges = segmentBoundaryDistanceRanges
            .compactMap { range -> ClosedRange<CLLocationDistance>? in
                let lowerBound = min(max(range.lowerBound, 0), self.totalDistanceMeters)
                let upperBound = min(
                    max(range.upperBound, lowerBound),
                    self.totalDistanceMeters
                )
                return upperBound > lowerBound ? lowerBound...upperBound : nil
            }
            .sorted { $0.lowerBound < $1.lowerBound }
        boundaryPanContext = nil
        peakSamples = globalPeakSamples
            ?? ElevationProfileView.PeakSamples(samples: self.elevationSamples)
        snapPoints = Self.snapPoints(
            for: peakSamples,
            totalDistanceMeters: self.totalDistanceMeters
        )
        visibleDistanceRange = 0...self.totalDistanceMeters
        refreshVisibleContent()
    }

    func setVisibleDistanceRange(_ range: ClosedRange<CLLocationDistance>?) {
        guard totalDistanceMeters > 0 else {
            visibleDistanceRange = 0...0
            refreshVisibleContent()
            return
        }

        let fullRange = 0...totalDistanceMeters
        guard let range else {
            applyVisibleDistanceRange(fullRange)
            return
        }

        var lowerBound = min(max(range.lowerBound, 0), totalDistanceMeters)
        var upperBound = min(max(range.upperBound, lowerBound), totalDistanceMeters)
        let fullRangeTolerance = max(totalDistanceMeters * 0.000_001, 0.5)
        if lowerBound <= fullRangeTolerance,
           upperBound >= totalDistanceMeters - fullRangeTolerance {
            lowerBound = 0
            upperBound = totalDistanceMeters
        }

        let minimumSpan = min(totalDistanceMeters, max(totalDistanceMeters * 0.000_001, 1))
        if upperBound - lowerBound < minimumSpan {
            let center = (lowerBound + upperBound) / 2
            lowerBound = max(center - minimumSpan / 2, 0)
            upperBound = min(lowerBound + minimumSpan, totalDistanceMeters)
            lowerBound = max(upperBound - minimumSpan, 0)
        }

        applyVisibleDistanceRange(lowerBound...upperBound)
    }

    func setProgress(_ progress: CGFloat, sendsAction: Bool = false) {
        setProgress(progress, sendsAction: sendsAction, allowsPeakCrossing: false)
    }

    func setIndicatorVisible(_ isVisible: Bool) {
        indicatorVisibilityRequested = isVisible
        updateIndicatorVisibility()
    }

    @discardableResult
    private func applyVisibleDistanceRange(
        _ range: ClosedRange<CLLocationDistance>
    ) -> Bool {
        let numericalTolerance = max(totalDistanceMeters, 1) * 1e-9
        let drawableWidth = profileView.bounds.width - horizontalPadding * 2
        let currentSpan = visibleDistanceRange.upperBound
            - visibleDistanceRange.lowerBound
        let requestedSpan = range.upperBound - range.lowerBound
        let visualTolerance: CLLocationDistance
        if drawableWidth > 1 {
            let displayScale = max(profileView.traitCollection.displayScale, 1)
            visualTolerance = max(currentSpan, requestedSpan)
                / Double(drawableWidth) * (0.5 / Double(displayScale))
        } else {
            visualTolerance = 0
        }
        let tolerance = max(numericalTolerance, visualTolerance, 0.01)
        guard abs(visibleDistanceRange.lowerBound - range.lowerBound) > tolerance
                || abs(visibleDistanceRange.upperBound - range.upperBound) > tolerance else {
            return false
        }

        visibleDistanceRange = range
        refreshVisibleContent()
        return true
    }

    private func refreshVisibleContent() {
        let visibleSamples = elevationSamples(in: visibleDistanceRange)
        let renderedSamples = downsample(
            visibleSamples,
            maximumCount: maximumRenderedSampleCount
        )
        profileView.configure(
            samples: renderedSamples,
            distanceRange: visibleDistanceRange,
            peakSamples: peakSamples
        )
        activeSnapProgress = nil
        activeMarkerKind = nil
        profileView.setHighlightedPeak(nil, animated: false)
        distanceScaleView.configure(
            visibleRange: visibleDistanceRange,
            totalDistanceMeters: totalDistanceMeters,
            totalDistanceText: totalDistanceText
        )
        updateProgressLayout(flushLayout: false)
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

        addSubview(profileView)
        insertSubview(indicatorView, belowSubview: profileView)
        addSubview(distanceScaleView)

        profileView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(70)
        }

        indicatorView.snp.makeConstraints { make in
            make.top.bottom.equalTo(profileView).inset(2)
            indicatorCenterXConstraint = make.centerX.equalTo(profileView.snp.leading).offset(0).constraint
            make.width.equalTo(2)
        }

        distanceScaleView.snp.makeConstraints { make in
            make.top.equalTo(profileView.snp.bottom).offset(5)
            make.leading.trailing.bottom.equalToSuperview()
        }

        let panGesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleProgressGesture(_:))
        )
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleProgressGesture(_:)))
        addGestureRecognizer(panGesture)
        addGestureRecognizer(tapGesture)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = panGesture.velocity(in: self)
        guard velocity != .zero else {
            return true
        }
        return abs(velocity.x) > abs(velocity.y)
    }

    private func updateProgressLayout(flushLayout: Bool) {
        let profileWidth = profileView.bounds.width
        guard profileWidth > 0 else {
            return
        }

        let drawableWidth = max(profileWidth - horizontalPadding * 2, 1)
        let localProgress = localProgress(forGlobalProgress: progress)
        indicatorCenterXConstraint?.update(
            offset: horizontalPadding + drawableWidth * localProgress
        )
        updateIndicatorVisibility()
        if flushLayout {
            layoutIfNeeded()
        }
    }

    private func updateIndicatorVisibility() {
        guard totalDistanceMeters > 0,
              visibleDistanceRange.upperBound > visibleDistanceRange.lowerBound else {
            indicatorView.isHidden = true
            return
        }

        let currentDistance = CLLocationDistance(progress) * totalDistanceMeters
        let tolerance = max(totalDistanceMeters, 1) * 1e-9
        let isInsideVisibleRange = currentDistance >= visibleDistanceRange.lowerBound - tolerance
            && currentDistance <= visibleDistanceRange.upperBound + tolerance
        indicatorView.isHidden = !indicatorVisibilityRequested || !isInsideVisibleRange
    }

    private func localProgress(forGlobalProgress globalProgress: CGFloat) -> CGFloat {
        let visibleSpan = visibleDistanceRange.upperBound - visibleDistanceRange.lowerBound
        guard totalDistanceMeters > 0, visibleSpan > 0 else {
            return 0
        }

        let distance = CLLocationDistance(globalProgress) * totalDistanceMeters
        return min(max(CGFloat((distance - visibleDistanceRange.lowerBound) / visibleSpan), 0), 1)
    }

    private func globalProgress(forLocalProgress localProgress: CGFloat) -> CGFloat {
        guard totalDistanceMeters > 0 else {
            return 0
        }

        let clampedLocalProgress = min(max(localProgress, 0), 1)
        let visibleSpan = visibleDistanceRange.upperBound - visibleDistanceRange.lowerBound
        let distance = visibleDistanceRange.lowerBound
            + visibleSpan * CLLocationDistance(clampedLocalProgress)
        return CGFloat(distance / totalDistanceMeters)
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
        guard totalDistanceMeters > 0 else {
            return 1 / drawableWidth
        }

        let visibleProgressSpan = CGFloat(
            (visibleDistanceRange.upperBound - visibleDistanceRange.lowerBound) / totalDistanceMeters
        )
        return visibleProgressSpan / drawableWidth
    }

    @objc private func handleProgressGesture(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            peakFeedbackGenerator.prepare()
            boundaryPanContext = nil
        }

        let location = recognizer.location(in: profileView)
        let drawableWidth = max(profileView.bounds.width - horizontalPadding * 2, 1)
        let localProgress = (location.x - horizontalPadding) / drawableWidth
        let allowsPeakCrossing = recognizer is UIPanGestureRecognizer && recognizer.state == .changed
        let requestedProgress = globalProgress(forLocalProgress: localProgress)
        setProgress(
            boundaryAdjustedProgress(
                requestedProgress,
                for: recognizer
            ),
            sendsAction: true,
            allowsPeakCrossing: allowsPeakCrossing
        )
        if recognizer.state == .ended
            || recognizer.state == .cancelled
            || recognizer.state == .failed {
            boundaryPanContext = nil
        }
    }

    private func boundaryAdjustedProgress(
        _ requestedProgress: CGFloat,
        for recognizer: UIGestureRecognizer
    ) -> CGFloat {
        guard recognizer is UIPanGestureRecognizer,
              !segmentBoundaryDistanceRanges.isEmpty,
              totalDistanceMeters > 0,
              profileView.bounds.width > horizontalPadding * 2 else {
            return requestedProgress
        }

        let visibleSpan = visibleDistanceRange.upperBound
            - visibleDistanceRange.lowerBound
        let drawableWidth = profileView.bounds.width - horizontalPadding * 2
        let deadZoneDistance = visibleSpan * Double(min(12 / drawableWidth, 0.08))
        let requestedDistance = CLLocationDistance(requestedProgress)
            * totalDistanceMeters
        let currentDistance = CLLocationDistance(progress) * totalDistanceMeters
        let tolerance = max(totalDistanceMeters, 1) * 1e-9

        if let context = boundaryPanContext {
            let centerDistance = (context.range.lowerBound + context.range.upperBound) / 2
            switch context.side {
            case .lower where requestedDistance < centerDistance - deadZoneDistance:
                boundaryPanContext = nil
                return requestedProgress
            case .upper where requestedDistance > centerDistance + deadZoneDistance:
                boundaryPanContext = nil
                return requestedProgress
            case .lower, .upper:
                break
            }
            let adjustedDistance: CLLocationDistance
            switch context.side {
            case .lower:
                if requestedDistance <= context.thresholdDistance {
                    adjustedDistance = context.range.lowerBound
                } else {
                    adjustedDistance = context.range.upperBound
                        + requestedDistance - context.thresholdDistance
                }
            case .upper:
                if requestedDistance >= context.thresholdDistance {
                    adjustedDistance = context.range.upperBound
                } else {
                    adjustedDistance = context.range.lowerBound
                        + requestedDistance - context.thresholdDistance
                }
            }
            return CGFloat(
                min(max(adjustedDistance, 0), totalDistanceMeters)
                    / totalDistanceMeters
            )
        }

        for boundaryRange in segmentBoundaryDistanceRanges {
            let centerDistance = (
                boundaryRange.lowerBound + boundaryRange.upperBound
            ) / 2
            guard abs(requestedDistance - centerDistance) <= deadZoneDistance else {
                continue
            }
            let currentBoundaryDistance = abs(currentDistance - centerDistance)
            guard currentBoundaryDistance <= deadZoneDistance * 2
                    + (boundaryRange.upperBound - boundaryRange.lowerBound) else {
                // A newly shown map segment can be far from the previous ruler
                // position. Do not make its first touch wait behind an unrelated
                // earlier boundary.
                continue
            }
            if currentDistance <= boundaryRange.lowerBound + tolerance {
                boundaryPanContext = BoundaryPanContext(
                    range: boundaryRange,
                    side: .lower,
                    thresholdDistance: centerDistance + deadZoneDistance
                )
                return CGFloat(boundaryRange.lowerBound / totalDistanceMeters)
            }
            if currentDistance >= boundaryRange.upperBound - tolerance {
                boundaryPanContext = BoundaryPanContext(
                    range: boundaryRange,
                    side: .upper,
                    thresholdDistance: centerDistance - deadZoneDistance
                )
                return CGFloat(boundaryRange.upperBound / totalDistanceMeters)
            }
            let targetDistance = requestedDistance <= centerDistance
                ? boundaryRange.lowerBound
                : boundaryRange.upperBound
            return CGFloat(targetDistance / totalDistanceMeters)
        }
        return requestedProgress
    }

    private func elevationSamples(
        in range: ClosedRange<CLLocationDistance>
    ) -> [RouteElevationSample] {
        guard elevationSamples.count > 1,
              let firstSample = elevationSamples.first,
              let lastSample = elevationSamples.last else {
            return elevationSamples.filter { range.contains($0.distanceMeters) }
        }

        let lowerBound = max(range.lowerBound, firstSample.distanceMeters)
        let upperBound = min(range.upperBound, lastSample.distanceMeters)
        guard upperBound >= lowerBound else {
            return []
        }

        let firstInsideIndex = firstSampleIndex(atOrAfter: lowerBound)
        let firstAfterIndex = firstSampleIndex(after: upperBound)
        var result: [RouteElevationSample] = []
        result.reserveCapacity(max(firstAfterIndex - firstInsideIndex + 2, 2))
        if firstInsideIndex > 0,
           firstInsideIndex < elevationSamples.count,
           elevationSamples[firstInsideIndex].distanceMeters > lowerBound,
           let lowerBoundarySample = interpolatedSample(
               at: lowerBound,
               upperIndex: firstInsideIndex
           ) {
            result.append(lowerBoundarySample)
        }

        if firstInsideIndex < firstAfterIndex {
            result.append(contentsOf: elevationSamples[firstInsideIndex..<firstAfterIndex])
        }

        if firstAfterIndex > 0,
           firstAfterIndex < elevationSamples.count,
           elevationSamples[firstAfterIndex - 1].distanceMeters < upperBound,
           let upperBoundarySample = interpolatedSample(
               at: upperBound,
               upperIndex: firstAfterIndex
           ) {
            result.append(upperBoundarySample)
        }
        return result
    }

    private func firstSampleIndex(atOrAfter distance: CLLocationDistance) -> Int {
        var lowerBound = 0
        var upperBound = elevationSamples.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if elevationSamples[middle].distanceMeters < distance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func firstSampleIndex(after distance: CLLocationDistance) -> Int {
        var lowerBound = 0
        var upperBound = elevationSamples.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if elevationSamples[middle].distanceMeters <= distance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func interpolatedSample(
        at distance: CLLocationDistance,
        upperIndex: Int
    ) -> RouteElevationSample? {
        guard upperIndex > 0, upperIndex < elevationSamples.count else {
            return nil
        }
        let upperSample = elevationSamples[upperIndex]
        let lowerSample = elevationSamples[upperIndex - 1]
        let sampleSpan = upperSample.distanceMeters - lowerSample.distanceMeters
        guard sampleSpan > 0,
              lowerSample.seriesIdentifier == upperSample.seriesIdentifier else {
            return nil
        }

        let interpolation = (distance - lowerSample.distanceMeters) / sampleSpan
        return RouteElevationSample(
            distanceMeters: distance,
            altitudeMeters: interpolated(
                lowerSample.altitudeMeters,
                upperSample.altitudeMeters,
                progress: interpolation
            ),
            heartRateBeatsPerMinute: interpolated(
                lowerSample.heartRateBeatsPerMinute,
                upperSample.heartRateBeatsPerMinute,
                progress: interpolation
            ),
            powerWatts: interpolated(
                lowerSample.powerWatts,
                upperSample.powerWatts,
                progress: interpolation
            ),
            temperatureCelsius: interpolated(
                lowerSample.temperatureCelsius,
                upperSample.temperatureCelsius,
                progress: interpolation
            ),
            seriesIdentifier: lowerSample.seriesIdentifier
        )
    }

    private func interpolated(
        _ lowerValue: Double,
        _ upperValue: Double,
        progress: Double
    ) -> Double {
        lowerValue + (upperValue - lowerValue) * progress
    }

    private func interpolated(
        _ lowerValue: Double?,
        _ upperValue: Double?,
        progress: Double
    ) -> Double? {
        guard let lowerValue, let upperValue else {
            return nil
        }
        return interpolated(lowerValue, upperValue, progress: progress)
    }

    private func downsample(
        _ samples: [RouteElevationSample],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        RouteElevationSampler.downsample(
            samples,
            maximumCount: maximumCount
        ) ?? samples
    }

    private static func snapPoints(
        for peakSamples: ElevationProfileView.PeakSamples,
        totalDistanceMeters: CLLocationDistance
    ) -> [SnapPoint] {
        guard totalDistanceMeters > 0 else {
            return []
        }

        var points: [SnapPoint] = []
        if let sample = peakSamples.altitude,
           let progress = peakProgress(
               for: sample,
               totalDistanceMeters: totalDistanceMeters
           ) {
            points.append(SnapPoint(progress: progress, markerKind: .altitude))
        }
        if let sample = peakSamples.heartRate,
           let progress = peakProgress(
               for: sample,
               totalDistanceMeters: totalDistanceMeters
           ) {
            points.append(SnapPoint(progress: progress, markerKind: .heartRate))
        }
        if let sample = peakSamples.power,
           let progress = peakProgress(
               for: sample,
               totalDistanceMeters: totalDistanceMeters
           ) {
            points.append(SnapPoint(progress: progress, markerKind: .power))
        }

        return mergedSnapPoints(points)
    }

    private static func peakProgress(
        for sample: RouteElevationSample,
        totalDistanceMeters: CLLocationDistance
    ) -> CGFloat? {
        guard sample.distanceMeters.isFinite,
              sample.distanceMeters >= 0,
              sample.distanceMeters <= totalDistanceMeters else {
            return nil
        }
        return CGFloat(sample.distanceMeters / totalDistanceMeters)
    }

    private static func mergedSnapPoints(_ points: [SnapPoint]) -> [SnapPoint] {
        points.reduce(into: []) { result, point in
            if let index = result.firstIndex(where: {
                abs($0.progress - point.progress) < 0.000_001
            }) {
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

private final class RouteDistanceScaleView: UIView {
    private var visibleRange: ClosedRange<CLLocationDistance> = 0...0
    private var totalDistanceMeters: CLLocationDistance = 0
    private var totalDistanceText = "0km"
    private let horizontalPadding: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isOpaque = false
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.setNeedsDisplay()
        }
    }

    func configure(
        visibleRange: ClosedRange<CLLocationDistance>,
        totalDistanceMeters: CLLocationDistance,
        totalDistanceText: String
    ) {
        self.visibleRange = visibleRange
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDistanceText = totalDistanceText
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              rect.width > horizontalPadding * 2,
              visibleRange.upperBound > visibleRange.lowerBound else {
            return
        }

        let drawableWidth = rect.width - horizontalPadding * 2
        let baselineY: CGFloat = 1.5
        let majorTickHeight: CGFloat = 5
        let minorTickHeight: CGFloat = 2.5
        let axisColor = UIColor.secondaryLabel.withAlphaComponent(0.38)
        context.setStrokeColor(axisColor.cgColor)
        context.setLineWidth(1 / max(contentScaleFactor, 1))
        context.move(to: CGPoint(x: horizontalPadding, y: baselineY))
        context.addLine(to: CGPoint(x: rect.width - horizontalPadding, y: baselineY))
        context.strokePath()
        drawTick(
            at: horizontalPadding,
            height: majorTickHeight,
            baselineY: baselineY,
            context: context
        )
        drawTick(
            at: rect.width - horizontalPadding,
            height: majorTickHeight,
            baselineY: baselineY,
            context: context
        )

        let span = visibleRange.upperBound - visibleRange.lowerBound
        let targetIntervalCount = max(Int(drawableWidth / 72), 2)
        let majorStep = niceStep(span / Double(targetIntervalCount))
        let minorStep = majorStep / 4
        if minorStep > 0 {
            let firstMinorTick = ceil(visibleRange.lowerBound / minorStep) * minorStep
            var distance = firstMinorTick
            var tickCount = 0
            while distance <= visibleRange.upperBound, tickCount < 100 {
                let majorMultiple = distance / majorStep
                let isMajor = abs(majorMultiple - majorMultiple.rounded()) < 0.000_001
                drawTick(
                    at: xPosition(for: distance, drawableWidth: drawableWidth),
                    height: isMajor ? majorTickHeight : minorTickHeight,
                    baselineY: baselineY,
                    context: context
                )
                distance += minorStep
                tickCount += 1
            }
        }

        drawLabels(
            in: rect,
            drawableWidth: drawableWidth,
            majorStep: majorStep,
            baselineY: baselineY + majorTickHeight + 1
        )
    }

    private func drawTick(
        at x: CGFloat,
        height: CGFloat,
        baselineY: CGFloat,
        context: CGContext
    ) {
        context.move(to: CGPoint(x: x, y: baselineY))
        context.addLine(to: CGPoint(x: x, y: baselineY + height))
        context.strokePath()
    }

    private func drawLabels(
        in rect: CGRect,
        drawableWidth: CGFloat,
        majorStep: CLLocationDistance,
        baselineY: CGFloat
    ) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let labelWidth: CGFloat = 66
        let labelHeight = max(rect.height - baselineY, font.lineHeight)
        var occupiedFrames: [CGRect] = []

        let endpointDistances = [visibleRange.lowerBound, visibleRange.upperBound]
        for (index, distance) in endpointDistances.enumerated() {
            let isLowerEndpoint = index == 0
            let x = xPosition(for: distance, drawableWidth: drawableWidth)
            let frame = CGRect(
                x: isLowerEndpoint ? horizontalPadding : x - labelWidth,
                y: baselineY,
                width: labelWidth,
                height: labelHeight
            )
            let text: String
            if !isLowerEndpoint,
               isFullDistanceRange,
               !totalDistanceText.isEmpty {
                text = totalDistanceText
            } else {
                text = formattedDistance(distance, step: majorStep)
            }
            draw(text, in: frame, alignment: isLowerEndpoint ? .left : .right, attributes: attributes)
            occupiedFrames.append(frame.insetBy(dx: -3, dy: 0))
        }

        var distance = ceil(visibleRange.lowerBound / majorStep) * majorStep
        var labelCount = 0
        while distance < visibleRange.upperBound, labelCount < 24 {
            if distance > visibleRange.lowerBound {
                let x = xPosition(for: distance, drawableWidth: drawableWidth)
                let frame = CGRect(
                    x: x - labelWidth / 2,
                    y: baselineY,
                    width: labelWidth,
                    height: labelHeight
                )
                if !occupiedFrames.contains(where: { $0.intersects(frame) }) {
                    draw(
                        formattedDistance(distance, step: majorStep),
                        in: frame,
                        alignment: .center,
                        attributes: attributes
                    )
                    occupiedFrames.append(frame.insetBy(dx: -3, dy: 0))
                }
            }
            distance += majorStep
            labelCount += 1
        }
    }

    private func draw(
        _ text: String,
        in frame: CGRect,
        alignment: NSTextAlignment,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        var resolvedAttributes = attributes
        resolvedAttributes[.paragraphStyle] = paragraphStyle
        (text as NSString).draw(in: frame, withAttributes: resolvedAttributes)
    }

    private var isFullDistanceRange: Bool {
        let tolerance = max(totalDistanceMeters, 1) * 0.000_001
        return visibleRange.lowerBound <= tolerance
            && visibleRange.upperBound >= totalDistanceMeters - tolerance
    }

    private func xPosition(
        for distance: CLLocationDistance,
        drawableWidth: CGFloat
    ) -> CGFloat {
        let span = visibleRange.upperBound - visibleRange.lowerBound
        let progress = CGFloat((distance - visibleRange.lowerBound) / span)
        return horizontalPadding + min(max(progress, 0), 1) * drawableWidth
    }

    private func niceStep(_ rawStep: CLLocationDistance) -> CLLocationDistance {
        guard rawStep.isFinite, rawStep > 0 else {
            return 1
        }

        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        return multiplier * magnitude
    }

    private func formattedDistance(
        _ distanceMeters: CLLocationDistance,
        step: CLLocationDistance
    ) -> String {
        let kilometers = max(distanceMeters, 0) / 1000
        guard kilometers > 0 else {
            return "0km"
        }

        let stepKilometers = step / 1000
        let decimalPlaces: Int
        if stepKilometers >= 10 {
            decimalPlaces = 0
        } else if stepKilometers >= 1 {
            decimalPlaces = 1
        } else if stepKilometers >= 0.1 {
            decimalPlaces = 1
        } else if stepKilometers >= 0.01 {
            decimalPlaces = 2
        } else {
            decimalPlaces = 3
        }

        var value = String(format: "%.*f", decimalPlaces, kilometers)
        while value.contains(".") && value.last == "0" {
            value.removeLast()
        }
        if value.last == "." {
            value.removeLast()
        }
        return "\(value)km"
    }
}
