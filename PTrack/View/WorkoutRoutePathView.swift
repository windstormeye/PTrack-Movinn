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
    private var currentLayerScale: CGFloat = 0
    private var strokeColor: UIColor = .black

    private let paddingRatio: Double = 0.18
    private var lineWidth: CGFloat = 2.8
    private static let maximumThumbnailPointCount = 180
    private static let sourceCache: NSCache<NSString, RouteSource> = {
        let cache = NSCache<NSString, RouteSource>()
        cache.countLimit = 240
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    private static let sourceBuildQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "studio.pj.PTrack.route-source-build"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private static let sourceBuildLock = NSLock()
    private static var pendingSourceBuilds: [String: PendingSourceBuild] = [:]

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
        updateLayerScaleIfNeeded()
        updatePathIfNeeded()
    }

    func configure(with workout: TrackedWorkout) {
        if routeID != workout.id {
            routeID = workout.id
            renderedSize = .zero

            if let cachedSource = Self.cachedSource(for: workout) {
                routeSource = cachedSource
            } else {
                routeSource = nil
                clearPath()
                Self.loadSource(for: workout, priority: .veryHigh) { [weak self] source in
                    guard let self, self.routeID == workout.id else {
                        return
                    }

                    self.routeSource = source
                    self.renderedSize = .zero
                    self.updatePathIfNeeded()
                }
            }
        }

        strokeColor = workout.routeColor
        shapeLayer.strokeColor = strokeColor.cgColor
        updatePathIfNeeded()
    }

    func setStrokeColor(_ color: UIColor) {
        strokeColor = color
        shapeLayer.strokeColor = color.cgColor
    }

    func setLineWidth(_ width: CGFloat) {
        lineWidth = width
        shapeLayer.lineWidth = width
    }

    func renderedContentBounds() -> CGRect? {
        guard let path = shapeLayer.path else {
            return nil
        }

        let strokePadding = max(lineWidth / 2 + 4, 5)
        let contentBounds = path.boundingBoxOfPath.insetBy(dx: -strokePadding, dy: -strokePadding)
        let clippedBounds = contentBounds.intersection(bounds)
        return clippedBounds.isNull || clippedBounds.isEmpty ? nil : clippedBounds
    }

    static func prewarmSource(for workout: TrackedWorkout) {
        loadSource(for: workout, priority: .low, completion: nil)
    }

    static func clearMemoryCache() {
        sourceCache.removeAllObjects()
    }

    static func cancelPrewarmSource(for workout: TrackedWorkout) {
        let key = sourceCacheKey(for: workout)
        sourceBuildLock.lock()
        defer {
            sourceBuildLock.unlock()
        }

        guard let pendingBuild = pendingSourceBuilds[key],
              pendingBuild.completions.isEmpty else {
            return
        }

        pendingBuild.operation.cancel()
        pendingSourceBuilds[key] = nil
    }

    private func configureLayer() {
        backgroundColor = .clear
        isOpaque = false

        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.lineJoin = .round
        shapeLayer.lineCap = .round
        shapeLayer.allowsEdgeAntialiasing = true
        shapeLayer.drawsAsynchronously = true
        shapeLayer.shouldRasterize = false
        updateLayerScaleIfNeeded()

        layer.addSublayer(shapeLayer)
    }

    private func clearPath() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = nil
        CATransaction.commit()
    }

    private func updateLayerScaleIfNeeded() {
        let scale = max(traitCollection.displayScale, window?.screen.scale ?? 0, 2)
        guard currentLayerScale != scale else {
            return
        }

        currentLayerScale = scale
        shapeLayer.contentsScale = scale
        shapeLayer.rasterizationScale = scale
    }

    private func updatePathIfNeeded() {
        guard renderedSize != bounds.size else {
            return
        }

        renderedSize = bounds.size

        guard let routeSource, routeSource.points.count > 1, bounds.width > 1, bounds.height > 1 else {
            clearPath()
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

    private static func loadSource(
        for workout: TrackedWorkout,
        priority: Operation.QueuePriority,
        completion: ((RouteSource) -> Void)?
    ) {
        let key = sourceCacheKey(for: workout)
        if let cachedSource = sourceCache.object(forKey: key as NSString) {
            if let completion {
                DispatchQueue.main.async {
                    completion(cachedSource)
                }
            }
            return
        }

        sourceBuildLock.lock()
        if var pendingBuild = pendingSourceBuilds[key] {
            if let completion {
                pendingBuild.completions.append(completion)
            }
            if priority.rawValue > pendingBuild.operation.queuePriority.rawValue {
                pendingBuild.operation.queuePriority = priority
            }
            pendingSourceBuilds[key] = pendingBuild
            sourceBuildLock.unlock()
            return
        }

        let operation = BlockOperation()
        operation.queuePriority = priority
        pendingSourceBuilds[key] = PendingSourceBuild(
            operation: operation,
            completions: completion.map { [$0] } ?? []
        )
        sourceBuildLock.unlock()

        operation.addExecutionBlock { [weak operation] in
            guard let operation else {
                return
            }

            guard !operation.isCancelled else {
                removePendingSourceBuild(for: key, operation: operation)
                return
            }

            let source = makeSource(for: workout)

            guard !operation.isCancelled else {
                removePendingSourceBuild(for: key, operation: operation)
                return
            }

            sourceCache.setObject(source, forKey: key as NSString, cost: source.memoryCost)

            sourceBuildLock.lock()
            let completions = pendingSourceBuilds.removeValue(forKey: key)?.completions ?? []
            sourceBuildLock.unlock()

            guard !completions.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                completions.forEach { $0(source) }
            }
        }

        sourceBuildQueue.addOperation(operation)
    }

    private static func cachedSource(for workout: TrackedWorkout) -> RouteSource? {
        sourceCache.object(forKey: sourceCacheKey(for: workout) as NSString)
    }

    private static func sourceCacheKey(for workout: TrackedWorkout) -> String {
        "\(workout.id)-gcj\(CoordinateTransformer.version)-p\(maximumThumbnailPointCount)"
    }

    private static func removePendingSourceBuild(for key: String, operation: Operation) {
        sourceBuildLock.lock()
        if pendingSourceBuilds[key]?.operation === operation {
            pendingSourceBuilds[key] = nil
        }
        sourceBuildLock.unlock()
    }

    private static func makeSource(for workout: TrackedWorkout) -> RouteSource {
        let cacheKey = sourceCacheKey(for: workout) as NSString
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
        sourceCache.setObject(source, forKey: cacheKey, cost: source.memoryCost)
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

private struct PendingSourceBuild {
    let operation: Operation
    var completions: [(RouteSource) -> Void]
}
