//
//  GPXRouteExporter.swift
//  PTrack
//
//  Created by Codex on 2026/6/18.
//

import CoreLocation
import Foundation

enum GPXRouteExporterError: LocalizedError {
    case noRoutePoints

    var errorDescription: String? {
        switch self {
        case .noRoutePoints:
            return AppLocalization.text(.gpxExportNoRoute)
        }
    }
}

enum GPXRouteExporter {
    nonisolated static func data(
        routeName: String,
        coordinates routeCoordinates: [RouteCoordinate]
    ) throws -> Data {
        let coordinates = routeCoordinates.filter { coordinate in
            coordinate.latitude.isFinite
                && coordinate.longitude.isFinite
                && CLLocationCoordinate2DIsValid(coordinate.coordinate)
        }
        guard coordinates.count > 1 else {
            throw GPXRouteExporterError.noRoutePoints
        }

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]

        let routeName = escapedXML(routeName)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Movinn" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(routeName)</name>
            <time>\(timestampFormatter.string(from: Date()))</time>
          </metadata>
          <trk>
            <name>\(routeName)</name>
            <trkseg>

        """

        for coordinate in coordinates {
            xml += """
              <trkpt lat="\(coordinateValueString(coordinate.latitude))" lon="\(coordinateValueString(coordinate.longitude))">

            """
            if let altitude = coordinate.altitudeMeters, altitude.isFinite {
                xml += "        <ele>\(measurementString(altitude))</ele>\n"
            }
            xml += """
                    <time>\(timestampFormatter.string(from: coordinate.timestamp))</time>
                  </trkpt>

            """
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>

        """

        return Data(xml.utf8)
    }

    static func data(for workout: TrackedWorkout) throws -> Data {
        try data(
            routeName: AppLocalization.text(.gpxExportRouteName),
            coordinates: workout.routeDetailCoordinates
        )
    }

    nonisolated static func suggestedFileName(routeName: String) -> String {
        let routeName = sanitizedFileName(routeName)
        return "\(routeName).gpx"
    }

    static func suggestedFileName(for workout: TrackedWorkout) -> String {
        suggestedFileName(routeName: AppLocalization.text(.gpxExportRouteName))
    }

    nonisolated private static func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated private static func coordinateValueString(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated private static func measurementString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated private static func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = value
            .components(separatedBy: invalidCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let name = components.joined(separator: "-")
        return name.isEmpty ? "Movinn-Route" : String(name.prefix(60))
    }
}
