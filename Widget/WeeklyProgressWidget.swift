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
            WeeklyProgressWidgetView(entry: entry)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetSmallWeeklyGoal))
        .description(PTrackWidgetText.current.text(.widgetSmallWeeklyGoalDescription))
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct WeeklyProgressWidgetView: View {
    let entry: PTrackWidgetEntry

    private var goalDistanceMeters: Double {
        PTrackWidgetSettingsStore.weeklyGoalDistanceMeters
    }

    private var progress: Double {
        guard goalDistanceMeters > 0 else {
            return 0
        }

        return min(max(entry.snapshot.weekSummary.distanceMeters / goalDistanceMeters, 0), 1)
    }

    var body: some View {
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

            VStack(spacing: 2) {
                Text(compactDistanceText(entry.snapshot.weekSummary.distanceMeters))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(PTrackWidgetPalette.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(compactDurationText(entry.snapshot.weekSummary.durationSeconds, text: entry.snapshot.text))
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

#Preview(as: .systemSmall) {
    PTrackWeeklyProgressWidget()
} timeline: {
    PTrackWidgetEntry(date: .now, snapshot: .placeholder)
}
