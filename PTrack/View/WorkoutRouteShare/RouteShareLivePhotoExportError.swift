//
//  RouteShareLivePhotoExportError.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import Foundation

enum RouteShareLivePhotoExportError: LocalizedError {
    case missingResources
    case missingStillImage
    case photoLibraryDenied
    case photoLibrarySaveFailed
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .missingResources:
            return "Live Photo resources are unavailable."
        case .missingStillImage:
            return "Live Photo still image is unavailable."
        case .photoLibraryDenied:
            return "Photo library save permission is required."
        case .photoLibrarySaveFailed:
            return "Live Photo could not be saved."
        case .renderingFailed:
            return "Live Photo rendering failed."
        }
    }
}
