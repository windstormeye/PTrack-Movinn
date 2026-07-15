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
        coordinates routeCoordinates: [RouteCoordinate],
        segmentStartIndices: Set<Int> = [],
        appMetadata: GPXRouteAppMetadata? = nil
    ) throws -> Data {
        let segments = validSegments(
            from: routeCoordinates,
            segmentStartIndices: segmentStartIndices
        )
        guard segments.reduce(0, { $0 + $1.count }) > 1 else {
            throw GPXRouteExporterError.noRoutePoints
        }

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let routeName = escapedXML(routeName)
        let encodedAppMetadata: String?
        if let appMetadata {
            encodedAppMetadata = try JSONEncoder().encode(appMetadata).base64EncodedString()
        } else {
            encodedAppMetadata = nil
        }
        let appMetadataXML = encodedAppMetadata.map { encodedValue in
            """
                <extensions>
                  <movinn:routeData encoding="base64">\(encodedValue)</movinn:routeData>
                </extensions>

            """
        } ?? ""
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Movinn" xmlns="http://www.topografix.com/GPX/1/1" xmlns:movinn="\(GPXRouteAppMetadata.namespaceURI)">
          <metadata>
            <name>\(routeName)</name>
            <time>\(timestampFormatter.string(from: Date()))</time>
        \(appMetadataXML)
          </metadata>
          <trk>
            <name>\(routeName)</name>

        """

        for segment in segments {
            xml += "    <trkseg>\n"
            for coordinate in segment {
                xml += """
                  <trkpt lat="\(coordinateValueString(coordinate.latitude))" lon="\(coordinateValueString(coordinate.longitude))">

                """
                if let altitude = coordinate.altitudeMeters, altitude.isFinite {
                    xml += "        <ele>\(measurementString(altitude))</ele>\n"
                }
                xml += "        <time>\(timestampFormatter.string(from: coordinate.timestamp))</time>\n"

                let sourceDistanceMeters = GPXRoutePointExtensions.validatedSourceDistanceMeters(
                    coordinate.sourceDistanceMeters
                )
                let gradeRatio = GPXRoutePointExtensions.validatedGradeRatio(coordinate.gradeRatio)
                if sourceDistanceMeters != nil || gradeRatio != nil {
                    xml += "        <extensions>\n"
                    if let sourceDistanceMeters {
                        xml += "          <movinn:sourceDistanceMeters>\(pointExtensionValueString(sourceDistanceMeters))</movinn:sourceDistanceMeters>\n"
                    }
                    if let gradeRatio {
                        xml += "          <movinn:gradeRatio>\(pointExtensionValueString(gradeRatio))</movinn:gradeRatio>\n"
                    }
                    xml += "        </extensions>\n"
                }
                xml += "      </trkpt>\n"
            }
            xml += "    </trkseg>\n"
        }

        xml += """
          </trk>
        </gpx>

        """

        return Data(xml.utf8)
    }

    static func data(for workout: TrackedWorkout) throws -> Data {
        try data(
            routeName: AppLocalization.text(.gpxExportRouteName),
            coordinates: workout.routeDetailCoordinates,
            segmentStartIndices: workout.routeDetailSegmentStartIndices
        )
    }

    nonisolated static func iCloudDocumentData(for workout: TrackedWorkout) throws -> Data {
        let routeCollectionID = workout.routeCollectionIdentifier ?? workout.id
        let routeName = workout.routeCollectionTitle ?? "Movinn Route"
        let metadata = GPXRouteAppMetadata(
            routeCollectionID: routeCollectionID,
            title: routeName,
            sourceName: workout.routeCollectionSourceName,
            importedAt: workout.routeCollectionImportedAt,
            distanceMeters: workout.distanceMeters,
            durationSeconds: workout.durationSeconds,
            startDate: workout.startDate,
            activityTypeRawValue: workout.activityTypeRawValue,
            additionalMetadata: workout.metadata?.filter { !TrackedWorkout.routeCollectionCanonicalMetadataKeys.contains($0.key) }
        )
        return try data(
            routeName: routeName,
            coordinates: workout.routeDetailCoordinates,
            segmentStartIndices: workout.routeDetailSegmentStartIndices,
            appMetadata: metadata
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
        var xmlSafeValue = ""
        for scalar in value.unicodeScalars where isValidXMLScalar(scalar) {
            xmlSafeValue.append(contentsOf: String(scalar))
        }

        return xmlSafeValue
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    nonisolated private static func validSegments(
        from coordinates: [RouteCoordinate],
        segmentStartIndices: Set<Int>
    ) -> [[RouteCoordinate]] {
        let starts = segmentStartIndices
            .filter { $0 > 0 && $0 < coordinates.count }
            .sorted()
        let boundaries = [0] + starts + [coordinates.count]

        return zip(boundaries, boundaries.dropFirst()).compactMap { startIndex, endIndex in
            let segment = coordinates[startIndex..<endIndex].filter { coordinate in
                coordinate.latitude.isFinite
                    && coordinate.longitude.isFinite
                    && CLLocationCoordinate2DIsValid(coordinate.coordinate)
            }
            return segment.isEmpty ? nil : segment
        }
    }

    nonisolated private static func isValidXMLScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x9, 0xA, 0xD,
             0x20...0xD7FF,
             0xE000...0xFFFD,
             0x10000...0x10FFFF:
            return true
        default:
            return false
        }
    }

    nonisolated private static func coordinateValueString(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated private static func measurementString(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    nonisolated private static func pointExtensionValueString(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
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
