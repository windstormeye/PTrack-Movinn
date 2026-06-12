//
//  RouteSampler.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import Foundation

enum RouteSampler {
    static func downsample(_ coordinates: [RouteCoordinate], limit: Int) -> [RouteCoordinate] {
        guard coordinates.count > limit, limit > 2 else {
            return coordinates
        }

        let step = Double(coordinates.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            coordinates[Int(round(Double(index) * step))]
        }
    }
}
