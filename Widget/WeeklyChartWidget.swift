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
            PTrackWeeklyChartWidgetContentView(snapshot: entry.snapshot)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetWeeklyChart))
        .description(PTrackWidgetText.current.text(.widgetWeeklyChartDescription))
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    PTrackWeeklyChartWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
