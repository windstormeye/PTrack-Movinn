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
            PTrackMonthlyCalendarWidgetContentView(snapshot: entry.snapshot)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetMonthlyCalendar))
        .description(PTrackWidgetText.current.text(.widgetMonthlyCalendarDescription))
        .supportedFamilies([.systemLarge])
    }
}

#Preview(as: .systemLarge) {
    PTrackMonthlyCalendarWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
