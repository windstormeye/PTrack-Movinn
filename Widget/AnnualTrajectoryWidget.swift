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
            AnnualTrajectoryWidgetView(entry: entry)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetAnnualTrajectory))
        .description(PTrackWidgetText.current.text(.widgetAnnualTrajectoryDescription))
        .supportedFamilies([.systemMedium])
    }
}

private struct AnnualTrajectoryWidgetView: View {
    let entry: PTrackWidgetEntry

    private var series: [PTrackWidgetSnapshot.AnnualSeries] {
        entry.snapshot.annualSeries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(series) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: String(item.year))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(item.year == series.first?.year ? PTrackWidgetPalette.foreground : PTrackWidgetPalette.secondary)
                        Text(compactDistanceText(item.totalDistanceMeters))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(item.year == series.first?.year ? PTrackWidgetPalette.brand : PTrackWidgetPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Canvas { context, size in
                let allValues = series.flatMap { Array($0.weeklyDistanceMeters.prefix($0.visibleWeekCount)) }
                let maxValue = max(allValues.max() ?? 0, 1)
                for (index, item) in series.enumerated().reversed() {
                    let values = Array(item.weeklyDistanceMeters.prefix(item.visibleWeekCount))
                    guard values.count > 1 else {
                        continue
                    }

                    var path = Path()
                    for valueIndex in values.indices {
                        let x = CGFloat(valueIndex) / CGFloat(max(item.weeklyDistanceMeters.count - 1, 1)) * size.width
                        let y = size.height - CGFloat(values[valueIndex] / maxValue) * (size.height - 10) - 5
                        let point = CGPoint(x: x, y: y)
                        if valueIndex == values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(index == 0 ? PTrackWidgetPalette.brand : PTrackWidgetPalette.secondary.opacity(0.2)),
                        style: StrokeStyle(lineWidth: index == 0 ? 3 : 1.7, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
    }
}
