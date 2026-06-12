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

    static func cachedSnapshot(
        for workout: TrackedWorkout,
        size: CGSize,
        traitCollection: UITraitCollection,
        completion: @escaping (UIImage?) -> Void
    ) {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        let cacheKey = "\(workout.id)-\(Int(size.width * scale))x\(Int(size.height * scale))-\(traitCollection.userInterfaceStyle.rawValue)" as NSString

        if let image = imageCache.object(forKey: cacheKey) {
            completion(image)
            return
        }

        makeSnapshot(for: workout, size: size, traitCollection: traitCollection) { image in
            if let image {
                imageCache.setObject(image, forKey: cacheKey)
            }
            completion(image)
        }
    }

    private static func makeSnapshot(
        for workout: TrackedWorkout,
        size: CGSize,
        traitCollection: UITraitCollection,
        completion: @escaping (UIImage?) -> Void
    ) {
        let coordinates = workout.displayCoordinates
        guard coordinates.count > 1, size.width > 1, size.height > 1 else {
            completion(nil)
            return
        }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        options.traitCollection = traitCollection
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.mapRect = paddedMapRect(for: coordinates)

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

    private static func paddedMapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null

        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        let minimumSide: Double = 180
        let width = max(rect.width, minimumSide)
        let height = max(rect.height, minimumSide)
        let paddingX = max(width * 0.08, 40)
        let paddingY = max(height * 0.08, 40)
        let centerX = rect.midX
        let centerY = rect.midY

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
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)

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
            path.lineWidth = 4
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

            context.cgContext.setFillColor(color.cgColor)
            if let first = coordinates.first {
                let point = snapshot.point(for: first)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
            }
            if let last = coordinates.last {
                let point = snapshot.point(for: last)
                context.cgContext.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            }
        }
    }
}
