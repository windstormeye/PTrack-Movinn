//
//  MonthlyCalendarWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackMonthlyCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.monthlyCalendar, provider: PTrackWidgetProvider()) { entry in
            MonthlyCalendarWidgetView(entry: entry)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetMonthlyCalendar))
        .description(PTrackWidgetText.current.text(.widgetMonthlyCalendarDescription))
        .supportedFamilies([.systemLarge])
    }
}

private struct MonthlyCalendarWidgetView: View {
    let entry: PTrackWidgetEntry

    private var text: PTrackWidgetText {
        entry.snapshot.text
    }

    private var month: PTrackWidgetSnapshot.MonthCalendar {
        entry.snapshot.monthCalendar
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(text.monthTitle(for: entry.snapshot.generatedAt))
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
                    MonthDayView(day: day)
                        .frame(height: 31)
                }
            }
        }
        .padding(18)
    }
}

private struct MonthDayView: View {
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

#Preview(as: .systemLarge) {
    PTrackMonthlyCalendarWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
