//
//  RouteShareEntranceAnimator.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import UIKit

enum RouteShareEntranceAnimator {
    static func prepare(_ views: [UIView]) {
        views.enumerated().forEach { index, view in
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 22 + CGFloat(index) * 6)
        }
    }

    static func animate(_ views: [UIView]) {
        views.enumerated().forEach { index, view in
            UIView.animate(
                withDuration: 0.46,
                delay: 0.04 + Double(index) * 0.055,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.55,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                view.alpha = 1
                view.transform = .identity
            }
        }
    }
}
