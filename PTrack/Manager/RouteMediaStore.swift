//
//  RouteMediaStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import HealthKit
import MapKit
import Photos

final class RouteMediaStore {
    private static let resultCache: NSCache<NSString, RouteMediaResultBox> = {
        let cache = NSCache<NSString, RouteMediaResultBox>()
        cache.countLimit = 128
        return cache
    }()
    private static let imageManager = PHCachingImageManager()
    private static let matchingDistanceThreshold: CLLocationDistance = 200

    static func clearMemoryCache() {
        resultCache.removeAllObjects()
        imageManager.stopCachingImagesForAllAssets()
        RouteMediaThumbnailCache.removeAllImages()
    }

    func loadMedia(
        for workout: TrackedWorkout,
        completion: @escaping (Result<[RouteMediaItem], Error>) -> Void
    ) {
        requestAuthorization { [weak self] authorizationResult in
            guard let self else { return }

            switch authorizationResult {
            case .success:
                let cacheKey = Self.cacheKey(for: workout)
                if let cachedResult = Self.resultCache.object(forKey: cacheKey) {
                    completion(.success(cachedResult.items))
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    let mediaItems = self.findMedia(for: workout)
                    Self.resultCache.setObject(RouteMediaResultBox(items: mediaItems), forKey: cacheKey)
                    DispatchQueue.main.async {
                        completion(.success(mediaItems))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func cacheKey(for workout: TrackedWorkout) -> NSString {
        "\(workout.id)-detail\(workout.routeDetailCoordinates.count)-\(CoordinateTransformer.cacheKey)" as NSString
    }

    private func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        switch PhotoLibraryAuthorizationManager.authorizationState {
        case .authorized:
            completion(.success(()))
        case .notDetermined:
            PhotoLibraryAuthorizationManager.requestFullAccess { authorizationState in
                switch authorizationState {
                case .authorized:
                    completion(.success(()))
                case .notDetermined, .needsAttention:
                    completion(.failure(RouteMediaStoreError.authorizationDenied))
                }
            }
        case .needsAttention:
            completion(.failure(RouteMediaStoreError.authorizationDenied))
        }
    }

    private func findMedia(for workout: TrackedWorkout) -> [RouteMediaItem] {
        let routePoints = routeMapPoints(for: workout)
        guard routePoints.count > 1 else {
            return []
        }

        let routeSearchRect = expandedSearchRect(for: routePoints, workout: workout)
        let assets = fetchCandidateAssets(for: workout)
        let distanceThreshold = matchingDistanceThreshold(for: workout)
        var mediaItems: [RouteMediaItem] = []
        mediaItems.reserveCapacity(min(assets.count, 48))
        var locationAssetCount = 0
        var routeBoundsCandidateCount = 0

        for asset in assets {
            guard let location = asset.location else {
                continue
            }
            locationAssetCount += 1

            let displayCoordinate = CoordinateTransformer.displayCoordinate(for: location.coordinate)
            guard CLLocationCoordinate2DIsValid(displayCoordinate) else {
                continue
            }

            let mapPoint = MKMapPoint(displayCoordinate)
            guard routeSearchRect.contains(mapPoint) else {
                continue
            }
            routeBoundsCandidateCount += 1

            let distance = minimumDistance(from: mapPoint, toPolyline: routePoints)
            guard distance <= distanceThreshold else {
                continue
            }

            mediaItems.append(
                RouteMediaItem(
                    asset: asset,
                    coordinate: displayCoordinate,
                    distanceFromRoute: distance
                )
            )
        }

        Self.imageManager.startCachingImages(
            for: mediaItems.map(\.asset),
            targetSize: CGSize(width: 160, height: 160),
            contentMode: .aspectFill,
            options: nil
        )

        print(
            "PTrack Photos: date=\(workout.dateText), fetched=\(assets.count), located=\(locationAssetCount), nearBounds=\(routeBoundsCandidateCount), matched=\(mediaItems.count), threshold=\(Int(distanceThreshold))m"
        )

        return mediaItems
            .sorted { lhs, rhs in
                if lhs.asset.creationDate == rhs.asset.creationDate {
                    return lhs.distanceFromRoute < rhs.distanceFromRoute
                }
                return (lhs.asset.creationDate ?? .distantPast) < (rhs.asset.creationDate ?? .distantPast)
            }
    }

    private func fetchCandidateAssets(for workout: TrackedWorkout) -> [PHAsset] {
        let mergedRouteDateRanges = workout.routeCollectionMergePhotoDateRanges
        guard mergedRouteDateRanges.isEmpty else {
            return fetchCandidateAssets(in: mergedRouteDateRanges)
        }

        let startDate = workout.startDate
        let endDate = (workout.endDate ?? workout.startDate.addingTimeInterval(workout.durationSeconds ?? 0))
        return fetchCandidateAssets(in: [(startDate, endDate)])
    }

    private func fetchCandidateAssets(in dateRanges: [(start: Date, end: Date)]) -> [PHAsset] {
        var assets: [PHAsset] = []
        var seenAssetIDs = Set<String>()

        for dateRange in dateRanges {
            assets.append(contentsOf: fetchCandidateAssets(from: dateRange.start, to: dateRange.end).filter { asset in
                seenAssetIDs.insert(asset.localIdentifier).inserted
            })
        }

        return assets.sorted { lhs, rhs in
            (lhs.creationDate ?? .distantPast) < (rhs.creationDate ?? .distantPast)
        }
    }

    private func fetchCandidateAssets(from startDate: Date, to endDate: Date) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = false
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND (mediaType == %d OR mediaType == %d)",
            startDate as NSDate,
            endDate as NSDate,
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    private func routeMapPoints(for workout: TrackedWorkout) -> [MKMapPoint] {
        let sourceCoordinates = workout.routeDetailCoordinates
        guard sourceCoordinates.count > 1 else {
            return []
        }

        let displayCoordinates = CoordinateTransformer.displayCoordinates(for: sourceCoordinates.map(\.coordinate))
        let targetCount = min(sourceCoordinates.count, 760)
        let step = Double(sourceCoordinates.count - 1) / Double(max(targetCount - 1, 1))

        return (0..<targetCount).map { index in
            let sourceIndex = min(Int(round(Double(index) * step)), sourceCoordinates.count - 1)
            return MKMapPoint(displayCoordinates[sourceIndex])
        }
    }

    private func matchingDistanceThreshold(for workout: TrackedWorkout) -> CLLocationDistance {
        Self.matchingDistanceThreshold
    }

    private func expandedSearchRect(for routePoints: [MKMapPoint], workout: TrackedWorkout) -> MKMapRect {
        let firstPoint = routePoints[0]
        let initialRect = MKMapRect(x: firstPoint.x, y: firstPoint.y, width: 0, height: 0)
        let routeRect = routePoints.dropFirst().reduce(initialRect) { partialResult, point in
            partialResult.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let latitude = routeRectCenterCoordinate(for: routeRect).latitude
        let metersPerMapPoint = max(MKMetersPerMapPointAtLatitude(latitude), .leastNonzeroMagnitude)
        let paddingMeters = matchingDistanceThreshold(for: workout) + 40
        let paddingMapPoints = paddingMeters / metersPerMapPoint
        return routeRect.insetBy(dx: -paddingMapPoints, dy: -paddingMapPoints)
    }

    private func routeRectCenterCoordinate(for rect: MKMapRect) -> CLLocationCoordinate2D {
        MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }

    private func minimumDistance(from point: MKMapPoint, toPolyline routePoints: [MKMapPoint]) -> CLLocationDistance {
        var minSquaredDistance = Double.greatestFiniteMagnitude

        for index in 1..<routePoints.count {
            let distance = squaredMapPointDistance(
                from: point,
                toSegmentStart: routePoints[index - 1],
                end: routePoints[index]
            )
            minSquaredDistance = min(minSquaredDistance, distance)
        }

        let metersPerMapPoint = max(MKMetersPerMapPointAtLatitude(point.coordinate.latitude), .leastNonzeroMagnitude)
        return sqrt(minSquaredDistance) * metersPerMapPoint
    }

    private func squaredMapPointDistance(
        from point: MKMapPoint,
        toSegmentStart start: MKMapPoint,
        end: MKMapPoint
    ) -> Double {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let segmentLengthSquared = segmentX * segmentX + segmentY * segmentY

        guard segmentLengthSquared > 0 else {
            let dx = point.x - start.x
            let dy = point.y - start.y
            return dx * dx + dy * dy
        }

        let pointX = point.x - start.x
        let pointY = point.y - start.y
        let progress = max(0, min(1, (pointX * segmentX + pointY * segmentY) / segmentLengthSquared))
        let projectedX = start.x + progress * segmentX
        let projectedY = start.y + progress * segmentY
        let dx = point.x - projectedX
        let dy = point.y - projectedY
        return dx * dx + dy * dy
    }
}

enum PhotoLibraryAuthorizationState {
    case notDetermined
    case authorized
    case needsAttention
}

enum PhotoLibraryAuthorizationManager {
    static var authorizationState: PhotoLibraryAuthorizationState {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited, .denied, .restricted:
            return .needsAttention
        @unknown default:
            return .needsAttention
        }
    }

    static func requestFullAccess(completion: @escaping (PhotoLibraryAuthorizationState) -> Void) {
        switch authorizationState {
        case .authorized, .needsAttention:
            DispatchQueue.main.async {
                completion(authorizationState)
            }
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async {
                    completion(authorizationState)
                }
            }
        }
    }
}

enum RouteMediaVisibilityPreference {
    private static let defaultsKey = "studio.pj.PTrack.routeMediaVisibility.isEnabled"

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: defaultsKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }
}
