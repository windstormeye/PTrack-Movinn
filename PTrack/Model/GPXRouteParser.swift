//
//  GPXRouteParser.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import CoreLocation
import CryptoKit
import Foundation

nonisolated struct GPXRouteAppMetadata: Codable {
    static let namespaceURI = "https://movinn.app/xmlschemas/gpx/1"

    let schemaVersion: Int
    let routeCollectionID: String
    let title: String?
    let sourceName: String?
    let importedAt: Date?
    let distanceMeters: Double?
    let durationSeconds: TimeInterval?
    let startDate: Date?
    let activityTypeRawValue: UInt?
    let additionalMetadata: [String: TrackedMetadataValue]?

    nonisolated init(
        schemaVersion: Int = 1,
        routeCollectionID: String,
        title: String?,
        sourceName: String?,
        importedAt: Date?,
        distanceMeters: Double?,
        durationSeconds: TimeInterval?,
        startDate: Date?,
        activityTypeRawValue: UInt?,
        additionalMetadata: [String: TrackedMetadataValue]?
    ) {
        self.schemaVersion = schemaVersion
        self.routeCollectionID = routeCollectionID
        self.title = title
        self.sourceName = sourceName
        self.importedAt = importedAt
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.startDate = startDate
        self.activityTypeRawValue = activityTypeRawValue
        self.additionalMetadata = additionalMetadata
    }
}

nonisolated struct GPXParsedRoute {
    let title: String?
    let coordinates: [RouteCoordinate]
    let appMetadata: GPXRouteAppMetadata?
}

enum GPXRouteIdentity {
    nonisolated static func routeCollectionID(embeddedID: String?, documentData: Data) -> String {
        validatedEmbeddedID(embeddedID) ?? "gpx-\(sha256Hex(documentData).prefix(32))"
    }

    nonisolated static func validatedEmbeddedID(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 120 else {
            return nil
        }

        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_."
        )
        guard value.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return nil
        }
        return value
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum GPXRouteParserError: LocalizedError {
    case invalidDocument
    case noRoutePoints

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return AppLocalization.text(.gpxImportInvalidFile)
        case .noRoutePoints:
            return AppLocalization.text(.gpxImportNoRoute)
        }
    }
}

enum GPXRouteParser {
    nonisolated static func parse(data: Data, fallbackDate: Date = Date()) throws -> GPXParsedRoute {
        let delegate = GPXRouteParserDelegate(fallbackDate: fallbackDate)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true

        guard parser.parse(), !delegate.hasInvalidAppMetadata else {
            throw GPXRouteParserError.invalidDocument
        }

        let coordinates = delegate.resolvedCoordinates()
        guard coordinates.count > 1 else {
            throw GPXRouteParserError.noRoutePoints
        }

        return GPXParsedRoute(
            title: delegate.title,
            coordinates: coordinates,
            appMetadata: delegate.appMetadata
        )
    }
}

private nonisolated final class GPXRouteParserDelegate: NSObject, XMLParserDelegate {
    private struct MutablePoint {
        let latitude: Double
        let longitude: Double
        var timestamp: Date?
        var altitude: Double?
    }

    private let fallbackDate: Date
    private let isoFormatter = ISO8601DateFormatter()
    private let isoFormatterWithoutFractionalSeconds = ISO8601DateFormatter()
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var currentPoint: MutablePoint?
    private var parsedPoints: [MutablePoint] = []

    private(set) var title: String?
    private(set) var appMetadata: GPXRouteAppMetadata?
    private(set) var hasInvalidAppMetadata = false

    init(fallbackDate: Date) {
        self.fallbackDate = fallbackDate
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatterWithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        super.init()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedElementName(elementName)
        elementStack.append(name)
        textBuffer = ""

        guard name == "trkpt" || name == "rtept" else {
            return
        }

        guard let latitude = Self.coordinateValue(from: attributeDict["lat"]),
              let longitude = Self.coordinateValue(from: attributeDict["lon"] ?? attributeDict["lng"]),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) else {
            currentPoint = nil
            return
        }

        currentPoint = MutablePoint(
            latitude: latitude,
            longitude: longitude,
            timestamp: nil,
            altitude: nil
        )
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalizedElementName(elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "name":
            let parentElement = elementStack.dropLast().last
            if title == nil,
               currentPoint == nil,
               !value.isEmpty,
               parentElement == "metadata" || parentElement == "trk" || parentElement == "rte" {
                title = value
            }
        case "ele":
            if let altitude = Double(value), altitude.isFinite {
                currentPoint?.altitude = altitude
            }
        case "time":
            if let date = date(from: value) {
                currentPoint?.timestamp = date
            }
        case "routedata":
            let ancestors = elementStack.dropLast()
            let isMetadataExtension = ancestors.count >= 2
                && ancestors[ancestors.index(ancestors.endIndex, offsetBy: -2)] == "metadata"
                && ancestors.last == "extensions"
            guard namespaceURI == GPXRouteAppMetadata.namespaceURI, isMetadataExtension else {
                break
            }

            if let data = Data(base64Encoded: value, options: [.ignoreUnknownCharacters]),
               let metadata = try? JSONDecoder().decode(GPXRouteAppMetadata.self, from: data),
               metadata.schemaVersion == 1,
               GPXRouteIdentity.validatedEmbeddedID(metadata.routeCollectionID) != nil {
                appMetadata = metadata
            } else {
                hasInvalidAppMetadata = true
            }
        case "trkpt", "rtept":
            if let currentPoint {
                parsedPoints.append(currentPoint)
            }
            currentPoint = nil
        default:
            break
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        textBuffer = ""
    }

    func resolvedCoordinates() -> [RouteCoordinate] {
        parsedPoints.enumerated().map { index, point in
            RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: point.timestamp ?? fallbackDate.addingTimeInterval(TimeInterval(index)),
                altitudeMeters: point.altitude
            )
        }
    }

    private func normalizedElementName(_ name: String) -> String {
        (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
    }

    private func date(from string: String) -> Date? {
        guard !string.isEmpty else {
            return nil
        }

        return isoFormatter.date(from: string)
            ?? isoFormatterWithoutFractionalSeconds.date(from: string)
    }

    private static func coordinateValue(from string: String?) -> Double? {
        guard let string, let value = Double(string), value.isFinite else {
            return nil
        }

        return value
    }
}
