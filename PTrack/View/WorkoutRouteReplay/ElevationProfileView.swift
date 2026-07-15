//
//  ElevationProfileView.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import CoreLocation
import UIKit

final class ElevationProfileView: UIView {
    nonisolated struct PeakSamples: Sendable {
        let altitude: RouteElevationSample?
        let slope: RouteElevationSample?
        let heartRate: RouteElevationSample?
        let power: RouteElevationSample?
        let temperature: RouteElevationSample?

        init(
            altitude: RouteElevationSample?,
            slope: RouteElevationSample? = nil,
            heartRate: RouteElevationSample?,
            power: RouteElevationSample?,
            temperature: RouteElevationSample?
        ) {
            self.altitude = altitude
            self.slope = slope
            self.heartRate = heartRate
            self.power = power
            self.temperature = temperature
        }

        init(samples: [RouteElevationSample]) {
            altitude = samples.max {
                $0.altitudeMeters < $1.altitudeMeters
            }
            // A single-point maximum is too sensitive to GPS altitude noise to
            // represent the steepest climb. Callers that have run the sustained
            // slope analysis must inject that peak explicitly.
            slope = nil
            heartRate = Self.metricPeak(
                in: samples,
                requiresPositiveValue: true,
                value: \.heartRateBeatsPerMinute
            )
            power = Self.metricPeak(
                in: samples,
                requiresPositiveValue: true,
                value: \.powerWatts
            )
            temperature = Self.metricPeak(
                in: samples,
                requiresPositiveValue: false,
                value: \.temperatureCelsius
            )
        }

        private static func metricPeak(
            in samples: [RouteElevationSample],
            requiresPositiveValue: Bool,
            value: KeyPath<RouteElevationSample, Double?>
        ) -> RouteElevationSample? {
            samples.compactMap { sample -> (sample: RouteElevationSample, value: Double)? in
                guard let sampleValue = sample[keyPath: value],
                      sampleValue.isFinite,
                      !requiresPositiveValue || sampleValue > 0 else {
                    return nil
                }
                return (sample, sampleValue)
            }
            .max { $0.value < $1.value }?
            .sample
        }
    }

    private struct PlotGeometry {
        let size: CGSize
        let distanceRange: ClosedRange<CLLocationDistance>
        let minimumAltitude: Double
        let altitudeRange: Double
        let horizontalPadding: CGFloat
        let bottomPadding: CGFloat
        let drawableWidth: CGFloat
        let usableHeight: CGFloat

        func point(for sample: RouteElevationSample) -> CGPoint {
            let visibleDistance = max(distanceRange.upperBound - distanceRange.lowerBound, 1)
            let distanceProgress = min(
                max((sample.distanceMeters - distanceRange.lowerBound) / visibleDistance, 0),
                1
            )
            let normalizedAltitude = (sample.altitudeMeters - minimumAltitude) / altitudeRange
            return CGPoint(
                x: horizontalPadding + CGFloat(distanceProgress) * drawableWidth,
                y: size.height - bottomPadding - CGFloat(normalizedAltitude) * usableHeight
            )
        }
    }

