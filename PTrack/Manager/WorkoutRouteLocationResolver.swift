//
//  WorkoutRouteLocationResolver.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import CoreLocation

@MainActor
final class WorkoutRouteLocationResolver {
    static let shared = WorkoutRouteLocationResolver()

    private struct CachedLocation: Codable {
        let cacheVersion: Int?
        let title: String
        let countryCode: String?
        let countryName: String?
        let administrativeArea: String?
        let subAdministrativeArea: String?
        let locality: String?
        let subLocality: String?
        let fullAddress: String?
        let latitude: Double
        let longitude: Double
        let updatedAt: Date

        init(location: WorkoutRouteResolvedLocation) {
            cacheVersion = WorkoutRouteLocationResolver.currentCacheVersion
            title = location.title
            countryCode = location.countryCode
            countryName = location.countryName
            administrativeArea = location.administrativeArea
            subAdministrativeArea = location.subAdministrativeArea
            locality = location.locality
            subLocality = location.subLocality
            fullAddress = location.fullAddress
            latitude = location.latitude
            longitude = location.longitude
            updatedAt = location.updatedAt
        }

        var resolvedLocation: WorkoutRouteResolvedLocation {
            WorkoutRouteResolvedLocation(
                title: title,
                countryCode: countryCode,
                countryName: countryName,
                administrativeArea: administrativeArea,
                subAdministrativeArea: subAdministrativeArea,
                locality: locality,
                subLocality: subLocality,
                fullAddress: fullAddress,
                latitude: latitude,
                longitude: longitude,
                updatedAt: updatedAt
            )
        }
    }

    private let userDefaults: UserDefaults
    private var pendingCompletions: [String: [(WorkoutRouteResolvedLocation?) -> Void]] = [:]
    private var activeRequests: [String: CLGeocoder] = [:]

    private static let currentCacheVersion = 4
    private let cacheKeyPrefix = "workoutRouteLocation."
    private let cachedCoordinateToleranceMeters: CLLocationDistance = 100

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func cachedLocationTitle(for workout: TrackedWorkout) -> String? {
        cachedResolvedLocation(for: workout)?.title
    }

    func cachedResolvedLocation(for workout: TrackedWorkout) -> WorkoutRouteResolvedLocation? {
        guard let coordinate = startCoordinate(for: workout),
              let cachedLocation = cachedLocation(for: workout.id),
              cachedLocation.cacheVersion == Self.currentCacheVersion,
              isCachedLocation(cachedLocation, validFor: coordinate) else {
            return nil
        }

        return cachedLocation.resolvedLocation
    }

    func resolveLocationTitle(for workout: TrackedWorkout, completion: @escaping (String?) -> Void) {
        resolveLocation(for: workout) { location in
            completion(location?.title)
        }
    }

