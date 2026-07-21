//
//  PTrackLog.swift
//  PTrack
//
//  Created by Codex on 2026/7/20.
//

import Foundation
import OSLog

enum PTrackLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "studio.pj.PTrack"

    static let cache = Logger(subsystem: subsystem, category: "WorkoutCache")
    static let synchronization = Logger(subsystem: subsystem, category: "Synchronization")
}

