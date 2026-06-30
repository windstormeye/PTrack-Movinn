//
//  LocationMapWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackWorldMapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.worldMap, provider: PTrackWidgetProvider()) { entry in
            PTrackLocationMapWidgetContentView(snapshot: entry.snapshot, map: .world)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetWorldMap))
        .description(PTrackWidgetText.current.text(.widgetWorldMapDescription))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct PTrackChinaMapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.chinaMap, provider: PTrackWidgetProvider()) { entry in
            PTrackLocationMapWidgetContentView(snapshot: entry.snapshot, map: .china)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetChinaMap))
        .description(PTrackWidgetText.current.text(.widgetChinaMapDescription))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
