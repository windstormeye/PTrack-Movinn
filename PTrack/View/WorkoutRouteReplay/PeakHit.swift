//
//  PeakHit.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

enum PeakMarkerKind {
    case altitude
    case slope
    case heartRate
    case power
    case temperature
}

enum WorkoutRouteReplayRulerLayout {
    // Keep every marker centered on its data position without clipping the
    // widest (30 pt) marker at either end of the profile.
    static let horizontalPadding: CGFloat = 15
}

struct PeakHit {
    let progress: CGFloat
    let snapProgress: CGFloat?
    let markerKind: PeakMarkerKind?
    let didHitPeak: Bool
}
