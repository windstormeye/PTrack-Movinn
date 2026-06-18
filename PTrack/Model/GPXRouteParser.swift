//
//  GPXRouteParser.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import CoreLocation
import Foundation

struct GPXParsedRoute {
    let title: String?
    let coordinates: [RouteCoordinate]
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

        guard parser.parse() else {
            throw GPXRouteParserError.invalidDocument
        }

        let coordinates = delegate.resolvedCoordinates()
        guard coordinates.count > 1 else {
            throw GPXRouteParserError.noRoutePoints
        }

        return GPXParsedRoute(
            title: delegate.title,
            coordinates: coordinates
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
            if title == nil, currentPoint == nil, !value.isEmpty {
                title = value
            }
        case "ele":
            if let altitude = Double(value) {
                currentPoint?.altitude = altitude
            }
        case "time":
            if let date = date(from: value) {
                currentPoint?.timestamp = date
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
        name.split(separator: ":").last.map(String.init) ?? name
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
