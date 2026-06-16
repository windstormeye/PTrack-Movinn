//
//  CoordinateTransformer.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation

enum CoordinateTransformer {
    static let version = 4

    private static let pi = Double.pi
    private static let axis = 6378245.0
    private static let offset = 0.00669342162296594323

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
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return false
        }

        if routeNeedsTransform {
            return true
        }

        return CoordinateRegionManager.shared.isCoordinateInMainlandChina(coordinate)
    }

    private static func shouldTransformRoute(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        guard let startCoordinate = coordinates.first(where: CLLocationCoordinate2DIsValid) else {
            return false
        }

        return CoordinateRegionManager.shared.isCoordinateInMainlandChina(startCoordinate)
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
