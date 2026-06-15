//
//  WorkoutRouteResolvedLocation.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import Foundation

struct WorkoutRouteResolvedLocation: Codable, Equatable {
    let title: String
    let countryCode: String?
    let countryName: String?
    let administrativeArea: String?
    let subAdministrativeArea: String?
    let locality: String?
    let subLocality: String?
    let fullAddress: String?
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
}
