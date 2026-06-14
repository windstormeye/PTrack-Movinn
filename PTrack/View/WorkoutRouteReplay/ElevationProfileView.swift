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

    func setPeakHighlighted(_ highlighted: Bool, animated: Bool) {
        let transform = highlighted ? CGAffineTransform(scaleX: 1.24, y: 1.24) : .identity
        guard animated else {
            peakLabel.transform = transform
            return
        }

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.peakLabel.transform = transform
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

        peakLabel.text = "⛰️"
        peakLabel.font = .systemFont(ofSize: 15)
        peakLabel.textAlignment = .center
        peakLabel.isHidden = true
        addSubview(peakLabel)
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
            peakLabel.isHidden = true
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

        updatePeakLabel(with: points)
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

    private func updatePeakLabel(with points: [CGPoint]) {
        guard points.count == samples.count,
              let peakIndex = samples.indices.max(by: { samples[$0].altitudeMeters < samples[$1].altitudeMeters }) else {
            peakLabel.isHidden = true
            return
        }

        let peakPoint = points[peakIndex]
        let labelSize = CGSize(width: 24, height: 24)
        let centerX = min(max(peakPoint.x, labelSize.width / 2), bounds.width - labelSize.width / 2)
        let centerY = min(
            max(peakPoint.y - labelSize.height / 2 - 6, labelSize.height / 2),
            bounds.height - labelSize.height / 2
        )

        peakLabel.isHidden = false
        peakLabel.frame = CGRect(
            x: centerX - labelSize.width / 2,
            y: centerY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }
}
