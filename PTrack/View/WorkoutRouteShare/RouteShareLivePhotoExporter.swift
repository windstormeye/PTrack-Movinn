//
//  RouteShareLivePhotoExporter.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import AVFoundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

final class RouteShareLivePhotoExporter {
    private struct LoadedLivePhotoVideo {
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let metadataTracks: [AVAssetTrack]
        let metadata: [AVMetadataItem]
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let nominalFrameRate: Float
    }

    func export(
        asset: PHAsset,
        overlayImage: UIImage,
        outputSize: CGSize,
        completion: @escaping (Result<RouteShareLivePhotoExport, Error>) -> Void
    ) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let pairedVideoResource = resources.first(where: { $0.type == .fullSizePairedVideo })
                ?? resources.first(where: { $0.type == .pairedVideo }) else {
            completion(.failure(RouteShareLivePhotoExportError.missingResources))
            return
        }

        do {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MovinnLivePhoto-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let sourceVideoURL = directoryURL.appendingPathComponent("source-live-photo.mov")
            let photoURL = directoryURL.appendingPathComponent("movinn-live-photo.jpg")
            let videoURL = directoryURL.appendingPathComponent("movinn-live-photo.mov")
            writePairedVideoResource(
                pairedVideoResource: pairedVideoResource,
                sourceVideoURL: sourceVideoURL,
                directoryURL: directoryURL,
                completion: { [weak self] result in
                    guard let self else {
                        return
                    }

                    switch result {
                    case .success:
                        let contentIdentifier = UUID().uuidString
                        requestLivePhotoStillImage(for: asset) { [weak self] stillImageResult in
                            guard let self else {
                                return
                            }

                            switch stillImageResult {
                            case .success(let stillImage):
                                renderLivePhoto(
                                    stillImage: stillImage,
                                    overlayImage: overlayImage,
                                    outputSize: outputSize,
                                    contentIdentifier: contentIdentifier,
                                    sourceVideoURL: sourceVideoURL,
                                    photoURL: photoURL,
                                    videoURL: videoURL,
                                    directoryURL: directoryURL,
                                    completion: completion
                                )
                            case .failure(let error):
                                try? FileManager.default.removeItem(at: directoryURL)
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        try? FileManager.default.removeItem(at: directoryURL)
                        completion(.failure(error))
                    }
                }
            )
        } catch {
            completion(.failure(error))
        }
    }

    private func renderLivePhoto(
        stillImage: UIImage,
        overlayImage: UIImage,
        outputSize: CGSize,
        contentIdentifier: String,
        sourceVideoURL: URL,
        photoURL: URL,
        videoURL: URL,
        directoryURL: URL,
        completion: @escaping (Result<RouteShareLivePhotoExport, Error>) -> Void
    ) {
        do {
            let photoImage = composeStillImage(
                baseImage: stillImage,
                overlayImage: overlayImage,
                outputSize: outputSize
            )
            try writeLivePhotoJPEG(
                photoImage,
                contentIdentifier: contentIdentifier,
                to: photoURL
            )
            renderLivePhotoVideo(
                sourceVideoURL: sourceVideoURL,
                outputVideoURL: videoURL,
                overlayImage: overlayImage,
                outputSize: outputSize,
                contentIdentifier: contentIdentifier
            ) { videoResult in
                switch videoResult {
                case .success:
                    completion(.success(RouteShareLivePhotoExport(
                        photoURL: photoURL,
                        pairedVideoURL: videoURL,
                        directoryURL: directoryURL
                    )))
                case .failure(let error):
                    try? FileManager.default.removeItem(at: directoryURL)
                    completion(.failure(error))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            completion(.failure(error))
        }
    }

    private func writePairedVideoResource(
        pairedVideoResource: PHAssetResource,
        sourceVideoURL: URL,
        directoryURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(
            for: pairedVideoResource,
            toFile: sourceVideoURL,
            options: options
        ) { error in
            DispatchQueue.main.async {
                if let error {
                    try? FileManager.default.removeItem(at: directoryURL)
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private func requestLivePhotoStillImage(
        for asset: PHAsset,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            DispatchQueue.main.async {
                if let data,
                   let image = UIImage(data: data) {
                    completion(.success(image))
                } else {
                    completion(.failure(RouteShareLivePhotoExportError.missingStillImage))
                }
            }
        }
    }

    private func composeStillImage(
        baseImage: UIImage,
        overlayImage: UIImage,
        outputSize: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: outputSize)).fill()
            baseImage.draw(in: aspectFillRect(for: baseImage.size, in: CGRect(origin: .zero, size: outputSize)))
            overlayImage.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    private func writeLivePhotoJPEG(
        _ image: UIImage,
        contentIdentifier: String,
        to url: URL
    ) throws {
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        let properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.94,
            kCGImagePropertyMakerAppleDictionary as String: [
                "17": contentIdentifier
            ]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
    }

    private func renderLivePhotoVideo(
        sourceVideoURL: URL,
        outputVideoURL: URL,
        overlayImage: UIImage,
        outputSize: CGSize,
        contentIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sourceAsset = AVAsset(url: sourceVideoURL)
                let loadedVideo = try await loadedLivePhotoVideo(from: sourceAsset)
                try renderLoadedLivePhotoVideo(
                    loadedVideo,
                    outputVideoURL: outputVideoURL,
                    overlayImage: overlayImage,
                    outputSize: outputSize,
                    contentIdentifier: contentIdentifier,
                    completion: completion
                )
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func loadedLivePhotoVideo(from sourceAsset: AVAsset) async throws -> LoadedLivePhotoVideo {
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RouteShareLivePhotoExportError.missingResources
        }

        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let metadataTracks = try await sourceAsset.loadTracks(withMediaType: .metadata)
        let metadata = try await sourceAsset.load(.metadata)
        let duration = try await sourceAsset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        return LoadedLivePhotoVideo(
            videoTrack: videoTrack,
            audioTrack: audioTracks.first,
            metadataTracks: metadataTracks,
            metadata: metadata,
            duration: duration,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            nominalFrameRate: nominalFrameRate
        )
    }

    private func renderLoadedLivePhotoVideo(
        _ loadedVideo: LoadedLivePhotoVideo,
        outputVideoURL: URL,
        overlayImage: UIImage,
        outputSize: CGSize,
        contentIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            completion(.failure(RouteShareLivePhotoExportError.missingResources))
            return
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: loadedVideo.duration),
            of: loadedVideo.videoTrack,
            at: .zero
        )
        if let sourceAudioTrack = loadedVideo.audioTrack,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: loadedVideo.duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }
        for metadataTrack in loadedVideo.metadataTracks {
            if let compositionMetadataTrack = composition.addMutableTrack(
                withMediaType: .metadata,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionMetadataTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: loadedVideo.duration),
                    of: metadataTrack,
                    at: .zero
                )
            }
        }

        let videoComposition = makeVideoComposition(
            compositionVideoTrack: compositionVideoTrack,
            duration: loadedVideo.duration,
            overlayImage: overlayImage,
            outputSize: outputSize,
            naturalSize: loadedVideo.naturalSize,
            preferredTransform: loadedVideo.preferredTransform,
            nominalFrameRate: loadedVideo.nominalFrameRate
        )

        try? FileManager.default.removeItem(at: outputVideoURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(.failure(RouteShareLivePhotoExportError.renderingFailed))
            return
        }

        exportSession.outputURL = outputVideoURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        exportSession.metadata = livePhotoMetadata(
            from: loadedVideo.metadata,
            contentIdentifier: contentIdentifier
        )
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(.success(()))
                case .failed, .cancelled:
                    completion(.failure(exportSession.error ?? RouteShareLivePhotoExportError.renderingFailed))
                default:
                    completion(.failure(RouteShareLivePhotoExportError.renderingFailed))
                }
            }
        }
    }

    private func makeVideoComposition(
        compositionVideoTrack: AVCompositionTrack,
        duration: CMTime,
        overlayImage: UIImage,
        outputSize: CGSize,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        nominalFrameRate: Float
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = outputSize
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(Int32(frameRate.rounded()), 1))
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(
            aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                outputSize: outputSize
            ),
            at: .zero
        )
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        let overlayLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        videoLayer.frame = parentLayer.bounds
        overlayLayer.frame = parentLayer.bounds
        overlayLayer.contents = overlayImage.cgImage
        overlayLayer.contentsGravity = .resize
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return videoComposition
    }

    private func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        outputSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
        guard orientedSize.width > 0, orientedSize.height > 0 else {
            return preferredTransform
        }

        let scale = max(outputSize.width / orientedSize.width, outputSize.height / orientedSize.height)
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let xOffset = (outputSize.width - scaledSize.width) / 2
        let yOffset = (outputSize.height - scaledSize.height) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))
    }

    private func livePhotoMetadata(
        from metadata: [AVMetadataItem],
        contentIdentifier: String
    ) -> [AVMetadataItem] {
        var updatedMetadata = metadata.filter { !isContentIdentifierMetadataItem($0) }
        let contentIdentifierItem = AVMutableMetadataItem()
        contentIdentifierItem.keySpace = .quickTimeMetadata
        contentIdentifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        contentIdentifierItem.value = contentIdentifier as NSString
        contentIdentifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        updatedMetadata.append(contentIdentifierItem)
        return updatedMetadata
    }

    private func isContentIdentifierMetadataItem(_ item: AVMetadataItem) -> Bool {
        if item.identifier?.rawValue.contains("com.apple.quicktime.content.identifier") == true {
            return true
        }
        if let key = item.key as? String {
            return key == "com.apple.quicktime.content.identifier"
        }
        if let key = item.key as? NSString {
            return key as String == "com.apple.quicktime.content.identifier"
        }
        return false
    }

    private func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}
