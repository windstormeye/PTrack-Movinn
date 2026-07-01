//
//  ElevationProfileView.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

final class ElevationProfileView: UIView {
    private let fillGradientLayer = CAGradientLayer()
    private let fillLayer = CAShapeLayer()
    private let curveLayer = CAShapeLayer()
    private let peakLabel = UILabel()
    private let heartRatePeakLabel = UILabel()
    private let powerPeakLabel = UILabel()
    private let temperaturePeakLabel = UILabel()
    private var samples: [RouteElevationSample] = []
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

    func configure(samples: [RouteElevationSample]) {
        self.samples = samples
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

        fillGradientLayer.colors = [
            UIColor.label.withAlphaComponent(0.11).cgColor,
            UIColor.label.withAlphaComponent(0).cgColor
        ]
        fillGradientLayer.locations = [0, 1]
        fillGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fillGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        fillGradientLayer.contentsScale = contentScaleFactor

        fillLayer.fillColor = UIColor.black.cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor
        fillLayer.contentsScale = contentScaleFactor
        fillGradientLayer.mask = fillLayer

        curveLayer.fillColor = UIColor.clear.cgColor
        curveLayer.strokeColor = UIColor.label.withAlphaComponent(0.76).cgColor
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
        label.layer.shadowColor = UIColor.systemBackground.cgColor
        label.layer.shadowOpacity = 0.82
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
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
        let curvePath = smoothedPath(for: points)
        let fillPath = curvePath.mutableCopy() ?? CGMutablePath()
        fillPath.addLine(to: CGPoint(x: bounds.width - horizontalPadding, y: bounds.height))
        fillPath.addLine(to: CGPoint(x: horizontalPadding, y: bounds.height))
        fillPath.closeSubpath()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillGradientLayer.frame = bounds
        fillLayer.frame = bounds
        curveLayer.frame = bounds
        fillLayer.path = fillPath
        curveLayer.path = curvePath
        CATransaction.commit()

        updatePeakLabels(with: points)
    }

    private func normalizedPoints(
        for samples: [RouteElevationSample],
        in size: CGSize
    ) -> [CGPoint] {
        let topPadding: CGFloat = 30
        let bottomPadding: CGFloat = 9
        let drawableWidth = max(size.width - horizontalPadding * 2, 1)
        let usableHeight = max(size.height - topPadding - bottomPadding, 1)
        let totalDistance = max(samples.last?.distanceMeters ?? 0, 1)
        let altitudeValues = samples.map(\.altitudeMeters)
        let minimumAltitude = altitudeValues.min() ?? 0
        let maximumAltitude = altitudeValues.max() ?? minimumAltitude
        let altitudeRange = max(maximumAltitude - minimumAltitude, 1)

        return samples.map { sample in
            let x = horizontalPadding + CGFloat(sample.distanceMeters / totalDistance) * drawableWidth
            let normalizedAltitude = (sample.altitudeMeters - minimumAltitude) / altitudeRange
            let y = size.height - bottomPadding - CGFloat(normalizedAltitude) * usableHeight
            return CGPoint(x: x, y: y)
        }
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

    private func updatePeakLabels(with points: [CGPoint]) {
        guard points.count == samples.count,
              let peakIndex = samples.indices.max(by: { samples[$0].altitudeMeters < samples[$1].altitudeMeters }) else {
            hideMarkerLabels()
            return
        }

        var occupiedFrames: [CGRect] = []
        placeMarkerLabel(peakLabel, at: points[peakIndex], occupiedFrames: &occupiedFrames)

        placeMetricMarkerLabel(
            heartRatePeakLabel,
            points: points,
            occupiedFrames: &occupiedFrames,
            requiresPositiveValue: true,
            value: \.heartRateBeatsPerMinute
        )
        placeMetricMarkerLabel(
            powerPeakLabel,
            points: points,
            occupiedFrames: &occupiedFrames,
            requiresPositiveValue: true,
            value: \.powerWatts
        )
        placeMetricMarkerLabel(
            temperaturePeakLabel,
            points: points,
            occupiedFrames: &occupiedFrames,
            requiresPositiveValue: false,
            value: \.temperatureCelsius
        )
    }

    private func placeMetricMarkerLabel(
        _ label: UILabel,
        points: [CGPoint],
        occupiedFrames: inout [CGRect],
        requiresPositiveValue: Bool,
        value: KeyPath<RouteElevationSample, Double?>
    ) {
        guard let peakIndex = metricPeakIndex(requiresPositiveValue: requiresPositiveValue, value: value) else {
            label.isHidden = true
            return
        }

        placeMarkerLabel(
            label,
            at: points[peakIndex],
            verticalGap: 13,
            maximumCenterY: bounds.height * 0.48,
            allowsDownwardFallback: false,
            occupiedFrames: &occupiedFrames
        )
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

    private func metricPeakIndex(
        requiresPositiveValue: Bool,
        value: KeyPath<RouteElevationSample, Double?>
    ) -> Int? {
        samples.indices
            .compactMap { index -> (index: Int, value: Double)? in
                guard let sampleValue = samples[index][keyPath: value],
                      sampleValue.isFinite,
                      !requiresPositiveValue || sampleValue > 0 else {
                    return nil
                }
                return (index, sampleValue)
            }
            .max { lhs, rhs in lhs.value < rhs.value }?.index
    }

    private func hideMarkerLabels() {
        [peakLabel, heartRatePeakLabel, powerPeakLabel, temperaturePeakLabel].forEach { label in
            label.isHidden = true
        }
    }
}
