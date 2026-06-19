//
//  RouteSharePhotoLibrarySaver.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import Photos
import UIKit

enum RouteSharePhotoLibrarySaver {
    static func saveImage(
        _ image: UIImage,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(RouteShareLivePhotoExportError.photoLibraryDenied))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? RouteShareLivePhotoExportError.photoLibrarySaveFailed))
                    }
                }
            }
        }
    }

    static func saveLivePhoto(
        _ livePhotoExport: RouteShareLivePhotoExport,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    completion(.failure(RouteShareLivePhotoExportError.photoLibraryDenied))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: livePhotoExport.photoURL, options: nil)
                request.addResource(with: .pairedVideo, fileURL: livePhotoExport.pairedVideoURL, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? RouteShareLivePhotoExportError.photoLibrarySaveFailed))
                    }
                }
            }
        }
    }
}
