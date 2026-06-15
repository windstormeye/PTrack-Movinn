//
//  CoordinateTransformer.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation

enum CoordinateTransformer {
    static let version = 3

    private static let pi = Double.pi
    private static let axis = 6378245.0
    private static let offset = 0.00669342162296594323
    private static let maximumRouteDecisionSampleCount = 180
    private static let mainlandChinaBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 39.5, longitude: 73.5),
        CLLocationCoordinate2D(latitude: 35.5, longitude: 75.0),
        CLLocationCoordinate2D(latitude: 32.0, longitude: 78.0),
        CLLocationCoordinate2D(latitude: 29.0, longitude: 78.5),
        CLLocationCoordinate2D(latitude: 27.2, longitude: 81.0),
        CLLocationCoordinate2D(latitude: 27.8, longitude: 88.0),
        CLLocationCoordinate2D(latitude: 27.6, longitude: 91.0),
        CLLocationCoordinate2D(latitude: 28.0, longitude: 94.0),
        CLLocationCoordinate2D(latitude: 23.8, longitude: 97.5),
        CLLocationCoordinate2D(latitude: 21.0, longitude: 98.7),
        CLLocationCoordinate2D(latitude: 21.0, longitude: 101.2),
        CLLocationCoordinate2D(latitude: 22.4, longitude: 102.3),
        CLLocationCoordinate2D(latitude: 22.7, longitude: 104.5),
        CLLocationCoordinate2D(latitude: 21.8, longitude: 106.7),
        CLLocationCoordinate2D(latitude: 21.5, longitude: 108.0),
        CLLocationCoordinate2D(latitude: 21.4, longitude: 109.6),
        CLLocationCoordinate2D(latitude: 21.5, longitude: 111.0),
        CLLocationCoordinate2D(latitude: 21.8, longitude: 112.8),
        CLLocationCoordinate2D(latitude: 22.2, longitude: 114.3),
        CLLocationCoordinate2D(latitude: 23.0, longitude: 116.5),
        CLLocationCoordinate2D(latitude: 24.0, longitude: 118.0),
        CLLocationCoordinate2D(latitude: 25.5, longitude: 119.8),
        CLLocationCoordinate2D(latitude: 27.5, longitude: 120.5),
        CLLocationCoordinate2D(latitude: 30.8, longitude: 121.8),
        CLLocationCoordinate2D(latitude: 32.8, longitude: 121.0),
        CLLocationCoordinate2D(latitude: 39.0, longitude: 122.0),
        CLLocationCoordinate2D(latitude: 40.0, longitude: 124.0),
        CLLocationCoordinate2D(latitude: 39.8, longitude: 124.6),
        CLLocationCoordinate2D(latitude: 40.6, longitude: 125.0),
        CLLocationCoordinate2D(latitude: 42.0, longitude: 126.7),
        CLLocationCoordinate2D(latitude: 42.5, longitude: 129.5),
        CLLocationCoordinate2D(latitude: 44.0, longitude: 130.8),
        CLLocationCoordinate2D(latitude: 48.0, longitude: 133.0),
        CLLocationCoordinate2D(latitude: 48.4, longitude: 135.1),
        CLLocationCoordinate2D(latitude: 49.5, longitude: 134.7),
        CLLocationCoordinate2D(latitude: 49.6, longitude: 127.5),
        CLLocationCoordinate2D(latitude: 53.5, longitude: 124.0),
        CLLocationCoordinate2D(latitude: 53.3, longitude: 120.0),
        CLLocationCoordinate2D(latitude: 49.5, longitude: 117.0),
        CLLocationCoordinate2D(latitude: 49.2, longitude: 111.0),
        CLLocationCoordinate2D(latitude: 50.5, longitude: 106.0),
        CLLocationCoordinate2D(latitude: 49.0, longitude: 97.0),
        CLLocationCoordinate2D(latitude: 46.5, longitude: 91.0),
        CLLocationCoordinate2D(latitude: 49.0, longitude: 86.0),
        CLLocationCoordinate2D(latitude: 45.0, longitude: 80.0)
    ]
    private static let hainanBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 18.0, longitude: 108.3),
        CLLocationCoordinate2D(latitude: 18.0, longitude: 111.2),
        CLLocationCoordinate2D(latitude: 20.3, longitude: 111.2),
        CLLocationCoordinate2D(latitude: 20.3, longitude: 108.3)
    ]

    static func displayCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        displayCoordinate(for: coordinate, routeNeedsTransform: false)
    }

    static func displayCoordinates(for coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let routeNeedsTransform = shouldTransformRoute(coordinates)
        return coordinates.map { displayCoordinate(for: $0, routeNeedsTransform: routeNeedsTransform) }
    }

    private static func displayCoordinate(
        for coordinate: CLLocationCoordinate2D,
        routeNeedsTransform: Bool
    ) -> CLLocationCoordinate2D {
        guard shouldTransform(coordinate, routeNeedsTransform: routeNeedsTransform) else {
            return coordinate
        }

        return wgs84ToGCJ02(coordinate)
    }

    private static func shouldTransform(
        _ coordinate: CLLocationCoordinate2D,
        routeNeedsTransform: Bool
    ) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate),
              isInChinaTransformBounds(coordinate),
              !isInTaiwan(coordinate) else {
            return false
        }

        if routeNeedsTransform {
            return isLikelyMainlandChina(coordinate)
        }

        return isLikelyMainlandChina(coordinate)
    }

    private static func shouldTransformRoute(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        let sampledCoordinates = routeDecisionSample(from: coordinates)
        guard !sampledCoordinates.isEmpty else {
            return false
        }

        let mainlandCount = sampledCoordinates.filter { isLikelyMainlandChina($0) }.count
        let minimumMainlandCount = min(3, sampledCoordinates.count)
        guard mainlandCount >= minimumMainlandCount else {
            return false
        }

        return Double(mainlandCount) / Double(sampledCoordinates.count) >= 0.58
    }

    private static func routeDecisionSample(from coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let validCoordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard validCoordinates.count > maximumRouteDecisionSampleCount else {
            return validCoordinates
        }

        let step = Double(validCoordinates.count - 1) / Double(maximumRouteDecisionSampleCount - 1)
        return (0..<maximumRouteDecisionSampleCount).map { index in
            validCoordinates[Int(round(Double(index) * step))]
        }
    }

    private static func isLikelyMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        isInChinaTransformBounds(coordinate)
            && !isInTaiwan(coordinate)
            && !isClearlyHongKongOrMacau(coordinate)
            && isInMainlandChinaLandApproximation(coordinate)
    }

    private static func isInChinaTransformBounds(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        return longitude >= 72.004
            && longitude <= 137.8347
            && latitude >= 0.8293
            && latitude <= 55.8271
    }

    private static func isInTaiwan(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        return longitude >= 119.30
            && longitude <= 122.10
            && latitude >= 21.70
            && latitude <= 25.50
    }

    private static func isClearlyHongKongOrMacau(_ coordinate: CLLocationCoordinate2D) -> Bool {
        isInMacauCore(coordinate) || isInHongKongCore(coordinate)
    }

    private static func isInMacauCore(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        return longitude >= 113.528
            && longitude <= 113.598
            && latitude >= 22.105
            && latitude <= 22.215
    }

    private static func isInHongKongCore(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        guard longitude >= 113.80,
              longitude <= 114.45,
              latitude >= 22.13,
              latitude <= 22.58 else {
            return false
        }

        if latitude <= 22.38 {
            return true
        }

        return latitude <= hongKongNorthernBoundaryLatitude(for: longitude)
    }

    private static func hongKongNorthernBoundaryLatitude(for longitude: Double) -> Double {
        if longitude < 113.95 {
            return 22.43 + (longitude - 113.80) / 0.15 * 0.04
        }

        if longitude < 114.15 {
            return 22.50
        }

        return 22.53
    }

    private static func isInMainlandChinaLandApproximation(_ coordinate: CLLocationCoordinate2D) -> Bool {
        isCoordinate(coordinate, inside: mainlandChinaBoundary) || isCoordinate(coordinate, inside: hainanBoundary)
    }

    private static func isCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        inside polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = polygon.count - 1
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let latitudeIntersects = (current.latitude > latitude) != (previous.latitude > latitude)

            if latitudeIntersects {
                let longitudeAtLatitude = (previous.longitude - current.longitude)
                    * (latitude - current.latitude)
                    / (previous.latitude - current.latitude)
                    + current.longitude

                if longitude < longitudeAtLatitude {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude
        var latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
        var longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radianLatitude = latitude / 180.0 * pi
        var magic = sin(radianLatitude)
        magic = 1 - offset * magic * magic
        let sqrtMagic = sqrt(magic)
        latitudeDelta = (latitudeDelta * 180.0) / ((axis * (1 - offset)) / (magic * sqrtMagic) * pi)
        longitudeDelta = (longitudeDelta * 180.0) / (axis / sqrtMagic * cos(radianLatitude) * pi)
        return CLLocationCoordinate2D(latitude: latitude + latitudeDelta, longitude: longitude + longitudeDelta)
    }

    private static func transformLatitude(_ longitude: Double, _ latitude: Double) -> Double {
        var result = -100.0 + 2.0 * longitude + 3.0 * latitude + 0.2 * latitude * latitude
        result += 0.1 * longitude * latitude + 0.2 * sqrt(abs(longitude))
        result += (20.0 * sin(6.0 * longitude * pi) + 20.0 * sin(2.0 * longitude * pi)) * 2.0 / 3.0
        result += (20.0 * sin(latitude * pi) + 40.0 * sin(latitude / 3.0 * pi)) * 2.0 / 3.0
        result += (160.0 * sin(latitude / 12.0 * pi) + 320 * sin(latitude * pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(_ longitude: Double, _ latitude: Double) -> Double {
        var result = 300.0 + longitude + 2.0 * latitude + 0.1 * longitude * longitude
        result += 0.1 * longitude * latitude + 0.1 * sqrt(abs(longitude))
        result += (20.0 * sin(6.0 * longitude * pi) + 20.0 * sin(2.0 * longitude * pi)) * 2.0 / 3.0
        result += (20.0 * sin(longitude * pi) + 40.0 * sin(longitude / 3.0 * pi)) * 2.0 / 3.0
        result += (150.0 * sin(longitude / 12.0 * pi) + 300.0 * sin(longitude / 30.0 * pi)) * 2.0 / 3.0
        return result
    }
}
