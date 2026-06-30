//
//  PTrackWidgetContentViews.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import SwiftUI
import UIKit

struct PTrackWeeklyProgressWidgetContentView: View {
    let snapshot: PTrackWidgetSnapshot
    let goalDistanceMeters: Double

    private var progress: Double {
        guard goalDistanceMeters > 0 else {
            return 0
        }

        return min(max(snapshot.weekSummary.distanceMeters / goalDistanceMeters, 0), 1)
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .stroke(PTrackWidgetPalette.muted.opacity(0.42), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        PTrackWidgetPalette.brand,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .padding(5)

            VStack(spacing: 2) {
                Text(compactDistanceText(snapshot.weekSummary.distanceMeters))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(PTrackWidgetPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(compactDurationText(snapshot.weekSummary.durationSeconds, text: snapshot.text))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PTrackWidgetPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .padding(.horizontal, 18)
        }
        .padding(12)
    }
}

struct PTrackWeeklyChartWidgetContentView: View {
    let snapshot: PTrackWidgetSnapshot

    private var text: PTrackWidgetText {
        snapshot.text
    }

    private var rows: [PTrackWidgetSnapshot.WeeklyRow] {
        snapshot.weeklyRows
    }

    private var maxDistance: Double {
        max(rows.map(\.distanceMeters).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                metric(title: text.text(.weeklyDistance), value: compactDistanceText(snapshot.weekSummary.distanceMeters))
                metric(title: text.text(.weeklyDuration), value: compactDurationText(snapshot.weekSummary.durationSeconds, text: text))
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(rows) { row in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PTrackWidgetPalette.brand.opacity(row.distanceMeters > 0 ? 0.86 : 0.18))
                            .frame(height: barHeight(value: row.distanceMeters, maxValue: maxDistance))
                            .frame(maxHeight: .infinity, alignment: .bottom)

                        Text(text.weekdayTitle(at: row.index))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PTrackWidgetPalette.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PTrackWidgetPalette.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(PTrackWidgetPalette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
    }

    private func barHeight(value: Double, maxValue: Double) -> CGFloat {
        CGFloat(max(value / maxValue, 0.04)) * 82
    }
}

struct PTrackMonthlyCalendarWidgetContentView: View {
    let snapshot: PTrackWidgetSnapshot

    private var text: PTrackWidgetText {
        snapshot.text
    }

    private var month: PTrackWidgetSnapshot.MonthCalendar {
        snapshot.monthCalendar
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(text.monthTitle(for: snapshot.generatedAt))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(PTrackWidgetPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(compactDistanceText(month.summaryDistanceMeters))
                    Text(compactDurationText(month.summaryDurationSeconds, text: text))
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PTrackWidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(text.placeholderWeekdayTitles.enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PTrackWidgetPalette.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(month.days) { day in
                    PTrackMonthDayView(day: day)
                        .frame(height: 31)
                }
            }
        }
        .padding(18)
    }
}

private struct PTrackMonthDayView: View {
    let day: PTrackWidgetSnapshot.MonthDay

    var body: some View {
        ZStack {
            Circle()
                .stroke(day.isToday ? PTrackWidgetPalette.foreground : Color.clear, lineWidth: 1.4)
                .frame(width: 30, height: 30)

            if day.symbolNames.isEmpty {
                Text("\(day.day)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(day.isCurrentMonth ? PTrackWidgetPalette.foreground : PTrackWidgetPalette.secondary.opacity(0.34))
            } else {
                HStack(spacing: 1) {
                    ForEach(Array(day.symbolNames.prefix(2)), id: \.self) { symbolName in
                        Image(systemName: symbolName)
                            .font(.system(size: day.symbolNames.count == 1 ? 14 : 10, weight: .semibold))
                            .foregroundStyle(PTrackWidgetPalette.brand)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 5)
            }
        }
    }
}

struct PTrackAnnualTrajectoryWidgetContentView: View {
    let snapshot: PTrackWidgetSnapshot

    private var series: [PTrackWidgetSnapshot.AnnualSeries] {
        snapshot.annualSeries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(series) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: String(item.year))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(item.year == series.first?.year ? PTrackWidgetPalette.foreground : PTrackWidgetPalette.secondary)
                        Text(compactDistanceText(item.totalDistanceMeters))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(item.year == series.first?.year ? PTrackWidgetPalette.brand : PTrackWidgetPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Canvas { context, size in
                let allValues = series.flatMap { Array($0.weeklyDistanceMeters.prefix($0.visibleWeekCount)) }
                let maxValue = max(allValues.max() ?? 0, 1)
                for (index, item) in series.enumerated().reversed() {
                    let values = Array(item.weeklyDistanceMeters.prefix(item.visibleWeekCount))
                    guard values.count > 1 else {
                        continue
                    }

                    var path = Path()
                    for valueIndex in values.indices {
                        let x = CGFloat(valueIndex) / CGFloat(max(item.weeklyDistanceMeters.count - 1, 1)) * size.width
                        let y = size.height - CGFloat(values[valueIndex] / maxValue) * (size.height - 10) - 5
                        let point = CGPoint(x: x, y: y)
                        if valueIndex == values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(index == 0 ? PTrackWidgetPalette.brand : PTrackWidgetPalette.secondary.opacity(0.2)),
                        style: StrokeStyle(lineWidth: index == 0 ? 3 : 1.7, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
    }
}

enum PTrackLocationMapKind {
    case world
    case china
}

struct PTrackLocationMapWidgetContentView: View {
    let snapshot: PTrackWidgetSnapshot
    let map: PTrackLocationMapKind
    var brightensDarkOutlinesInPreview = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let image = preferredMapImage
            let previewOutlineImage = preferredPreviewOutlineImage
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    mapImage(image: image)

                    if brightensDarkOutlinesInPreview, colorScheme == .dark, previewOutlineImage != nil {
                        mapImage(image: previewOutlineImage)
                            .opacity(0.92)
                    }
                }
                    .frame(
                        width: proxy.size.width,
                        height: max(proxy.size.height - verticalPadding * 2, 1)
                    )
                    .scaleEffect(mapScale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Text(locationWorkoutText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PTrackWidgetPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PTrackWidgetPalette.background.opacity(0.82), in: Capsule())
                    .padding(.leading, 9)
                    .padding(.bottom, 8)
            }
        }
    }

    private var locationWorkoutText: String {
        switch map {
        case .world:
            return worldCountryWorkoutText
        case .china:
            return chinaCityWorkoutText
        }
    }

    private var worldCountryWorkoutText: String {
        snapshot.text.format(
            .widgetWorldCountryWorkoutFormat,
            snapshot.worldVisitedCountryCount ?? 0,
            snapshot.worldTotalCountryCount ?? 0
        )
    }

    private var chinaCityWorkoutText: String {
        snapshot.text.format(
            .widgetChinaCityWorkoutFormat,
            snapshot.chinaVisitedCityCount ?? 0,
            snapshot.chinaTotalCityCount ?? 0
        )
    }

    private var preferredMapImage: UIImage? {
        guard let fileName = preferredMapImageFileName else {
            return nil
        }

        return PTrackWidgetSnapshotReader.image(fileName: fileName)
    }

    private var preferredPreviewOutlineImage: UIImage? {
        guard let fileName = preferredPreviewOutlineImageFileName else {
            return nil
        }

        return PTrackWidgetSnapshotReader.image(fileName: fileName)
    }

    private var preferredMapImageFileName: String? {
        switch (map, colorScheme) {
        case (.world, .dark):
            return snapshot.worldMapDarkImageFileName ?? snapshot.worldMapImageFileName
        case (.china, .dark):
            return snapshot.chinaMapDarkImageFileName ?? snapshot.chinaMapImageFileName
        case (.world, _):
            return snapshot.worldMapImageFileName
        case (.china, _):
            return snapshot.chinaMapImageFileName
        }
    }

    private var preferredPreviewOutlineImageFileName: String? {
        switch map {
        case .world:
            return snapshot.worldMapPreviewOutlineImageFileName
        case .china:
            return snapshot.chinaMapPreviewOutlineImageFileName
        }
    }

    private var mapScale: CGFloat {
        switch map {
        case .world:
            return 1.08
        case .china:
            return 1.12
        }
    }

    private var verticalPadding: CGFloat {
        switch map {
        case .world:
            return 10
        case .china:
            return 12
        }
    }

    @ViewBuilder
    private func mapImage(image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(PTrackWidgetPalette.secondary.opacity(0.08))
                .overlay(
                    Circle()
                        .fill(PTrackWidgetPalette.brand)
                        .frame(width: 10, height: 10)
                )
        }
    }
}
