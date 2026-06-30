//
//  WeeklyProgressWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackWeeklyProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.weeklyProgress, provider: PTrackWidgetProvider()) { entry in
            PTrackWeeklyProgressWidgetContentView(
                snapshot: entry.snapshot,
                goalDistanceMeters: PTrackWidgetSettingsStore.weeklyGoalDistanceMeters
            )
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetSmallWeeklyGoal))
        .description(PTrackWidgetText.current.text(.widgetSmallWeeklyGoalDescription))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    PTrackWeeklyProgressWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
