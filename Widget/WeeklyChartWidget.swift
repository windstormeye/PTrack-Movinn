//
//  WeeklyChartWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackWeeklyChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.weeklyChart, provider: PTrackWidgetProvider()) { entry in
            WeeklyChartWidgetView(entry: entry)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetWeeklyChart))
        .description(PTrackWidgetText.current.text(.widgetWeeklyChartDescription))
        .supportedFamilies([.systemMedium])
    }
}

private struct WeeklyChartWidgetView: View {
    let entry: PTrackWidgetEntry

    private var text: PTrackWidgetText {
        entry.snapshot.text
    }

    private var rows: [PTrackWidgetSnapshot.WeeklyRow] {
        entry.snapshot.weeklyRows
    }

    private var maxDistance: Double {
        max(rows.map(\.distanceMeters).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                metric(title: text.text(.weeklyDistance), value: compactDistanceText(entry.snapshot.weekSummary.distanceMeters))
                metric(title: text.text(.weeklyDuration), value: compactDurationText(entry.snapshot.weekSummary.durationSeconds, text: text))
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

#Preview(as: .systemMedium) {
    PTrackWeeklyChartWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