    private let fillGradientLayer = CAGradientLayer()
    private let fillLayer = CAShapeLayer()
    private let curveLayer = CAShapeLayer()
    private let peakLabel = UILabel()
    private let slopePeakLabel = UILabel()
    private let heartRatePeakLabel = UILabel()
    private let powerPeakLabel = UILabel()
    private let temperaturePeakLabel = UILabel()
    private var samples: [RouteElevationSample] = []
    private var peakSamples = PeakSamples(samples: [])
    private var distanceRange: ClosedRange<CLLocationDistance> = 0...0
    private var renderedSize = CGSize.zero
    private let horizontalPadding = WorkoutRouteReplayRulerLayout.horizontalPadding

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePathIfNeeded()
    }

    func configure(
        samples: [RouteElevationSample],
        distanceRange: ClosedRange<CLLocationDistance>,
        peakSamples: PeakSamples
    ) {
        self.samples = samples
        self.distanceRange = distanceRange
        self.peakSamples = peakSamples
        renderedSize = .zero
        updatePathIfNeeded()
    }

    func setHighlightedPeak(_ kind: PeakMarkerKind?, animated: Bool) {
        let highlightedTransform = CGAffineTransform(scaleX: 1.24, y: 1.24)
        let powerTransform = CGAffineTransform(rotationAngle: -.pi / 2)
        let updates = {
            self.peakLabel.transform = kind == .altitude ? highlightedTransform : .identity
            self.slopePeakLabel.transform = kind == .slope
                ? CGAffineTransform(scaleX: -1.24, y: 1.24)
                : CGAffineTransform(scaleX: -1, y: 1)
            self.heartRatePeakLabel.transform = kind == .heartRate ? highlightedTransform : .identity
            self.powerPeakLabel.transform = kind == .power
                ? powerTransform.scaledBy(x: 1.24, y: 1.24)
                : powerTransform
            self.temperaturePeakLabel.transform = kind == .temperature
                ? highlightedTransform
                : .identity
        }
        guard animated else {
            updates()
            return
        }

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            updates()
        }
    }

    private func configureLayers() {
        isOpaque = false

        fillGradientLayer.locations = [0, 1]
        fillGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fillGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        fillGradientLayer.contentsScale = contentScaleFactor

        fillLayer.fillColor = UIColor.black.cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor
        fillLayer.contentsScale = contentScaleFactor
        fillGradientLayer.mask = fillLayer

        curveLayer.fillColor = UIColor.clear.cgColor
        curveLayer.lineWidth = 2
        curveLayer.lineJoin = .round
        curveLayer.lineCap = .round
        curveLayer.contentsScale = contentScaleFactor
        curveLayer.drawsAsynchronously = true

        layer.addSublayer(fillGradientLayer)
        layer.addSublayer(curveLayer)

        configureMarkerLabel(peakLabel, text: "▲", accessibilityLabel: "Maximum altitude")
        peakLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        configureMarkerLabel(slopePeakLabel, text: "↖︎", accessibilityLabel: "Maximum climbing grade")
        slopePeakLabel.font = .systemFont(ofSize: 17, weight: .bold)
        slopePeakLabel.transform = CGAffineTransform(scaleX: -1, y: 1)
        configureMarkerLabel(heartRatePeakLabel, text: "♥︎", accessibilityLabel: "Maximum heart rate")
        heartRatePeakLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        configureMarkerLabel(powerPeakLabel, text: "⌁", accessibilityLabel: "Maximum power")
        powerPeakLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        powerPeakLabel.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        configureMarkerLabel(temperaturePeakLabel, text: "☀︎", accessibilityLabel: "Maximum temperature")

        [peakLabel, slopePeakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
            addSubview(label)
        }

        applyDynamicColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.applyDynamicColors()
        }
    }

    private func configureMarkerLabel(
        _ label: UILabel,
        text: String,
        accessibilityLabel: String
    ) {
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.textAlignment = .center
        label.isHidden = true
        label.accessibilityLabel = accessibilityLabel
    }

    private func applyDynamicColors() {
        let foregroundColor = UIColor.label.resolvedColor(with: traitCollection)

        fillGradientLayer.colors = [
            foregroundColor.withAlphaComponent(0.11).cgColor,
            foregroundColor.withAlphaComponent(0).cgColor
        ]
        curveLayer.strokeColor = foregroundColor.withAlphaComponent(0.76).cgColor
    }

    private func updatePathIfNeeded() {
        guard renderedSize != bounds.size else {
            return
        }
        renderedSize = bounds.size

        guard bounds.width > 1, bounds.height > 1, samples.count > 1 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillLayer.path = nil
            fillGradientLayer.frame = bounds
            curveLayer.path = nil
            hideMarkerLabels()
            CATransaction.commit()
            return
        }

        let points = normalizedPoints(for: samples, in: bounds.size)
        let curvePath = CGMutablePath()
        let fillPath = CGMutablePath()
        for pointGroup in continuousPointGroups(points: points) where pointGroup.count > 1 {
            let groupCurvePath = smoothedPath(for: pointGroup)
            curvePath.addPath(groupCurvePath)
            fillPath.addPath(groupCurvePath)
            if let firstPoint = pointGroup.first,
               let lastPoint = pointGroup.last {
                fillPath.addLine(to: CGPoint(x: lastPoint.x, y: bounds.height))
                fillPath.addLine(to: CGPoint(x: firstPoint.x, y: bounds.height))
                fillPath.closeSubpath()
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillGradientLayer.frame = bounds
        fillLayer.frame = bounds
        curveLayer.frame = bounds
        fillLayer.path = fillPath
        curveLayer.path = curvePath
        CATransaction.commit()

        updatePeakLabels()
    }

    private func continuousPointGroups(points: [CGPoint]) -> [[CGPoint]] {
        guard points.count == samples.count,
              let firstPoint = points.first,
              let firstSample = samples.first else {
            return []
        }

        var groups: [[CGPoint]] = [[firstPoint]]
        var currentSeriesIdentifier = firstSample.seriesIdentifier
        for index in 1..<points.count {
            let seriesIdentifier = samples[index].seriesIdentifier
            if seriesIdentifier != currentSeriesIdentifier {
                groups.append([])
                currentSeriesIdentifier = seriesIdentifier
            }
            groups[groups.count - 1].append(points[index])
        }
        return groups
    }

    private func normalizedPoints(
        for samples: [RouteElevationSample],
        in size: CGSize
    ) -> [CGPoint] {
        let geometry = plotGeometry(for: samples, in: size)
        return samples.map(geometry.point)
    }

    private func plotGeometry(
        for samples: [RouteElevationSample],
        in size: CGSize
    ) -> PlotGeometry {
        let topPadding: CGFloat = 30
        let bottomPadding: CGFloat = 9
        let drawableWidth = max(size.width - horizontalPadding * 2, 1)
        let usableHeight = max(size.height - topPadding - bottomPadding, 1)
        let altitudeValues = samples.map(\.altitudeMeters)
        let minimumAltitude = altitudeValues.min() ?? 0
        let maximumAltitude = altitudeValues.max() ?? minimumAltitude
        let altitudeRange = max(maximumAltitude - minimumAltitude, 1)

        return PlotGeometry(
            size: size,
            distanceRange: distanceRange,
            minimumAltitude: minimumAltitude,
            altitudeRange: altitudeRange,
            horizontalPadding: horizontalPadding,
            bottomPadding: bottomPadding,
            drawableWidth: drawableWidth,
            usableHeight: usableHeight
        )
    }

    private func smoothedPath(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: firstPoint)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }

        var previousPoint = firstPoint
        for point in points.dropFirst() {
            let midPoint = CGPoint(
                x: (previousPoint.x + point.x) / 2,
                y: (previousPoint.y + point.y) / 2
            )
            path.addQuadCurve(to: midPoint, control: previousPoint)
            previousPoint = point
        }

        if let lastPoint = points.last {
            path.addQuadCurve(to: lastPoint, control: previousPoint)
        }

        return path
    }

    private func updatePeakLabels() {
        let geometry = plotGeometry(for: samples, in: bounds.size)
        var occupiedFrames: [CGRect] = []
        placePeakMarkerLabel(
            peakLabel,
            sample: peakSamples.altitude,
            geometry: geometry,
            occupiedFrames: &occupiedFrames
        )
        placePeakMarkerLabel(
            slopePeakLabel,
            sample: peakSamples.slope,
            geometry: geometry,
            allowsDownwardFallback: false,
            occupiedFrames: &occupiedFrames
        )
        placePeakMarkerLabel(
            heartRatePeakLabel,
            sample: peakSamples.heartRate,
            geometry: geometry,
            verticalGap: 13,
            maximumCenterY: bounds.height * 0.48,
            allowsDownwardFallback: false,
            occupiedFrames: &occupiedFrames
        )
        placePeakMarkerLabel(
            powerPeakLabel,
            sample: peakSamples.power,
            geometry: geometry,
            verticalGap: 13,
            maximumCenterY: bounds.height * 0.48,
            allowsDownwardFallback: false,
            occupiedFrames: &occupiedFrames
        )
        placePeakMarkerLabel(
            temperaturePeakLabel,
            sample: peakSamples.temperature,
            geometry: geometry,
            verticalGap: 13,
            maximumCenterY: bounds.height * 0.48,
            allowsDownwardFallback: false,
            occupiedFrames: &occupiedFrames
        )
    }

    private func placePeakMarkerLabel(
        _ label: UILabel,
        sample: RouteElevationSample?,
        geometry: PlotGeometry,
        verticalGap: CGFloat = 6,
        maximumCenterY: CGFloat? = nil,
        allowsDownwardFallback: Bool = true,
        occupiedFrames: inout [CGRect]
    ) {
        guard let sample,
              isVisible(distance: sample.distanceMeters) else {
            label.isHidden = true
            return
        }

        placeMarkerLabel(
            label,
            at: geometry.point(for: sample),
            verticalGap: verticalGap,
            maximumCenterY: maximumCenterY,
            allowsDownwardFallback: allowsDownwardFallback,
            occupiedFrames: &occupiedFrames
        )
    }

    private func isVisible(distance: CLLocationDistance) -> Bool {
        let tolerance = max(distanceRange.upperBound - distanceRange.lowerBound, 1) * 1e-9
        return distance >= distanceRange.lowerBound - tolerance
            && distance <= distanceRange.upperBound + tolerance
    }

    private func placeMarkerLabel(
        _ label: UILabel,
        at point: CGPoint,
        verticalGap: CGFloat = 6,
        maximumCenterY: CGFloat? = nil,
        allowsDownwardFallback: Bool = true,
        occupiedFrames: inout [CGRect]
    ) {
        let labelSize = label === powerPeakLabel
            ? CGSize(width: 30, height: 30)
            : CGSize(width: 24, height: 24)
        // The curve, ruler and gesture mapping share enough horizontal inset
        // for the widest marker, so its center can stay on the true data x.
        let centerX = point.x
        let preferredCenterY = min(
            max(point.y - labelSize.height / 2 - verticalGap, labelSize.height / 2),
            maximumCenterY ?? (bounds.height - labelSize.height / 2)
        )
        guard let center = nonOverlappingCenter(
            CGPoint(x: centerX, y: preferredCenterY),
            labelSize: labelSize,
            maximumCenterY: maximumCenterY,
            allowsDownwardFallback: allowsDownwardFallback,
            occupiedFrames: occupiedFrames
        ) else {
            label.isHidden = true
            return
        }
        let frame = CGRect(
            x: center.x - labelSize.width / 2,
            y: center.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        label.isHidden = false
        label.bounds = CGRect(origin: .zero, size: labelSize)
        // Updating bounds + center keeps the configured flip/rotation transform
        // intact; assigning frame here would make transformed labels jump.
        label.center = center
        // Reserve enough breathing room for the 1.24x snap highlight as well.
        occupiedFrames.append(frame.insetBy(dx: -4, dy: -4))
    }

    private func nonOverlappingCenter(
        _ preferredCenter: CGPoint,
        labelSize: CGSize,
        maximumCenterY: CGFloat?,
        allowsDownwardFallback: Bool,
        occupiedFrames: [CGRect]
    ) -> CGPoint? {
        let minimumCenterY = labelSize.height / 2
        let resolvedMaximumCenterY = min(
            maximumCenterY ?? (bounds.height - labelSize.height / 2),
            bounds.height - labelSize.height / 2
        )
        guard resolvedMaximumCenterY >= minimumCenterY else {
            return nil
        }

        // A marker's x position represents its distance and must never move.
        // Resolve collisions vertically so the ruler snap and marker stay aligned.
        let verticalStep = labelSize.height * 0.82
        var verticalOffsets: [CGFloat] = [
            0,
            -verticalStep,
            -verticalStep * 2,
            -verticalStep * 3
        ]
        if allowsDownwardFallback {
            verticalOffsets.append(contentsOf: [
                verticalStep,
                verticalStep * 2
            ])
        }

        var testedCenterYs: [CGFloat] = []
        for verticalOffset in verticalOffsets {
            let centerY = min(
                max(preferredCenter.y + verticalOffset, minimumCenterY),
                resolvedMaximumCenterY
            )
            guard !testedCenterYs.contains(where: { abs($0 - centerY) < 0.5 }) else {
                continue
            }
            testedCenterYs.append(centerY)

            let center = CGPoint(x: preferredCenter.x, y: centerY)
            let frame = CGRect(
                x: center.x - labelSize.width / 2,
                y: center.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            if !occupiedFrames.contains(where: { $0.intersects(frame) }) {
                return center
            }
        }

        // If the compact profile has no collision-free row left, keep the
        // marker visible at its preferred position. Its x coordinate still
        // represents the exact route distance, so overlap is preferable to
        // hiding a peak or moving it away from the ruler snap position.
        return CGPoint(
            x: preferredCenter.x,
            y: min(
                max(preferredCenter.y, minimumCenterY),
                resolvedMaximumCenterY
            )
        )
    }

    private func hideMarkerLabels() {
        [peakLabel, slopePeakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
            label.isHidden = true
        }
    }
}
