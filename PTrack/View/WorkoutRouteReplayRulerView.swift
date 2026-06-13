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
        profileView.configure(samples: elevationSamples)
    }

    func setProgress(_ progress: CGFloat, sendsAction: Bool = false) {
        self.progress = min(max(progress, 0), 1)
        updateProgressLayout(flushLayout: true)

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

    @objc private func handleProgressGesture(_ recognizer: UIGestureRecognizer) {
        let location = recognizer.location(in: profileView)
        let drawableWidth = max(profileView.bounds.width - horizontalPadding * 2, 1)
        setProgress((location.x - horizontalPadding) / drawableWidth, sendsAction: true)
    }
}

private final class ElevationProfileView: UIView {
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

    private func configureLayers() {
        isOpaque = false

        fillGradientLayer.colors = [
            UIColor.label.withAlphaComponent(0.11).cgColor,
            UIColor.label.withAlphaComponent(0).cgColor
        ]
        fillGradientLayer.locations = [0, 1]
        fillGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fillGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        fillGradientLayer.contentsScale = UIScreen.main.scale

        fillLayer.fillColor = UIColor.black.cgColor
        fillLayer.strokeColor = UIColor.clear.cgColor
        fillLayer.contentsScale = UIScreen.main.scale
        fillGradientLayer.mask = fillLayer

        curveLayer.fillColor = UIColor.clear.cgColor
        curveLayer.strokeColor = UIColor.label.withAlphaComponent(0.76).cgColor
        curveLayer.lineWidth = 2
        curveLayer.lineJoin = .round
        curveLayer.lineCap = .round
        curveLayer.contentsScale = UIScreen.main.scale
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
