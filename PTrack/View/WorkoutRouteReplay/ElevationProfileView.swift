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
        let heartRate: RouteElevationSample?
        let power: RouteElevationSample?
        let temperature: RouteElevationSample?

        init(
            altitude: RouteElevationSample?,
            heartRate: RouteElevationSample?,
            power: RouteElevationSample?,
            temperature: RouteElevationSample?
        ) {
            self.altitude = altitude
            self.heartRate = heartRate
            self.power = power
            self.temperature = temperature
        }

        init(samples: [RouteElevationSample]) {
            altitude = samples.max {
                $0.altitudeMeters < $1.altitudeMeters
            }
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
    private let heartRatePeakLabel = UILabel()
    private let powerPeakLabel = UILabel()
    private let temperaturePeakLabel = UILabel()
    private var samples: [RouteElevationSample] = []
    private var peakSamples = PeakSamples(samples: [])
    private var distanceRange: ClosedRange<CLLocationDistance> = 0...0
    private var renderedSize = CGSize.zero
    private let horizontalPadding: CGFloat = 2

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
        let updates = {
            self.peakLabel.transform = kind == .altitude ? highlightedTransform : .identity
            self.heartRatePeakLabel.transform = kind == .heartRate ? highlightedTransform : .identity
            self.powerPeakLabel.transform = kind == .power ? highlightedTransform : .identity
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

        configureMarkerLabel(peakLabel, text: "⛰️", accessibilityLabel: "Maximum altitude")
        configureMarkerLabel(heartRatePeakLabel, text: "❤️", accessibilityLabel: "Maximum heart rate")
        configureMarkerLabel(powerPeakLabel, text: "⚡️", accessibilityLabel: "Maximum power")
        configureMarkerLabel(temperaturePeakLabel, text: "☀️", accessibilityLabel: "Maximum temperature")

        [peakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
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
        label.textAlignment = .center
        label.isHidden = true
        label.accessibilityLabel = accessibilityLabel
        label.layer.shadowOpacity = 0.82
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
    }

    private func applyDynamicColors() {
        let foregroundColor = UIColor.label.resolvedColor(with: traitCollection)
        let backgroundColor = UIColor.systemBackground.resolvedColor(with: traitCollection)

        fillGradientLayer.colors = [
            foregroundColor.withAlphaComponent(0.11).cgColor,
            foregroundColor.withAlphaComponent(0).cgColor
        ]
        curveLayer.strokeColor = foregroundColor.withAlphaComponent(0.76).cgColor
        [peakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
            label.layer.shadowColor = backgroundColor.cgColor
        }
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
        let labelSize = CGSize(width: 24, height: 24)
        let centerX = min(max(point.x, labelSize.width / 2), bounds.width - labelSize.width / 2)
        let preferredCenterY = min(
            max(point.y - labelSize.height / 2 - verticalGap, labelSize.height / 2),
            maximumCenterY ?? (bounds.height - labelSize.height / 2)
        )
        let centerY = nonOverlappingCenterY(
            preferredCenterY,
            centerX: centerX,
            labelSize: labelSize,
            maximumCenterY: maximumCenterY,
            allowsDownwardFallback: allowsDownwardFallback,
            occupiedFrames: occupiedFrames
        )
        let frame = CGRect(
            x: centerX - labelSize.width / 2,
            y: centerY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        label.isHidden = false
        label.frame = frame
        occupiedFrames.append(frame.insetBy(dx: -2, dy: -2))
    }

    private func nonOverlappingCenterY(
        _ preferredCenterY: CGFloat,
        centerX: CGFloat,
        labelSize: CGSize,
        maximumCenterY: CGFloat?,
        allowsDownwardFallback: Bool,
        occupiedFrames: [CGRect]
    ) -> CGFloat {
        let minimumCenterY = labelSize.height / 2
        let resolvedMaximumCenterY = min(
            maximumCenterY ?? (bounds.height - labelSize.height / 2),
            bounds.height - labelSize.height / 2
        )
        let verticalStep = labelSize.height * 0.82
        var candidates = [
            preferredCenterY,
            preferredCenterY - verticalStep,
            preferredCenterY - verticalStep * 2,
            preferredCenterY - verticalStep * 3
        ]
        if allowsDownwardFallback {
            candidates.append(contentsOf: [
                preferredCenterY + verticalStep,
                preferredCenterY + verticalStep * 2
            ])
        }

        for candidate in candidates {
            let clampedCenterY = min(max(candidate, minimumCenterY), resolvedMaximumCenterY)
            let frame = CGRect(
                x: centerX - labelSize.width / 2,
                y: clampedCenterY - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            if !occupiedFrames.contains(where: { $0.intersects(frame) }) {
                return clampedCenterY
            }
        }

        return min(max(preferredCenterY, minimumCenterY), resolvedMaximumCenterY)
    }

    private func hideMarkerLabels() {
        [peakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
            label.isHidden = true
        }
    }
}
