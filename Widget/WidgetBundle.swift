//
//  WidgetBundle.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import WidgetKit
import SwiftUI

@main
struct PTrackWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PTrackWeeklyProgressWidget()
        PTrackWeeklyChartWidget()
        PTrackMonthlyCalendarWidget()
        PTrackAnnualTrajectoryWidget()
        PTrackWorldMapWidget()
        PTrackChinaMapWidget()
    }
}
