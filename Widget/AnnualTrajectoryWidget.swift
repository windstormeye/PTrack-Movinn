//
//  AnnualTrajectoryWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackAnnualTrajectoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.annualTrajectory, provider: PTrackWidgetProvider()) { entry in
            PTrackAnnualTrajectoryWidgetContentView(snapshot: entry.snapshot)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetAnnualTrajectory))
        .description(PTrackWidgetText.current.text(.widgetAnnualTrajectoryDescription))
        .supportedFamilies([.systemMedium])
    }
}
