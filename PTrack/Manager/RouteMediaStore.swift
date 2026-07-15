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
    private static let routePointSamplingBudget = 760

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
                DispatchQueue.global(qos: .userInitiated).async {
                    let cacheKey = Self.cacheKey(for: workout)
                    if let cachedResult = Self.resultCache.object(forKey: cacheKey) {
                        DispatchQueue.main.async {
                            completion(.success(cachedResult.items))
                        }
                        return
                    }
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
        var fingerprint: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: UInt64) {
            fingerprint ^= value
            fingerprint &*= 0x0000_0100_0000_01b3
        }

        let coordinates = workout.routeDetailCoordinates
        mix(UInt64(coordinates.count))
        for coordinate in coordinates {
            mix(coordinate.latitude.bitPattern)
            mix(coordinate.longitude.bitPattern)
            mix(coordinate.timestamp.timeIntervalSinceReferenceDate.bitPattern)
            mix(coordinate.altitudeMeters?.bitPattern ?? UInt64.max)
        }
        for segmentStartIndex in workout.routeDetailSegmentStartIndices.sorted() {
            mix(UInt64(segmentStartIndex))
        }
        return "\(workout.id)-geometry\(String(fingerprint, radix: 16))-\(CoordinateTransformer.cacheKey)" as NSString
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
        let routeSegments = routeMapPoints(for: workout)
        guard routeSegments.contains(where: { !$0.isEmpty }) else {
            return []
        }

        let routeSearchRect = expandedSearchRect(for: routeSegments, workout: workout)
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

            let distance = minimumDistance(from: mapPoint, toPolylines: routeSegments)
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

    private func routeMapPoints(for workout: TrackedWorkout) -> [[MKMapPoint]] {
        let sourceCoordinates = workout.routeDetailCoordinates
        guard !sourceCoordinates.isEmpty else {
            return []
        }

        let displayCoordinates = CoordinateTransformer.displayCoordinates(for: sourceCoordinates.map(\.coordinate))
        guard displayCoordinates.count == sourceCoordinates.count else {
            return []
        }

        let segmentStarts = workout.routeDetailSegmentStartIndices
            .filter { $0 > 0 && $0 < sourceCoordinates.count }
            .sorted()
        let boundaries = [0] + segmentStarts + [sourceCoordinates.count]
        let segmentRanges = zip(boundaries, boundaries.dropFirst()).compactMap { bounds -> Range<Int>? in
            guard bounds.0 < bounds.1 else {
                return nil
            }
            return bounds.0..<bounds.1
        }
        let sampledIndices = sampledRouteIndices(
            in: segmentRanges,
            maximumCount: Self.routePointSamplingBudget
        )

        return zip(segmentRanges, sampledIndices).compactMap { range, indices -> [MKMapPoint]? in
            guard !indices.isEmpty else {
                return nil
            }
            return shapePreservingMapPoints(
                displayCoordinates: displayCoordinates,
                range: range,
                maximumCount: indices.count
            ) ?? indices.map { MKMapPoint(displayCoordinates[$0]) }
        }
    }

    private func shapePreservingMapPoints(
        displayCoordinates: [CLLocationCoordinate2D],
        range: Range<Int>,
        maximumCount: Int
    ) -> [MKMapPoint]? {
        guard maximumCount > 0, !range.isEmpty else {
            return nil
        }
        if maximumCount == 1 {
            return [MKMapPoint(displayCoordinates[range.lowerBound])]
        }

        let coordinates = Array(displayCoordinates[range])
        var cumulativeDistances: [CLLocationDistance] = [0]
        cumulativeDistances.reserveCapacity(coordinates.count)
        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(
            latitude: coordinates[0].latitude,
            longitude: coordinates[0].longitude
        )
        for coordinate in coordinates.dropFirst() {
            let location = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            totalDistance += location.distance(from: previousLocation)
            cumulativeDistances.append(totalDistance)
            previousLocation = location
        }
        guard totalDistance > 0,
              let geometry = RouteSlopeGeometryPreparer.prepare(
                  coordinates: coordinates,
                  cumulativeDistances: cumulativeDistances,
                  toleranceMeters: 2,
                  maximumCount: maximumCount,
                  isCancelled: { false }
              ) else {
            return nil
        }
        return geometry.coordinates.map(MKMapPoint.init)
    }

    /// Shares one global sampling budget across every route segment. Under the
    /// normal budget each segment keeps both endpoints; unusually fragmented
    /// routes retain an evenly distributed subset of endpoint candidates rather
    /// than creating artificial connector lines between segments.
    private func sampledRouteIndices(
        in segmentRanges: [Range<Int>],
        maximumCount: Int
    ) -> [[Int]] {
        guard maximumCount > 0, !segmentRanges.isEmpty else {
            return []
        }

        let totalPointCount = segmentRanges.reduce(0) { $0 + $1.count }
        let targetCount = min(totalPointCount, maximumCount)
        guard totalPointCount > targetCount else {
            return segmentRanges.map(Array.init)
        }

        let endpointCount = segmentRanges.reduce(0) { partialResult, range in
            partialResult + min(range.count, 2)
        }
        guard endpointCount <= targetCount else {
            return endpointLimitedRouteIndices(
                in: segmentRanges,
                maximumCount: targetCount
            )
        }

        var targetCounts = segmentRanges.map { min($0.count, 2) }
        var remainingCount = targetCount - endpointCount
        let capacities = zip(segmentRanges, targetCounts).map { range, selectedCount in
            range.count - selectedCount
        }
        let totalCapacity = capacities.reduce(0, +)

        if remainingCount > 0, totalCapacity > 0 {
            var remainders: [(segmentIndex: Int, remainder: Int)] = []
            remainders.reserveCapacity(segmentRanges.count)
            for index in segmentRanges.indices {
                let scaledCapacity = remainingCount * capacities[index]
                let additionalCount = min(
                    capacities[index],
                    scaledCapacity / totalCapacity
                )
                targetCounts[index] += additionalCount
                remainders.append((index, scaledCapacity % totalCapacity))
            }

            remainingCount = targetCount - targetCounts.reduce(0, +)
            remainders.sort { lhs, rhs in
                if lhs.remainder != rhs.remainder {
                    return lhs.remainder > rhs.remainder
                }
                return lhs.segmentIndex < rhs.segmentIndex
            }
            for candidate in remainders where remainingCount > 0 {
                let index = candidate.segmentIndex
                guard targetCounts[index] < segmentRanges[index].count else {
                    continue
                }
                targetCounts[index] += 1
                remainingCount -= 1
            }
        }

        return zip(segmentRanges, targetCounts).map { range, count in
            evenlySpacedIndices(in: range, count: count)
        }
    }

    private func endpointLimitedRouteIndices(
        in segmentRanges: [Range<Int>],
        maximumCount: Int
    ) -> [[Int]] {
        var endpointCandidates: [(segmentIndex: Int, sourceIndex: Int)] = []
        endpointCandidates.reserveCapacity(segmentRanges.count * 2)
        for (segmentIndex, range) in segmentRanges.enumerated() {
            endpointCandidates.append((segmentIndex, range.lowerBound))
            if range.count > 1 {
                endpointCandidates.append((segmentIndex, range.upperBound - 1))
            }
        }

        var selectedIndices = Array(repeating: [Int](), count: segmentRanges.count)
        guard maximumCount > 0 else {
            return selectedIndices
        }
        if maximumCount == 1, let candidate = endpointCandidates.first {
            selectedIndices[candidate.segmentIndex].append(candidate.sourceIndex)
            return selectedIndices
        }

        for position in 0..<maximumCount {
            let candidateOffset = Int(round(
                Double(endpointCandidates.count - 1) * Double(position)
                    / Double(maximumCount - 1)
            ))
            let candidate = endpointCandidates[candidateOffset]
            selectedIndices[candidate.segmentIndex].append(candidate.sourceIndex)
        }
        return selectedIndices
    }

    private func evenlySpacedIndices(in range: Range<Int>, count: Int) -> [Int] {
        guard count > 0, !range.isEmpty else {
            return []
        }
        guard count < range.count else {
            return Array(range)
        }
        guard count > 1 else {
            return [range.lowerBound]
        }

        let lastOffset = range.count - 1
        return (0..<count).map { position in
            range.lowerBound + Int(round(
                Double(lastOffset) * Double(position) / Double(count - 1)
            ))
        }
    }

    private func matchingDistanceThreshold(for workout: TrackedWorkout) -> CLLocationDistance {
        Self.matchingDistanceThreshold
    }

    private func expandedSearchRect(
        for routeSegments: [[MKMapPoint]],
        workout: TrackedWorkout
    ) -> MKMapRect {
        guard let firstPoint = routeSegments.lazy.compactMap(\.first).first else {
            return .null
        }
        let initialRect = MKMapRect(x: firstPoint.x, y: firstPoint.y, width: 0, height: 0)
        let routeRect = routeSegments.lazy.joined().reduce(initialRect) { partialResult, point in
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

    private func minimumDistance(
        from point: MKMapPoint,
        toPolylines routeSegments: [[MKMapPoint]]
    ) -> CLLocationDistance {
        var minSquaredDistance = Double.greatestFiniteMagnitude

        for routePoints in routeSegments {
            guard let firstRoutePoint = routePoints.first else {
                continue
            }
            if routePoints.count == 1 {
                minSquaredDistance = min(
                    minSquaredDistance,
                    squaredMapPointDistance(from: point, to: firstRoutePoint)
                )
                continue
            }
            for index in 1..<routePoints.count {
                let distance = squaredMapPointDistance(
                    from: point,
                    toSegmentStart: routePoints[index - 1],
                    end: routePoints[index]
                )
                minSquaredDistance = min(minSquaredDistance, distance)
            }
        }

        guard minSquaredDistance.isFinite else {
            return .greatestFiniteMagnitude
        }
        let metersPerMapPoint = max(MKMetersPerMapPointAtLatitude(point.coordinate.latitude), .leastNonzeroMagnitude)
        return sqrt(minSquaredDistance) * metersPerMapPoint
    }

    private func squaredMapPointDistance(from lhs: MKMapPoint, to rhs: MKMapPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
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
