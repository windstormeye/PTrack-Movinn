//
//  HealthWorkoutStoreError.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import Foundation

enum HealthWorkoutStoreError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return AppLocalization.text(.healthDataUnavailable)
        case .authorizationDenied:
            return AppLocalization.text(.healthAuthorizationDenied)
        }
    }
}
