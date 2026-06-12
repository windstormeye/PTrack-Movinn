//
//  CoordinateTransformer.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation

enum CoordinateTransformer {
    private static let pi = Double.pi
    private static let axis = 6378245.0
    private static let offset = 0.00669342162296594323

    static func displayCoordinate(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainlandChina(coordinate) else {
            return coordinate
        }

        return wgs84ToGCJ02(coordinate)
    }

    private static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let longitude = coordinate.longitude
        let latitude = coordinate.latitude

        guard longitude >= 73.66, longitude <= 135.05, latitude >= 3.86, latitude <= 53.55 else {
            return false
        }

        if longitude >= 113.52, longitude <= 113.63, latitude >= 22.10, latitude <= 22.22 {
            return false
        }

        if longitude >= 113.80, longitude <= 114.50, latitude >= 22.13, latitude <= 22.60 {
            return false
        }

        if longitude >= 119.30, longitude <= 122.10, latitude >= 21.70, latitude <= 25.50 {
            return false
        }

        return true
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
