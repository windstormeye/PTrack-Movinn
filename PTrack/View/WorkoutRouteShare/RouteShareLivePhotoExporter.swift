//
//  RouteShareLivePhotoExporter.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

@preconcurrency import AVFoundation
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
        backgroundTransform: RouteShareBackgroundRenderTransform,
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
                                    backgroundTransform: backgroundTransform,
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
        backgroundTransform: RouteShareBackgroundRenderTransform,
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
                outputSize: outputSize,
                backgroundTransform: backgroundTransform
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
                backgroundTransform: backgroundTransform,
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
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { rendererContext in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: outputSize)).fill()
            drawAdjustedAspectFillImage(
                baseImage,
                in: CGRect(origin: .zero, size: outputSize),
                backgroundTransform: backgroundTransform,
                context: rendererContext.cgContext
            )
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
        backgroundTransform: RouteShareBackgroundRenderTransform,
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
                try await renderLoadedLivePhotoVideo(
                    loadedVideo,
                    outputVideoURL: outputVideoURL,
                    overlayImage: overlayImage,
                    outputSize: outputSize,
                    backgroundTransform: backgroundTransform,
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
        backgroundTransform: RouteShareBackgroundRenderTransform,
        contentIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async throws {
        let whiteBackgroundURL = outputVideoURL
            .deletingLastPathComponent()
            .appendingPathComponent("white-background.mov")
        try writeWhiteBackgroundVideo(
            to: whiteBackgroundURL,
            outputSize: outputSize,
            duration: loadedVideo.duration,
            nominalFrameRate: loadedVideo.nominalFrameRate
        )
        let whiteBackgroundAsset = AVAsset(url: whiteBackgroundURL)
        let whiteBackgroundTracks = try await whiteBackgroundAsset.loadTracks(withMediaType: .video)
        guard let whiteBackgroundTrack = whiteBackgroundTracks.first else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw RouteShareLivePhotoExportError.missingResources
        }
        guard let compositionBackgroundTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RouteShareLivePhotoExportError.missingResources
        }

        try compositionBackgroundTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: loadedVideo.duration),
            of: whiteBackgroundTrack,
            at: .zero
        )
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
            compositionBackgroundTrack: compositionBackgroundTrack,
            duration: loadedVideo.duration,
            overlayImage: overlayImage,
            outputSize: outputSize,
            backgroundTransform: backgroundTransform,
            naturalSize: loadedVideo.naturalSize,
            preferredTransform: loadedVideo.preferredTransform,
            nominalFrameRate: loadedVideo.nominalFrameRate
        )

        try? FileManager.default.removeItem(at: outputVideoURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        exportSession.metadata = livePhotoMetadata(
            from: loadedVideo.metadata,
            contentIdentifier: contentIdentifier
        )

        do {
            try await exportSession.export(to: outputVideoURL, as: .mov)
            DispatchQueue.main.async {
                completion(.success(()))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private func writeWhiteBackgroundVideo(
        to url: URL,
        outputSize: CGSize,
        duration: CMTime,
        nominalFrameRate: Float
    ) throws {
        try? FileManager.default.removeItem(at: url)
        let width = max(Int(outputSize.width.rounded()), 2)
        let height = max(Int(outputSize.height.rounded()), 2)
        let frameRate = max(Int32(nominalFrameRate.rounded()), 30)
        let frameCount = max(Int(ceil(CMTimeGetSeconds(duration) * Double(frameRate))), 1)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
        }

        writer.startSession(atSourceTime: .zero)
        let whitePixelBuffer = try makeWhitePixelBuffer(width: width, height: height)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        for frameIndex in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard adaptor.append(whitePixelBuffer, withPresentationTime: presentationTime) else {
                writer.cancelWriting()
                throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
            }
        }

        videoInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
        }
    }

    private func makeWhitePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for row in 0..<height {
            memset(baseAddress.advanced(by: row * bytesPerRow), 0xFF, width * 4)
        }

        return pixelBuffer
    }

    private func makeVideoComposition(
        compositionVideoTrack: AVCompositionTrack,
        compositionBackgroundTrack: AVCompositionTrack,
        duration: CMTime,
        overlayImage: UIImage,
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform,
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
        instruction.backgroundColor = UIColor.white.cgColor

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(
            aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                outputSize: outputSize,
                backgroundTransform: backgroundTransform
            ),
            at: .zero
        )
        let backgroundLayerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compositionBackgroundTrack
        )
        instruction.layerInstructions = [layerInstruction, backgroundLayerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        let whiteCanvasLayer = CALayer()
        let videoLayer = CALayer()
        let overlayLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        parentLayer.backgroundColor = UIColor.white.cgColor
        whiteCanvasLayer.frame = parentLayer.bounds
        whiteCanvasLayer.backgroundColor = UIColor.white.cgColor
        whiteCanvasLayer.isOpaque = true
        videoLayer.frame = parentLayer.bounds
        videoLayer.backgroundColor = UIColor.white.cgColor
        overlayLayer.frame = parentLayer.bounds
        overlayLayer.contents = overlayImage.cgImage
        overlayLayer.contentsGravity = .resize
        parentLayer.addSublayer(whiteCanvasLayer)
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
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform
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
            * backgroundTransform.scale
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let xOffset = (outputSize.width - scaledSize.width) / 2
        let yOffset = (outputSize.height - scaledSize.height) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))
            .concatenating(CGAffineTransform(translationX: -outputSize.width / 2, y: -outputSize.height / 2))
            .concatenating(CGAffineTransform(rotationAngle: backgroundTransform.rotation))
            .concatenating(CGAffineTransform(
                translationX: outputSize.width / 2 + backgroundTransform.translation.x,
                y: outputSize.height / 2 + backgroundTransform.translation.y
            ))
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

    private func drawAdjustedAspectFillImage(
        _ image: UIImage,
        in bounds: CGRect,
        backgroundTransform: RouteShareBackgroundRenderTransform,
        context: CGContext
    ) {
        let baseRect = aspectFillRect(for: image.size, in: bounds)
        let scaledSize = CGSize(
            width: baseRect.width * backgroundTransform.scale,
            height: baseRect.height * backgroundTransform.scale
        )

        context.saveGState()
        context.translateBy(
            x: bounds.midX + backgroundTransform.translation.x,
            y: bounds.midY + backgroundTransform.translation.y
        )
        context.rotate(by: backgroundTransform.rotation)
        image.draw(in: CGRect(
            x: -scaledSize.width / 2,
            y: -scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        ))
        context.restoreGState()
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
