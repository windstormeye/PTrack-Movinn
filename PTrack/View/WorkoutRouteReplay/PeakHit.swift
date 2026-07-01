//
//  PeakHit.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

enum PeakMarkerKind {
    case altitude
    case heartRate
    case power
}

struct PeakHit {
    let progress: CGFloat
    let snapProgress: CGFloat?
    let markerKind: PeakMarkerKind?
    let didHitPeak: Bool
}
