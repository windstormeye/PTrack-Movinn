//
//  Widget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import WidgetKit

struct PTrackWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PTrackWidgetSnapshot
}

struct PTrackWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PTrackWidgetEntry {
        PTrackWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PTrackWidgetEntry) -> Void) {
        completion(PTrackWidgetEntry(date: .now, snapshot: PTrackWidgetSnapshotReader.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PTrackWidgetEntry>) -> Void) {
        let now = Date()
        let entry = PTrackWidgetEntry(date: now, snapshot: PTrackWidgetSnapshotReader.loadSnapshot())
        let nextRefreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate)))
    }
}

extension View {
    @ViewBuilder
    func pTrackWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(PTrackWidgetPalette.background, for: .widget)
        } else {
            padding()
                .background(PTrackWidgetPalette.background)
        }
    }
}