    func resolveLocation(
        for workout: TrackedWorkout,
        completion: @escaping (WorkoutRouteResolvedLocation?) -> Void
    ) {
        if let cachedLocation = cachedResolvedLocation(for: workout) {
            completion(cachedLocation)
            return
        }

        guard let coordinate = startCoordinate(for: workout) else {
            completion(nil)
            return
        }

        let localRegion = CoordinateRegionManager.shared.region(for: coordinate)
        let localLocation = Self.resolvedLocation(from: localRegion, coordinate: coordinate)
        if localRegion?.isChina == true, let localLocation {
            cache(CachedLocation(location: localLocation), for: workout.id)
            completion(localLocation)
            return
        }

        if pendingCompletions[workout.id] != nil {
            pendingCompletions[workout.id]?.append(completion)
            return
        }

        pendingCompletions[workout.id] = [completion]
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        activeRequests[workout.id] = geocoder

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let resolvedLocation = placemarks?.compactMap {
                Self.resolvedLocation(from: $0, coordinate: coordinate)
            }.first ?? localLocation

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if let resolvedLocation {
                    self.cache(CachedLocation(location: resolvedLocation), for: workout.id)
                }

                self.completePendingRequests(for: workout.id, location: resolvedLocation)
            }
        }
    }

    nonisolated private static func resolvedLocation(
        from region: CoordinateRegionResult?,
        coordinate: CLLocationCoordinate2D
    ) -> WorkoutRouteResolvedLocation? {
        guard let region,
              let title = region.title else {
            return nil
        }

        let fullAddress = uniqueComponents([
            region.countryName,
            region.provinceName,
            region.cityName,
            region.districtName
        ]).joined(separator: " ")

        return WorkoutRouteResolvedLocation(
            title: title,
            countryCode: region.countryCode,
            countryName: region.countryName,
            administrativeArea: region.provinceName,
            subAdministrativeArea: nil,
            locality: region.cityName,
            subLocality: region.districtName,
            fullAddress: fullAddress.isEmpty ? nil : fullAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            updatedAt: Date()
        )
    }

    private func startCoordinate(for workout: TrackedWorkout) -> CLLocationCoordinate2D? {
        workout.coordinates.first?.coordinate
    }

    private func cachedLocation(for workoutID: String) -> CachedLocation? {
        guard let data = userDefaults.data(forKey: cacheKey(for: workoutID)) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedLocation.self, from: data)
    }

    private func cache(_ location: CachedLocation, for workoutID: String) {
        guard let data = try? JSONEncoder().encode(location) else {
            return
        }

        userDefaults.set(data, forKey: cacheKey(for: workoutID))
    }

    private func cacheKey(for workoutID: String) -> String {
        "\(cacheKeyPrefix)\(workoutID)"
    }

    private func completePendingRequests(for workoutID: String, location: WorkoutRouteResolvedLocation?) {
        activeRequests[workoutID] = nil
        let completions = pendingCompletions.removeValue(forKey: workoutID) ?? []
        completions.forEach { $0(location) }
    }

    private func isCachedLocation(_ cachedLocation: CachedLocation, validFor coordinate: CLLocationCoordinate2D) -> Bool {
        let sourceLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let cachedCoordinate = CLLocationCoordinate2D(
            latitude: cachedLocation.latitude,
            longitude: cachedLocation.longitude
        )
        let storedLocation = CLLocation(
            latitude: cachedCoordinate.latitude,
            longitude: cachedCoordinate.longitude
        )

        return sourceLocation.distance(from: storedLocation) <= cachedCoordinateToleranceMeters
    }

    nonisolated private static func resolvedLocation(
        from placemark: CLPlacemark,
        coordinate: CLLocationCoordinate2D
    ) -> WorkoutRouteResolvedLocation? {
        let countryCode = placemark.isoCountryCode
        let countryName = placemark.country
        let administrativeArea = placemark.administrativeArea
        let subAdministrativeArea = placemark.subAdministrativeArea
        let locality = placemark.locality
        let subLocality = placemark.subLocality
        let fullAddress = uniqueComponents([
            placemark.name,
            subLocality,
            locality,
            subAdministrativeArea,
            administrativeArea,
            countryName
        ]).joined(separator: " ")
        let titleComponents = uniqueComponents([
            placemark.name,
            subLocality,
            locality,
            subAdministrativeArea,
            administrativeArea,
            countryName,
            fullAddress.isEmpty ? nil : fullAddress
        ])

        guard let title = titleComponents.first else {
            return nil
        }

        return WorkoutRouteResolvedLocation(
            title: title,
            countryCode: countryCode,
            countryName: countryName,
            administrativeArea: administrativeArea,
            subAdministrativeArea: subAdministrativeArea,
            locality: locality,
            subLocality: subLocality,
            fullAddress: fullAddress.isEmpty ? nil : fullAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            updatedAt: Date()
        )
    }

    nonisolated private static func uniqueComponents(_ components: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for component in components {
            let value = component?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty,
                  !isUnknownLocationValue(value),
                  !seen.contains(value) else {
                continue
            }

            seen.insert(value)
            result.append(value)
        }

        return result
    }

    nonisolated private static func isUnknownLocationValue(_ value: String) -> Bool {
        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let compactValue = normalizedValue
            .filter { !$0.isWhitespace && !$0.isPunctuation }

        return [
            "unknown",
            "unknownlocation",
            "unknownunknown",
            "未知",
            "未知位置",
            "未知未知",
            "不明",
            "不明な位置",
            "알수없음",
            "알수없는위치"
        ].contains(compactValue)
    }
}
