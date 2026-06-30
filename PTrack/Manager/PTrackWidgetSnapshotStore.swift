//
//  PTrackWidgetSnapshotStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import CoreLocation
import UIKit
import WidgetKit

extension PTrackWidgetSettingsStore {
    static func setWeeklyGoalDistanceKilometers(_ kilometers: Double) {
        let sanitizedKilometers = min(max(kilometers, 1), 9_999)
        sharedDefaults.set(sanitizedKilometers * 1_000, forKey: PTrackWidgetConstants.weeklyGoalDistanceMetersKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum PTrackWidgetSnapshotStore {
    private struct DrawingBounds {
        let minLongitude: Double
        let minLatitude: Double
        let maxLongitude: Double
        let maxLatitude: Double

        var width: Double {
            max(maxLongitude - minLongitude, 0)
        }

        var height: Double {
            max(maxLatitude - minLatitude, 0)
        }
    }

    static func refresh(with workouts: [TrackedWorkout]) {
        let snapshotWorkouts = workouts.map { $0.statisticsPreview() }
        let language = systemLanguage
        let goalDistanceMeters = PTrackWidgetSettingsStore.weeklyGoalDistanceMeters

        DispatchQueue.global(qos: .utility).async {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: PTrackWidgetConstants.appGroupIdentifier
            ) else {
                return
            }

            let snapshot = makeSnapshot(
                workouts: snapshotWorkouts,
                language: language,
                goalDistanceMeters: goalDistanceMeters,
                containerURL: containerURL
            )

            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(
                    to: containerURL.appendingPathComponent(PTrackWidgetConstants.snapshotFileName),
                    options: [.atomic]
                )
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } catch {
                print("PTrack Widget: failed to write widget snapshot: \(error)")
            }
        }
    }

    private static var systemLanguage: AppLanguage {
        for identifier in Locale.preferredLanguages.map({ $0.lowercased() }) {
            if identifier.hasPrefix("zh") {
                return .chinese
            }
            if identifier.hasPrefix("ja") {
                return .japanese
            }
            if identifier.hasPrefix("ko") {
                return .korean
            }
            if identifier.hasPrefix("en") {
                return .english
            }
        }

        return .english
    }

    private static func makeSnapshot(
        workouts: [TrackedWorkout],
        language: AppLanguage,
        goalDistanceMeters _: Double,
        containerURL: URL,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PTrackWidgetSnapshot {
        let weekRows = makeWeeklyRows(
            workouts: workouts,
            language: language,
            now: now,
            calendar: calendar
        )
        let weekSummary = PTrackWidgetSnapshot.WeekSummary(
            distanceMeters: weekRows.reduce(0) { $0 + $1.distanceMeters },
            durationSeconds: weekRows.reduce(0) { $0 + $1.durationSeconds }
        )
        let locationSummary = makeLocationSummary(from: workouts, language: language)
        let worldMapFileName = writeMapImage(
            scope: .world,
            highlightedIdentifiers: locationSummary.worldHighlightedIdentifiers,
            fileName: PTrackWidgetConstants.worldMapImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 720, height: 340),
            drawsForDarkAppearance: false
        )
        let worldMapDarkFileName = writeMapImage(
            scope: .world,
            highlightedIdentifiers: locationSummary.worldHighlightedIdentifiers,
            fileName: PTrackWidgetConstants.worldMapDarkImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 720, height: 340),
            drawsForDarkAppearance: true
        )
        let worldMapPreviewOutlineFileName = writeMapOutlineImage(
            scope: .world,
            fileName: PTrackWidgetConstants.worldMapPreviewOutlineImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 720, height: 340)
        )
        let chinaMapFileName = writeMapImage(
            scope: .china,
            highlightedIdentifiers: locationSummary.chinaHighlightedIdentifiers,
            fileName: PTrackWidgetConstants.chinaMapImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 420, height: 340),
            drawsForDarkAppearance: false
        )
        let chinaMapDarkFileName = writeMapImage(
            scope: .china,
            highlightedIdentifiers: locationSummary.chinaHighlightedIdentifiers,
            fileName: PTrackWidgetConstants.chinaMapDarkImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 420, height: 340),
            drawsForDarkAppearance: true
        )
        let chinaMapPreviewOutlineFileName = writeMapOutlineImage(
            scope: .china,
            fileName: PTrackWidgetConstants.chinaMapPreviewOutlineImageFileName,
            containerURL: containerURL,
            size: CGSize(width: 420, height: 340)
        )

        return PTrackWidgetSnapshot(
            generatedAt: now,
            languageRawValue: language.rawValue,
            weekSummary: weekSummary,
            weeklyRows: weekRows,
            monthCalendar: makeMonthCalendar(
                workouts: workouts,
                language: language,
                now: now,
                calendar: calendar
            ),
            annualSeries: makeAnnualSeries(
                workouts: workouts,
                now: now,
                calendar: calendar
            ),
            worldMapImageFileName: worldMapFileName,
            worldMapDarkImageFileName: worldMapDarkFileName,
            worldMapPreviewOutlineImageFileName: worldMapPreviewOutlineFileName,
            worldVisitedCountryCount: locationSummary.worldVisitedCountryCount,
            worldTotalCountryCount: locationSummary.worldTotalCountryCount,
            chinaMapImageFileName: chinaMapFileName,
            chinaMapDarkImageFileName: chinaMapDarkFileName,
            chinaMapPreviewOutlineImageFileName: chinaMapPreviewOutlineFileName,
            chinaVisitedCityCount: locationSummary.chinaVisitedCityCount,
            chinaTotalCityCount: locationSummary.chinaTotalCityCount
        )
    }

    private static func widgetWeekCalendar(from calendar: Calendar) -> Calendar {
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        weekCalendar.minimumDaysInFirstWeek = 4
        return weekCalendar
    }

    private static func makeWeeklyRows(
        workouts: [TrackedWorkout],
        language: AppLanguage,
        now: Date,
        calendar: Calendar
    ) -> [PTrackWidgetSnapshot.WeeklyRow] {
        let weekCalendar = widgetWeekCalendar(from: calendar)
        guard let weekInterval = weekCalendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = "E"

        return (0..<7).compactMap { dayOffset in
            guard let date = weekCalendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                return nil
            }

            let dayWorkouts = workouts.filter { workout in
                weekCalendar.isDate(workout.startDate, inSameDayAs: date)
            }

            return PTrackWidgetSnapshot.WeeklyRow(
                index: dayOffset,
                title: formatter.string(from: date),
                distanceMeters: dayWorkouts.reduce(0) { $0 + $1.distanceMeters },
                durationSeconds: dayWorkouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
            )
        }
    }

    private static func makeMonthCalendar(
        workouts: [TrackedWorkout],
        language: AppLanguage,
        now: Date,
        calendar: Calendar
    ) -> PTrackWidgetSnapshot.MonthCalendar {
        var monthCalendar = widgetWeekCalendar(from: calendar)
        monthCalendar.locale = Locale(identifier: language.rawValue)
        let monthStartDate = startOfMonth(for: now, calendar: monthCalendar)
        let nextMonthDate = monthCalendar.date(byAdding: .month, value: 1, to: monthStartDate) ?? now
        let monthWorkouts = workouts.filter { workout in
            workout.startDate >= monthStartDate && workout.startDate < nextMonthDate
        }
        let workoutsByDateKey = Dictionary(grouping: workouts) { workout in
            dateKey(for: workout.startDate, calendar: monthCalendar)
        }
        let dayRange = monthCalendar.range(of: .day, in: .month, for: monthStartDate) ?? 1..<1
        let weekday = monthCalendar.component(.weekday, from: monthStartDate)
        let leadingEmptyCount = (weekday - monthCalendar.firstWeekday + 7) % 7
        let dayCount = dayRange.count

        let days = (0..<42).map { index in
            let dayOffset = index - leadingEmptyCount
            let date = monthCalendar.date(byAdding: .day, value: dayOffset, to: monthStartDate) ?? monthStartDate
            let dayWorkouts = workoutsByDateKey[dateKey(for: date, calendar: monthCalendar)] ?? []
            let symbolNames = dayWorkouts
                .sorted { $0.startDate < $1.startDate }
                .map(\.symbolName)
                .reduce(into: [String]()) { result, symbolName in
                    guard !result.contains(symbolName) else {
                        return
                    }

                    result.append(symbolName)
                }

            return PTrackWidgetSnapshot.MonthDay(
                day: monthCalendar.component(.day, from: date),
                isCurrentMonth: dayOffset >= 0 && dayOffset < dayCount,
                isToday: monthCalendar.isDateInToday(date),
                symbolNames: Array(symbolNames.prefix(4))
            )
        }

        let titleFormatter = DateFormatter()
        titleFormatter.locale = Locale(identifier: language.rawValue)
        titleFormatter.calendar = monthCalendar
        titleFormatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")

        return PTrackWidgetSnapshot.MonthCalendar(
            title: titleFormatter.string(from: monthStartDate),
            summaryDistanceMeters: monthWorkouts.reduce(0) { $0 + $1.distanceMeters },
            summaryDurationSeconds: monthWorkouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
            weekdayTitles: reorderedWeekdaySymbols(calendar: monthCalendar, language: language),
            days: days
        )
    }

    private static func makeAnnualSeries(
        workouts: [TrackedWorkout],
        now: Date,
        calendar: Calendar
    ) -> [PTrackWidgetSnapshot.AnnualSeries] {
        let weekCalendar = widgetWeekCalendar(from: calendar)
        let currentYear = weekCalendar.component(.yearForWeekOfYear, from: now)
        let previousYear = currentYear - 1
        let currentWeekOfYear = min(max(weekCalendar.component(.weekOfYear, from: now), 1), 53)
        var yearlyDurations: [Int: [Int: TimeInterval]] = [:]
        var yearlyDistances: [Int: [Int: Double]] = [:]

        for workout in workouts {
            let year = weekCalendar.component(.yearForWeekOfYear, from: workout.startDate)
            guard year == currentYear || year == previousYear else {
                continue
            }

            let weekOfYear = min(max(weekCalendar.component(.weekOfYear, from: workout.startDate), 1), 53)
            yearlyDurations[year, default: [:]][weekOfYear, default: 0] += workout.durationSeconds ?? 0
            yearlyDistances[year, default: [:]][weekOfYear, default: 0] += workout.distanceMeters
        }

        return [currentYear, previousYear].map { year in
            let weekCount = weeksInYear(year, calendar: weekCalendar)
            let durations = yearlyDurations[year] ?? [:]
            let distances = yearlyDistances[year] ?? [:]
            let durationValues = (1...weekCount).map { durations[$0] ?? 0 }
            let distanceValues = (1...weekCount).map { distances[$0] ?? 0 }

            return PTrackWidgetSnapshot.AnnualSeries(
                year: year,
                weeklyDistanceMeters: distanceValues,
                weeklyDurationSeconds: durationValues,
                visibleWeekCount: year == currentYear ? min(currentWeekOfYear, weekCount) : weekCount,
                totalDistanceMeters: distanceValues.reduce(0, +),
                totalDurationSeconds: durationValues.reduce(0, +)
            )
        }
    }

    private static func weeksInYear(_ year: Int, calendar: Calendar) -> Int {
        let components = DateComponents(calendar: calendar, year: year, month: 12, day: 28)
        guard let date = calendar.date(from: components) else {
            return 52
        }

        return min(max(calendar.component(.weekOfYear, from: date), 52), 53)
    }

    private static func reorderedWeekdaySymbols(calendar: Calendar, language: AppLanguage) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.calendar = calendar
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else {
            switch language {
            case .chinese:
                return ["日", "一", "二", "三", "四", "五", "六"]
            case .japanese:
                return ["日", "月", "火", "水", "木", "金", "土"]
            case .korean:
                return ["일", "월", "화", "수", "목", "금", "토"]
            case .english:
                return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            }
        }

        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }

        return "\(year)-\(month)-\(day)"
    }

    private struct LocationSummary {
        let worldHighlightedIdentifiers: Set<String>
        let chinaHighlightedIdentifiers: Set<String>
        let worldVisitedCountryCount: Int
        let worldTotalCountryCount: Int
        let chinaVisitedCityCount: Int
        let chinaTotalCityCount: Int
    }

    private static func makeLocationSummary(
        from workouts: [TrackedWorkout],
        language: AppLanguage
    ) -> LocationSummary {
        var worldHighlightedIdentifiers = Set<String>()
        var chinaHighlightedIdentifiers = Set<String>()
        var worldVisitedCountryIdentifiers = Set<String>()
        var chinaVisitedCityIdentifiers = Set<String>()
        let regionManager = CoordinateRegionManager.shared
        let worldTotalCountryCount = Set(
            regionManager.mapFeatures(for: .world)
                .compactMap { normalizedIdentifier($0.displayName) }
        ).count
        let chinaTotalCityCount = regionManager.mapFeatures(for: .china).filter(\.isCity).count

        for workout in workouts where !isVirtualWorkout(workout) {
            for coordinate in routeEndpointCoordinates(for: workout) {
                guard let region = regionManager.region(for: coordinate, language: language) else {
                    continue
                }

                addLocationIdentifiers(
                    [
                        region.countryCode,
                        region.countryName,
                        region.countryCode == "CN" ? "China" : nil
                    ],
                    to: &worldHighlightedIdentifiers
                )
                if let countryIdentifier = normalizedIdentifier(region.countryCode)
                    ?? normalizedIdentifier(region.countryName) {
                    worldVisitedCountryIdentifiers.insert(countryIdentifier)
                }

                guard region.isChina else {
                    continue
                }

                let chinaRegion = regionManager.region(for: coordinate, language: .chinese) ?? region
                let chinaCityName = normalizedDisplayName(chinaRegion.cityName)
                    ?? normalizedDisplayName(chinaRegion.provinceName)
                addLocationIdentifiers(
                    [
                        chinaRegion.cityName,
                        chinaRegion.provinceName,
                        chinaRegion.adcode.map { String($0) }
                    ],
                    to: &chinaHighlightedIdentifiers
                )
                if let chinaCityName,
                   let identifier = normalizedIdentifier(chinaCityName) {
                    chinaVisitedCityIdentifiers.insert(identifier)
                }
            }
        }

        return LocationSummary(
            worldHighlightedIdentifiers: worldHighlightedIdentifiers,
            chinaHighlightedIdentifiers: chinaHighlightedIdentifiers,
            worldVisitedCountryCount: worldVisitedCountryIdentifiers.count,
            worldTotalCountryCount: worldTotalCountryCount,
            chinaVisitedCityCount: chinaVisitedCityIdentifiers.count,
            chinaTotalCityCount: chinaTotalCityCount
        )
    }

    private static func routeEndpointCoordinates(for workout: TrackedWorkout) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []

        if let startCoordinate = workout.coordinates.first?.coordinate,
           CLLocationCoordinate2DIsValid(startCoordinate) {
            coordinates.append(startCoordinate)
        }

        if let endCoordinate = workout.coordinates.last?.coordinate,
           CLLocationCoordinate2DIsValid(endCoordinate),
           !coordinates.contains(where: { $0.latitude == endCoordinate.latitude && $0.longitude == endCoordinate.longitude }) {
            coordinates.append(endCoordinate)
        }

        return coordinates
    }

    private static func isVirtualWorkout(_ workout: TrackedWorkout) -> Bool {
        workout.sportKind == .virtualCycling || workout.sportKind == .virtualRunning
    }

    private static func addLocationIdentifiers(
        _ values: [String?],
        to identifiers: inout Set<String>
    ) {
        values.forEach { value in
            guard let identifier = normalizedIdentifier(value) else {
                return
            }

            identifiers.insert(identifier)
        }
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedValue,
              !normalizedValue.isEmpty,
              normalizedValue != "-99" else {
            return nil
        }

        return normalizedValue
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue,
              !trimmedValue.isEmpty,
              normalizedIdentifier(trimmedValue) != nil else {
            return nil
        }

        return trimmedValue
    }

    private static func writeMapImage(
        scope: CoordinateRegionMapScope,
        highlightedIdentifiers: Set<String>,
        fileName: String,
        containerURL: URL,
        size: CGSize,
        drawsForDarkAppearance: Bool
    ) -> String? {
        let features = CoordinateRegionManager.shared.mapFeatures(for: scope)
        let image = renderMapImage(
            scope: scope,
            features: features,
            highlightedIdentifiers: highlightedIdentifiers,
            size: size,
            scale: 2,
            drawsForDarkAppearance: drawsForDarkAppearance
        )

        guard let data = image.pngData() else {
            return nil
        }

        do {
            try data.write(to: containerURL.appendingPathComponent(fileName), options: [.atomic])
            return fileName
        } catch {
            print("PTrack Widget: failed to write \(fileName): \(error)")
            return nil
        }
    }

    private static func writeMapOutlineImage(
        scope: CoordinateRegionMapScope,
        fileName: String,
        containerURL: URL,
        size: CGSize
    ) -> String? {
        let features = CoordinateRegionManager.shared.mapFeatures(for: scope)
        let image = renderMapOutlineImage(
            scope: scope,
            features: features,
            size: size,
            scale: 2
        )

        guard let data = image.pngData() else {
            return nil
        }

        do {
            try data.write(to: containerURL.appendingPathComponent(fileName), options: [.atomic])
            return fileName
        } catch {
            print("PTrack Widget: failed to write \(fileName): \(error)")
            return nil
        }
    }

    private static func renderMapImage(
        scope: CoordinateRegionMapScope,
        features: [CoordinateRegionMapFeature],
        highlightedIdentifiers: Set<String>,
        size: CGSize,
        scale: CGFloat,
        drawsForDarkAppearance: Bool
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            guard !features.isEmpty,
                  let bounds = drawingBounds(for: features, scope: scope),
                  bounds.width > 0,
                  bounds.height > 0 else {
                drawPlaceholder(in: rect, drawsForDarkAppearance: drawsForDarkAppearance)
                return
            }

            let targetRect = fittedRect(
                for: bounds,
                scope: scope,
                in: rect.insetBy(dx: 3, dy: 3)
            )
            let baseFillColor = (drawsForDarkAppearance ? UIColor.white : UIColor.black)
                .withAlphaComponent(drawsForDarkAppearance ? 0.082 : 0.075)
            let baseStrokeColor = drawsForDarkAppearance
                ? UIColor.white.withAlphaComponent(0.58)
                : UIColor(white: 0.24, alpha: 0.72)
            let highlightedFillColor = AppColors.movinnGreen
            let highlightedStrokeColor = drawsForDarkAppearance
                ? UIColor.white.withAlphaComponent(0.66)
                : UIColor(white: 0.30, alpha: 0.72)

            for feature in features {
                let path = path(for: feature, bounds: bounds, targetRect: targetRect)
                guard !path.isEmpty else {
                    continue
                }

                let isHighlighted = !feature.identifiers.isDisjoint(with: highlightedIdentifiers)
                (isHighlighted ? highlightedFillColor : baseFillColor).setFill()
                path.fill()
                (isHighlighted ? highlightedStrokeColor : baseStrokeColor).setStroke()
                path.lineWidth = isHighlighted ? 0.7 : 0.4
                path.stroke()
            }
        }
    }

    private static func renderMapOutlineImage(
        scope: CoordinateRegionMapScope,
        features: [CoordinateRegionMapFeature],
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            guard !features.isEmpty,
                  let bounds = drawingBounds(for: features, scope: scope),
                  bounds.width > 0,
                  bounds.height > 0 else {
                return
            }

            let targetRect = fittedRect(
                for: bounds,
                scope: scope,
                in: rect.insetBy(dx: 3, dy: 3)
            )

            UIColor.white.withAlphaComponent(0.74).setStroke()
            for feature in features {
                let path = path(for: feature, bounds: bounds, targetRect: targetRect)
                guard !path.isEmpty else {
                    continue
                }

                path.lineWidth = scope == .world ? 0.54 : 0.62
                path.stroke()
            }
        }
    }

    private static func drawPlaceholder(in rect: CGRect, drawsForDarkAppearance: Bool) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 18), cornerRadius: 8)
        (drawsForDarkAppearance ? UIColor.white : UIColor.black).withAlphaComponent(0.045).setFill()
        path.fill()
    }

    private static func drawingBounds(
        for features: [CoordinateRegionMapFeature],
        scope: CoordinateRegionMapScope
    ) -> DrawingBounds? {
        guard let firstBounds = features.first?.bounds,
              firstBounds.isValid else {
            return nil
        }

        let bounds = features.dropFirst().reduce(
            DrawingBounds(
                minLongitude: firstBounds.minLongitude,
                minLatitude: firstBounds.minLatitude,
                maxLongitude: firstBounds.maxLongitude,
                maxLatitude: firstBounds.maxLatitude
            )
        ) { result, feature in
            DrawingBounds(
                minLongitude: min(result.minLongitude, feature.bounds.minLongitude),
                minLatitude: min(result.minLatitude, feature.bounds.minLatitude),
                maxLongitude: max(result.maxLongitude, feature.bounds.maxLongitude),
                maxLatitude: max(result.maxLatitude, feature.bounds.maxLatitude)
            )
        }

        switch scope {
        case .world:
            return bounds
        case .china:
            return DrawingBounds(
                minLongitude: bounds.minLongitude,
                minLatitude: max(bounds.minLatitude, 17.5),
                maxLongitude: bounds.maxLongitude,
                maxLatitude: bounds.maxLatitude
            )
        }
    }

    private static func fittedRect(
        for bounds: DrawingBounds,
        scope: CoordinateRegionMapScope,
        in rect: CGRect
    ) -> CGRect {
        let mapAspectRatio = CGFloat(bounds.width / bounds.height)
        let rectAspectRatio = rect.width / max(rect.height, 1)
        let fittedRect: CGRect
        if mapAspectRatio > rectAspectRatio {
            let height = rect.width / max(mapAspectRatio, 0.1)
            fittedRect = CGRect(
                x: rect.minX,
                y: rect.midY - height / 2,
                width: rect.width,
                height: height
            )
        } else {
            let width = rect.height * mapAspectRatio
            fittedRect = CGRect(
                x: rect.midX - width / 2,
                y: rect.minY,
                width: width,
                height: rect.height
            )
        }

        switch scope {
        case .world:
            return fittedRect
        case .china:
            let expandedHeight = min(rect.height, max(fittedRect.height, rect.height * 0.96))
            return CGRect(
                x: fittedRect.minX,
                y: rect.midY - expandedHeight / 2,
                width: fittedRect.width,
                height: expandedHeight
            )
        }
    }

    private static func path(
        for feature: CoordinateRegionMapFeature,
        bounds: DrawingBounds,
        targetRect: CGRect
    ) -> UIBezierPath {
        let path = UIBezierPath()
        for ring in feature.rings {
            let points = simplifiedCoordinates(ring)
            guard let firstCoordinate = points.first else {
                continue
            }

            path.move(to: projectedPoint(firstCoordinate, bounds: bounds, targetRect: targetRect))
            for coordinate in points.dropFirst() {
                path.addLine(to: projectedPoint(coordinate, bounds: bounds, targetRect: targetRect))
            }
            path.close()
        }

        return path
    }

    private static func simplifiedCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let maxPointCount = 520
        guard coordinates.count > maxPointCount else {
            return coordinates
        }

        let stride = Int(ceil(Double(coordinates.count) / Double(maxPointCount)))
        var result = coordinates.enumerated().compactMap { index, coordinate in
            index % stride == 0 ? coordinate : nil
        }
        if let lastCoordinate = coordinates.last {
            let currentLastCoordinate = result.last
            if currentLastCoordinate == nil
                || currentLastCoordinate?.latitude != lastCoordinate.latitude
                || currentLastCoordinate?.longitude != lastCoordinate.longitude {
                result.append(lastCoordinate)
            }
        }
        return result
    }

    private static func projectedPoint(
        _ coordinate: CLLocationCoordinate2D,
        bounds: DrawingBounds,
        targetRect: CGRect
    ) -> CGPoint {
        let xRatio = (coordinate.longitude - bounds.minLongitude) / max(bounds.width, 0.000_001)
        let yRatio = (coordinate.latitude - bounds.minLatitude) / max(bounds.height, 0.000_001)
        return CGPoint(
            x: targetRect.minX + CGFloat(xRatio) * targetRect.width,
            y: targetRect.maxY - CGFloat(yRatio) * targetRect.height
        )
    }
}
