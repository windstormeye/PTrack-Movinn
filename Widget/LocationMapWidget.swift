//
//  LocationMapWidget.swift
//  Widget
//
//  Created by pjhubs on 2026/6/30.
//

import SwiftUI
import UIKit
import WidgetKit

struct PTrackWorldMapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PTrackWidgetKind.worldMap, provider: PTrackWidgetProvider()) { entry in
            LocationMapWidgetView(entry: entry, map: .world)
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
            LocationMapWidgetView(entry: entry, map: .china)
                .pTrackWidgetBackground()
        }
        .configurationDisplayName(PTrackWidgetText.current.text(.widgetChinaMap))
        .description(PTrackWidgetText.current.text(.widgetChinaMapDescription))
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct LocationMapWidgetView: View {
    enum MapKind {
        case world
        case china
    }

    let entry: PTrackWidgetEntry
    let map: MapKind

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                mapImage(fileName: map == .world ? entry.snapshot.worldMapImageFileName : entry.snapshot.chinaMapImageFileName)
                    .frame(
                        width: proxy.size.width,
                        height: max(proxy.size.height - verticalPadding * 2, 1)
                    )
                    .scaleEffect(mapScale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if map == .china {
                    Text(chinaCityWorkoutText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PTrackWidgetPalette.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PTrackWidgetPalette.background.opacity(0.82), in: Capsule())
                        .padding(.leading, 9)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var chinaCityWorkoutText: String {
        entry.snapshot.text.format(
            .widgetChinaCityWorkoutFormat,
            entry.snapshot.chinaVisitedCityCount ?? 0,
            entry.snapshot.chinaTotalCityCount ?? 0
        )
    }

    private var mapScale: CGFloat {
        switch map {
        case .world:
            return 1.08
        case .china:
            return 1.12
        }
    }

    private var verticalPadding: CGFloat {
        switch map {
        case .world:
            return 10
        case .china:
            return 12
        }
    }

    @ViewBuilder
    private func mapImage(fileName: String?) -> some View {
        if let image = image(fileName: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(PTrackWidgetPalette.secondary.opacity(0.08))
                .overlay(
                    Circle()
                        .fill(PTrackWidgetPalette.brand)
                        .frame(width: 10, height: 10)
                )
        }
    }

    private func image(fileName: String?) -> UIImage? {
        guard let fileName,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: PTrackWidgetConstants.appGroupIdentifier
              ) else {
            return nil
        }

        return UIImage(contentsOfFile: containerURL.appendingPathComponent(fileName).path)
    }
}
