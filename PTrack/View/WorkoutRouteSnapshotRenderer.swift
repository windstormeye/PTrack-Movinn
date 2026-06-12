//
//  WorkoutRouteSnapshotRenderer.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import MapKit
import UIKit

enum WorkoutRouteSnapshotRenderer {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static let routeLineWidth: CGFloat = 4.5
    private static let mapPaddingRatio = 0.10
    private static let routeOnlyPaddingRatio = 0.18

    static func cachedSnapshot(
        for workout: TrackedWorkout,
        size: CGSize,
        showsMap: Bool,
        traitCollection: UITraitCollection,
        completion: @escaping (UIImage?) -> Void
    ) {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        let cacheSizeKey = "\(Int(size.width * scale))x\(Int(size.height * scale))"
        let cacheKey = "\(workout.id)-\(cacheSizeKey)-\(showsMap)-\(traitCollection.userInterfaceStyle.rawValue)" as NSString

        if let image = imageCache.object(forKey: cacheKey) {
            completion(image)
            return
        }

        makeSnapshot(for: workout, size: size, showsMap: showsMap, traitCollection: traitCollection) { image in
            if let image {
                imageCache.setObject(image, forKey: cacheKey)
            }
            completion(image)
        }
    }

    private static func makeSnapshot(
        for workout: TrackedWorkout,
        size: CGSize,
        showsMap: Bool,
        traitCollection: UITraitCollection,
        completion: @escaping (UIImage?) -> Void
    ) {
        let coordinates = workout.displayCoordinates
        guard coordinates.count > 1, size.width > 1, size.height > 1 else {
            completion(nil)
            return
        }

        guard showsMap else {
            completion(drawRouteOnly(coordinates, color: workout.routeColor, size: size))
            return
        }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        options.traitCollection = traitCollection
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.mapRect = paddedMapRect(for: coordinates, aspectRatio: Double(size.width / size.height), paddingRatio: mapPaddingRatio)

        MKMapSnapshotter(options: options).start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, error in
            guard let snapshot, error == nil else {
                print("PTrack Snapshot: failed to create snapshot: \(String(describing: error))")
                completion(nil)
                return
            }

            let image = drawRoute(coordinates, color: workout.routeColor, on: snapshot)
            completion(image)
        }
    }

    private static func paddedMapRect(
        for coordinates: [CLLocationCoordinate2D],
        aspectRatio: Double,
        paddingRatio: Double
    ) -> MKMapRect {
        var rect = MKMapRect.null

        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

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

    private static func drawRoute(
        _ coordinates: [CLLocationCoordinate2D],
        color: UIColor,
        on snapshot: MKMapSnapshotter.Snapshot
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)

        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            for (index, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            color.setStroke()
            path.lineWidth = routeLineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

            context.cgContext.setFillColor(color.cgColor)
            if let first = coordinates.first {
                let point = snapshot.point(for: first)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            }
            if let last = coordinates.last {
                let point = snapshot.point(for: last)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            }
        }
    }

    private static func drawRouteOnly(
        _ coordinates: [CLLocationCoordinate2D],
        color: UIColor,
        size: CGSize
    ) -> UIImage {
        let mapRect = paddedMapRect(
            for: coordinates,
            aspectRatio: Double(size.width / size.height),
            paddingRatio: routeOnlyPaddingRatio
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { context in
            let path = UIBezierPath()

            for (index, coordinate) in coordinates.enumerated() {
                let point = point(for: coordinate, in: mapRect, canvasSize: size)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            color.setStroke()
            path.lineWidth = routeLineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

            context.cgContext.setFillColor(color.cgColor)
            if let first = coordinates.first {
                let point = point(for: first, in: mapRect, canvasSize: size)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            }
            if let last = coordinates.last {
                let point = point(for: last, in: mapRect, canvasSize: size)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            }
        }
    }

    private static func point(
        for coordinate: CLLocationCoordinate2D,
        in mapRect: MKMapRect,
        canvasSize: CGSize
    ) -> CGPoint {
        let mapPoint = MKMapPoint(coordinate)
        let x = (mapPoint.x - mapRect.minX) / mapRect.width * canvasSize.width
        let y = (mapPoint.y - mapRect.minY) / mapRect.height * canvasSize.height
        return CGPoint(x: x, y: y)
    }
}
