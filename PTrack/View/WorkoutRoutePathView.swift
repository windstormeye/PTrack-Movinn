//
//  WorkoutRoutePathView.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import MapKit
import UIKit

final class WorkoutRoutePathView: UIView {
    private let shapeLayer = CAShapeLayer()
    private var routeSource: RouteSource?
    private var routeID: String?
    private var renderedSize = CGSize.zero
    private var strokeColor: UIColor = .black

    private let paddingRatio: Double = 0.18
    private let lineWidth: CGFloat = 2.8
    private static let maximumThumbnailPointCount = 320
    private static let sourceCache: NSCache<NSString, RouteSource> = {
        let cache = NSCache<NSString, RouteSource>()
        cache.countLimit = 1_200
        return cache
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePathIfNeeded()
    }

    func configure(with workout: TrackedWorkout) {
        if routeID != workout.id {
            routeID = workout.id
            routeSource = Self.source(for: workout)
            renderedSize = .zero
        }

        strokeColor = workout.routeColor
        shapeLayer.strokeColor = strokeColor.cgColor
        updatePathIfNeeded()
    }

    static func prewarmSource(for workout: TrackedWorkout) {
        _ = source(for: workout)
    }

    private func configureLayer() {
        backgroundColor = .clear
        isOpaque = false

        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.lineJoin = .round
        shapeLayer.lineCap = .round
        shapeLayer.contentsScale = contentScaleFactor
        shapeLayer.drawsAsynchronously = true
        shapeLayer.shouldRasterize = true
        shapeLayer.rasterizationScale = contentScaleFactor

        layer.addSublayer(shapeLayer)
    }

    private func updatePathIfNeeded() {
        guard renderedSize != bounds.size else {
            return
        }

        renderedSize = bounds.size

        guard let routeSource, routeSource.points.count > 1, bounds.width > 1, bounds.height > 1 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.path = nil
            CATransaction.commit()
            return
        }

        let mapRect = paddedMapRect(
            for: routeSource.boundingRect,
            aspectRatio: Double(bounds.width / bounds.height),
            paddingRatio: paddingRatio
        )
        let path = CGMutablePath()

        for (index, mapPoint) in routeSource.points.enumerated() {
            let point = point(for: mapPoint, in: mapRect, canvasSize: bounds.size)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        shapeLayer.path = path
        shapeLayer.lineWidth = lineWidth
        CATransaction.commit()
    }

    private func paddedMapRect(
        for rect: MKMapRect,
        aspectRatio: Double,
        paddingRatio: Double
    ) -> MKMapRect {
        let minimumSide: Double = 180
        var width = max(rect.width, minimumSide)
        var height = max(rect.height, minimumSide)
        let centerX = rect.midX
        let centerY = rect.midY
        let rectAspectRatio = width / height

        if rectAspectRatio > aspectRatio {
            height = width / aspectRatio
        } else {
            width = height * aspectRatio
        }

        let paddingX = max(width * paddingRatio, 60)
        let paddingY = max(height * paddingRatio, 60)

        return MKMapRect(
            x: centerX - width / 2 - paddingX,
            y: centerY - height / 2 - paddingY,
            width: width + paddingX * 2,
            height: height + paddingY * 2
        )
    }

    private func point(
        for mapPoint: MKMapPoint,
        in mapRect: MKMapRect,
        canvasSize: CGSize
    ) -> CGPoint {
        let x = (mapPoint.x - mapRect.minX) / mapRect.width * canvasSize.width
        let y = (mapPoint.y - mapRect.minY) / mapRect.height * canvasSize.height
        return CGPoint(x: x, y: y)
    }

    private static func source(for workout: TrackedWorkout) -> RouteSource {
        let cacheKey = NSString(string: "\(workout.id)-gcj\(CoordinateTransformer.version)")
        if let cachedSource = sourceCache.object(forKey: cacheKey) {
            return cachedSource
        }

        let coordinates = sampledCoordinates(
            workout.displayCoordinates,
            maximumCount: maximumThumbnailPointCount
        )
        let points = coordinates.map(MKMapPoint.init)
        let boundingRect = points.reduce(MKMapRect.null) { rect, point in
            rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let source = RouteSource(points: points, boundingRect: boundingRect)
        sourceCache.setObject(source, forKey: cacheKey)
        return source
    }

    private static func sampledCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumCount, maximumCount > 2 else {
            return coordinates
        }

        let step = Double(coordinates.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            coordinates[Int(round(Double(index) * step))]
        }
    }
}

private final class RouteSource {
    let points: [MKMapPoint]
    let boundingRect: MKMapRect

    init(points: [MKMapPoint], boundingRect: MKMapRect) {
        self.points = points
        self.boundingRect = boundingRect
    }
}
