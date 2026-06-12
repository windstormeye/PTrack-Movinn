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
            return "当前设备不支持健康数据。"
        case .authorizationDenied:
            return "未获得健康数据读取权限。"
        }
    }
}
