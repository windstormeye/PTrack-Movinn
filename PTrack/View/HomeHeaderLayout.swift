//
//  HomeHeaderLayout.swift
//  PTrack
//

import UIKit

struct HomeHeaderLayoutMetrics: Equatable {
    let height: CGFloat
    let titleLeading: CGFloat
    let titleTop: CGFloat
}

enum HomeHeaderLayout {
    static func metrics(for view: UIView) -> HomeHeaderLayoutMetrics {
        guard view.traitCollection.userInterfaceIdiom == .pad else {
            return HomeHeaderLayoutMetrics(height: 122, titleLeading: 16, titleTop: 10)
        }

        let isWindowed = isWindowed(on: view)
        return HomeHeaderLayoutMetrics(
            height: 96,
            titleLeading: isWindowed ? 32 : 16,
            titleTop: isWindowed ? 16 : 10
        )
    }

    private static func isWindowed(on view: UIView) -> Bool {
        guard let window = view.window,
              let windowScene = window.windowScene else {
            return false
        }

        let windowSize = window.bounds.size
        let screenSize = windowScene.screen.coordinateSpace.bounds.size
        let tolerance: CGFloat = 1
        let matchesScreen = abs(windowSize.width - screenSize.width) <= tolerance
            && abs(windowSize.height - screenSize.height) <= tolerance
        let matchesRotatedScreen = abs(windowSize.width - screenSize.height) <= tolerance
            && abs(windowSize.height - screenSize.width) <= tolerance

        return !matchesScreen && !matchesRotatedScreen
    }
}
