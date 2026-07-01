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
        let asset: AVAsset
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let videoTimeRange: CMTimeRange
        let audioTimeRange: CMTimeRange?
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let nominalFrameRate: Float
    }

    private struct PreparedCompositeVideoSource {
        let loadedVideo: LoadedLivePhotoVideo
        let backgroundTransform: RouteShareBackgroundRenderTransform
        let clippingPath: UIBezierPath?
    }

    private struct CompositeFrameSource {
        let imageGenerator: AVAssetImageGenerator
        let videoTimeRange: CMTimeRange
        let backgroundTransform: RouteShareBackgroundRenderTransform
        let clippingPath: UIBezierPath?
        let lastFrameTime: CMTime
        var lastFrameImage: CGImage?

        mutating func frameImage(at presentationTime: CMTime) throws -> CGImage {
            let usesLastFrame = CMTimeCompare(presentationTime, lastFrameTime) >= 0
            if usesLastFrame, let lastFrameImage {
                return lastFrameImage
            }

            let sourceElapsedTime = usesLastFrame ? lastFrameTime : presentationTime
            let sourceTime = CMTimeAdd(videoTimeRange.start, sourceElapsedTime)
            let image = try imageGenerator.copyCGImage(at: sourceTime, actualTime: nil)
            if usesLastFrame {
                lastFrameImage = image
            }
            return image
        }
    }

    private final class SampleCopyPipeline: @unchecked Sendable {
        nonisolated(unsafe) let output: AVAssetReaderOutput
        nonisolated(unsafe) let input: AVAssetWriterInput

        nonisolated init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
            self.output = output
            self.input = input
        }
    }

    private final class SampleCopyContext: @unchecked Sendable {
        let pipelines: [SampleCopyPipeline]
        nonisolated(unsafe) let readers: [AVAssetReader]
        nonisolated(unsafe) let writer: AVAssetWriter

        nonisolated init(
            pipelines: [SampleCopyPipeline],
            readers: [AVAssetReader],
            writer: AVAssetWriter
        ) {
            self.pipelines = pipelines
            self.readers = readers
            self.writer = writer
        }
    }

    func export(
        asset: PHAsset,
        overlayImage: UIImage,
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform,
        canvasColor: UIColor = .white,
        includesAudio: Bool = true,
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
                                    canvasColor: canvasColor,
                                    includesAudio: includesAudio,
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

    func export(
        sources: [RouteShareLivePhotoVideoSource],
        stillImage: UIImage,
        overlayImage: UIImage,
        outputSize: CGSize,
        canvasColor: UIColor = .white,
        includesAudio: Bool = true,
        completion: @escaping (Result<RouteShareLivePhotoExport, Error>) -> Void
    ) {
        guard sources.count > 1 else {
            completion(.failure(RouteShareLivePhotoExportError.missingResources))
            return
        }

        do {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MovinnLivePhoto-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let photoURL = directoryURL.appendingPathComponent("movinn-live-photo.jpg")
            let videoURL = directoryURL.appendingPathComponent("movinn-live-photo.mov")
            let contentIdentifier = UUID().uuidString

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let preparedSources = try await prepareCompositeVideoSources(
                        sources,
                        directoryURL: directoryURL
                    )
                    try writeLivePhotoJPEG(
                        stillImage,
                        contentIdentifier: contentIdentifier,
                        to: photoURL
                    )
                    try await renderCompositeLivePhotoVideo(
                        sources: preparedSources,
                        overlayImage: overlayImage,
                        outputSize: outputSize,
                        canvasColor: canvasColor,
                        includesAudio: includesAudio,
                        contentIdentifier: contentIdentifier,
                        outputVideoURL: videoURL
                    )
                    DispatchQueue.main.async {
                        completion(.success(RouteShareLivePhotoExport(
                            photoURL: photoURL,
                            pairedVideoURL: videoURL,
                            directoryURL: directoryURL
                        )))
                    }
                } catch {
                    try? FileManager.default.removeItem(at: directoryURL)
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func renderLivePhoto(
        stillImage: UIImage,
        overlayImage: UIImage,
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform,
        canvasColor: UIColor,
        includesAudio: Bool,
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
                backgroundTransform: backgroundTransform,
                canvasColor: canvasColor
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
                canvasColor: canvasColor,
                includesAudio: includesAudio,
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

    private func prepareCompositeVideoSources(
        _ sources: [RouteShareLivePhotoVideoSource],
        directoryURL: URL
    ) async throws -> [PreparedCompositeVideoSource] {
        var preparedSources: [PreparedCompositeVideoSource] = []
        preparedSources.reserveCapacity(sources.count)

        for (index, source) in sources.enumerated() {
            let pairedVideoResource = try pairedVideoResource(for: source.asset)
            let sourceVideoURL = directoryURL
                .appendingPathComponent("source-live-photo-\(index).mov")
            try await writePairedVideoResource(
                pairedVideoResource: pairedVideoResource,
                sourceVideoURL: sourceVideoURL
            )

            let sourceAsset = AVAsset(url: sourceVideoURL)
            let loadedVideo = try await loadedLivePhotoVideo(from: sourceAsset)
            preparedSources.append(PreparedCompositeVideoSource(
                loadedVideo: loadedVideo,
                backgroundTransform: source.backgroundTransform,
                clippingPath: source.clippingPath?.copy() as? UIBezierPath
            ))
        }

        return preparedSources
    }

    private func pairedVideoResource(for asset: PHAsset) throws -> PHAssetResource {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let pairedVideoResource = resources.first(where: { $0.type == .fullSizePairedVideo })
                ?? resources.first(where: { $0.type == .pairedVideo }) else {
            throw RouteShareLivePhotoExportError.missingResources
        }
        return pairedVideoResource
    }

    private func writePairedVideoResource(
        pairedVideoResource: PHAssetResource,
        sourceVideoURL: URL
    ) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: pairedVideoResource,
                toFile: sourceVideoURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
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
        backgroundTransform: RouteShareBackgroundRenderTransform,
        canvasColor: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { rendererContext in
            canvasColor.setFill()
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

    nonisolated private func writeLivePhotoJPEG(
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
        canvasColor: UIColor,
        includesAudio: Bool,
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
                    canvasColor: canvasColor,
                    includesAudio: includesAudio,
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

    nonisolated private func loadedLivePhotoVideo(from sourceAsset: AVAsset) async throws -> LoadedLivePhotoVideo {
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RouteShareLivePhotoExportError.missingResources
        }

        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let duration = try await sourceAsset.load(.duration)
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let audioTimeRange = try await audioTracks.first?.load(.timeRange)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        return LoadedLivePhotoVideo(
            asset: sourceAsset,
            videoTrack: videoTrack,
            audioTrack: audioTracks.first,
            videoTimeRange: videoTimeRange,
            audioTimeRange: audioTimeRange,
            duration: minTime(duration, videoTimeRange.duration),
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
        canvasColor: UIColor,
        includesAudio: Bool,
        contentIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async throws {
        let solidBackgroundURL = outputVideoURL
            .deletingLastPathComponent()
            .appendingPathComponent("solid-background.mov")
        try writeSolidBackgroundVideo(
            to: solidBackgroundURL,
            outputSize: outputSize,
            duration: loadedVideo.duration,
            nominalFrameRate: loadedVideo.nominalFrameRate,
            backgroundColor: canvasColor
        )
        let solidBackgroundAsset = AVAsset(url: solidBackgroundURL)
        let solidBackgroundTracks = try await solidBackgroundAsset.loadTracks(withMediaType: .video)
        guard let solidBackgroundTrack = solidBackgroundTracks.first else {
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
            of: solidBackgroundTrack,
            at: .zero
        )
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: loadedVideo.videoTimeRange.start, duration: loadedVideo.duration),
            of: loadedVideo.videoTrack,
            at: .zero
        )
        if includesAudio,
           let sourceAudioTrack = loadedVideo.audioTrack,
           let sourceAudioTimeRange = loadedVideo.audioTimeRange,
           let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioDuration = minTime(sourceAudioTimeRange.duration, loadedVideo.duration)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: sourceAudioTimeRange.start, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }
        let videoComposition = makeVideoComposition(
            compositionVideoTrack: compositionVideoTrack,
            compositionBackgroundTrack: compositionBackgroundTrack,
            duration: loadedVideo.duration,
            overlayImage: overlayImage,
            outputSize: outputSize,
            backgroundTransform: backgroundTransform,
            canvasColor: canvasColor,
            naturalSize: loadedVideo.naturalSize,
            preferredTransform: loadedVideo.preferredTransform,
            nominalFrameRate: loadedVideo.nominalFrameRate
        )

        let renderedVideoURL = outputVideoURL
            .deletingLastPathComponent()
            .appendingPathComponent("rendered-live-photo.mov")
        try? FileManager.default.removeItem(at: renderedVideoURL)
        try? FileManager.default.removeItem(at: outputVideoURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        do {
            try await exportSession.export(to: renderedVideoURL, as: .mov)
            try await writeLivePhotoPairedVideo(
                from: renderedVideoURL,
                to: outputVideoURL,
                contentIdentifier: contentIdentifier
            )
            DispatchQueue.main.async {
                completion(.success(()))
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private func renderCompositeLivePhotoVideo(
        sources: [PreparedCompositeVideoSource],
        overlayImage: UIImage,
        outputSize: CGSize,
        canvasColor: UIColor,
        includesAudio: Bool,
        contentIdentifier: String,
        outputVideoURL: URL
    ) async throws {
        let outputDuration = sources
            .map(\.loadedVideo.duration)
            .reduce(CMTime.zero, maxTime)
        guard CMTimeCompare(outputDuration, .zero) > 0 else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        let renderedVideoURL = outputVideoURL
            .deletingLastPathComponent()
            .appendingPathComponent("rendered-composite-live-photo.mov")
        let renderedVideoWithAudioURL = outputVideoURL
            .deletingLastPathComponent()
            .appendingPathComponent("rendered-composite-live-photo-audio.mov")
        try? FileManager.default.removeItem(at: renderedVideoURL)
        try? FileManager.default.removeItem(at: renderedVideoWithAudioURL)
        try? FileManager.default.removeItem(at: outputVideoURL)

        let frameRate = compositeFrameRate(for: sources)
        try writeCompositeVideoFrames(
            to: renderedVideoURL,
            sources: sources,
            overlayImage: overlayImage,
            outputSize: outputSize,
            canvasColor: canvasColor,
            duration: outputDuration,
            frameRate: frameRate
        )

        let pairedVideoSourceURL: URL
        if includesAudio {
            pairedVideoSourceURL = try await writeCompositeAudioVideo(
                videoURL: renderedVideoURL,
                sources: sources,
                duration: outputDuration,
                outputURL: renderedVideoWithAudioURL
            )
        } else {
            pairedVideoSourceURL = renderedVideoURL
        }

        try await writeLivePhotoPairedVideo(
            from: pairedVideoSourceURL,
            to: outputVideoURL,
            contentIdentifier: contentIdentifier
        )
    }

    private func writeCompositeVideoFrames(
        to url: URL,
        sources: [PreparedCompositeVideoSource],
        overlayImage: UIImage,
        outputSize: CGSize,
        canvasColor: UIColor,
        duration: CMTime,
        frameRate: Int32
    ) throws {
        let width = max(Int(outputSize.width.rounded()), 2)
        let height = max(Int(outputSize.height.rounded()), 2)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
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
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        var frameSources = makeCompositeFrameSources(
            from: sources,
            frameDuration: frameDuration,
            frameRate: frameRate
        )

        do {
            for frameIndex in 0..<frameCount {
                while !videoInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.002)
                }

                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                try autoreleasepool {
                    let frameImage = try compositeFrameImage(
                        at: presentationTime,
                        frameSources: &frameSources,
                        overlayImage: overlayImage,
                        outputSize: outputSize,
                        canvasColor: canvasColor
                    )
                    let pixelBuffer = try makePixelBuffer(
                        from: frameImage,
                        pixelBufferPool: pixelBufferPool,
                        width: width,
                        height: height
                    )
                    guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
                    }
                }
            }
        } catch {
            writer.cancelWriting()
            throw error
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

    private func makeCompositeFrameSources(
        from sources: [PreparedCompositeVideoSource],
        frameDuration: CMTime,
        frameRate: Int32
    ) -> [CompositeFrameSource] {
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(max(frameRate * 2, 1)))
        return sources.map { source in
            let imageGenerator = AVAssetImageGenerator(asset: source.loadedVideo.asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceBefore = tolerance
            imageGenerator.requestedTimeToleranceAfter = tolerance

            return CompositeFrameSource(
                imageGenerator: imageGenerator,
                videoTimeRange: source.loadedVideo.videoTimeRange,
                backgroundTransform: source.backgroundTransform,
                clippingPath: source.clippingPath,
                lastFrameTime: maxTime(.zero, CMTimeSubtract(source.loadedVideo.duration, frameDuration)),
                lastFrameImage: nil
            )
        }
    }

    private func compositeFrameImage(
        at presentationTime: CMTime,
        frameSources: inout [CompositeFrameSource],
        overlayImage: UIImage,
        outputSize: CGSize,
        canvasColor: UIColor
    ) throws -> CGImage {
        var layerImages: [(CGImage, RouteShareBackgroundRenderTransform, UIBezierPath?)] = []
        layerImages.reserveCapacity(frameSources.count)
        for index in frameSources.indices {
            let frameImage = try frameSources[index].frameImage(at: presentationTime)
            layerImages.append((
                frameImage,
                frameSources[index].backgroundTransform,
                frameSources[index].clippingPath
            ))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: outputSize, format: format).image { rendererContext in
            canvasColor.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: outputSize)).fill()

            for (frameImage, backgroundTransform, clippingPath) in layerImages {
                rendererContext.cgContext.saveGState()
                clippingPath?.addClip()
                drawAdjustedAspectFillImage(
                    UIImage(cgImage: frameImage),
                    in: CGRect(origin: .zero, size: outputSize),
                    backgroundTransform: backgroundTransform,
                    context: rendererContext.cgContext
                )
                rendererContext.cgContext.restoreGState()
            }

            overlayImage.draw(in: CGRect(origin: .zero, size: outputSize))
        }

        guard let cgImage = image.cgImage else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
        return cgImage
    }

    private func makePixelBuffer(
        from image: CGImage,
        pixelBufferPool: CVPixelBufferPool,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private func writeCompositeAudioVideo(
        videoURL: URL,
        sources: [PreparedCompositeVideoSource],
        duration: CMTime,
        outputURL: URL
    ) async throws -> URL {
        let renderedVideoAsset = AVAsset(url: videoURL)
        let renderedVideoTracks = try await renderedVideoAsset.loadTracks(withMediaType: .video)
        guard let renderedVideoTrack = renderedVideoTracks.first else {
            throw RouteShareLivePhotoExportError.missingResources
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RouteShareLivePhotoExportError.missingResources
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: renderedVideoTrack,
            at: .zero
        )

        var audioMixParameters: [AVMutableAudioMixInputParameters] = []
        for source in sources {
            guard let sourceAudioTrack = source.loadedVideo.audioTrack,
                  let sourceAudioTimeRange = source.loadedVideo.audioTimeRange,
                  let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                continue
            }

            let audioDuration = minTime(
                minTime(sourceAudioTimeRange.duration, source.loadedVideo.duration),
                duration
            )
            guard CMTimeCompare(audioDuration, .zero) > 0 else {
                continue
            }

            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: sourceAudioTimeRange.start, duration: audioDuration),
                of: sourceAudioTrack,
                at: .zero
            )
            let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            parameters.setVolume(1, at: .zero)
            audioMixParameters.append(parameters)
        }

        guard !audioMixParameters.isEmpty else {
            return videoURL
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParameters

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.audioMix = audioMix
        try await exportSession.export(to: outputURL, as: .mov)
        return outputURL
    }

    nonisolated private func writeLivePhotoPairedVideo(
        from renderedVideoURL: URL,
        to outputVideoURL: URL,
        contentIdentifier: String
    ) async throws {
        try? FileManager.default.removeItem(at: outputVideoURL)

        let asset = AVAsset(url: renderedVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RouteShareLivePhotoExportError.missingResources
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoFormatDescriptions = try await videoTrack.load(.formatDescriptions)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputVideoURL, fileType: .mov)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = livePhotoMetadata(contentIdentifier: contentIdentifier)

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: videoFormatDescriptions.first
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = .identity
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        var samplePipelines: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(videoOutput, videoInput)]
        for audioTrack in audioTracks {
            let audioFormatDescriptions = try await audioTrack.load(.formatDescriptions)
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            audioOutput.alwaysCopiesSampleData = false
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: audioFormatDescriptions.first
            )
            audioInput.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOutput), writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                samplePipelines.append((audioOutput, audioInput))
            }
        }

        let metadataAdaptor = try makeStillImageTimeMetadataAdaptor(for: writer)

        do {
            guard writer.startWriting() else {
                throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
            }
            guard reader.startReading() else {
                writer.cancelWriting()
                throw reader.error ?? RouteShareLivePhotoExportError.renderingFailed
            }

            writer.startSession(atSourceTime: .zero)
            try appendStillImageTimeMetadata(using: metadataAdaptor)
            try await copySamplePipelines(samplePipelines, readers: [reader], writer: writer)

            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }

            if reader.status == .failed || reader.status == .cancelled {
                throw reader.error ?? RouteShareLivePhotoExportError.renderingFailed
            }
            guard writer.status == .completed else {
                throw writer.error ?? RouteShareLivePhotoExportError.renderingFailed
            }
        } catch {
            logAssetCopyFailure(error, reader: reader, writer: writer, context: "paired-video-write")
            throw error
        }
    }

    nonisolated private func makeStillImageTimeMetadataAdaptor(
        for writer: AVAssetWriter
    ) throws -> AVAssetWriterInputMetadataAdaptor {
        let metadataSpecification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8
        ]
        var formatDescription: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [metadataSpecification] as CFArray,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        let metadataInput = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        metadataInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(metadataInput) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
        writer.add(metadataInput)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
    }

    nonisolated private func appendStillImageTimeMetadata(
        using metadataAdaptor: AVAssetWriterInputMetadataAdaptor
    ) throws {
        let metadataInput = metadataAdaptor.assetWriterInput
        while !metadataInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        let stillImageTimeItem = AVMutableMetadataItem()
        stillImageTimeItem.keySpace = .quickTimeMetadata
        stillImageTimeItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillImageTimeItem.value = 0 as NSNumber
        stillImageTimeItem.dataType = kCMMetadataBaseDataType_SInt8 as String
        let metadataGroup = AVTimedMetadataGroup(
            items: [stillImageTimeItem],
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 100))
        )
        guard metadataAdaptor.append(metadataGroup) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }
        metadataInput.markAsFinished()
    }

    nonisolated private func copySamplePipelines(
        _ samplePipelines: [(AVAssetReaderOutput, AVAssetWriterInput)],
        readers: [AVAssetReader],
        writer: AVAssetWriter
    ) async throws {
        let context = SampleCopyContext(
            pipelines: samplePipelines.map { output, input in
                SampleCopyPipeline(output: output, input: input)
            },
            readers: readers,
            writer: writer
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()
            let stateQueue = DispatchQueue(label: "com.ptrack.live-photo.sample-copy.state")
            var firstError: Error?

            func recordFailure(_ error: Error) {
                stateQueue.sync {
                    guard firstError == nil else {
                        return
                    }
                    firstError = error
                    context.readers.forEach { $0.cancelReading() }
                    context.writer.cancelWriting()
                }
            }

            for (index, pipeline) in context.pipelines.enumerated() {
                let queue = DispatchQueue(label: "com.ptrack.live-photo.sample-copy.\(index)")
                group.enter()
                queue.async {
                    defer {
                        group.leave()
                    }

                    while true {
                        if let failedReader = context.readers.first(where: { $0.status == .failed || $0.status == .cancelled }) {
                            recordFailure(failedReader.error ?? RouteShareLivePhotoExportError.renderingFailed)
                            return
                        }
                        if context.writer.status == .failed || context.writer.status == .cancelled {
                            recordFailure(context.writer.error ?? RouteShareLivePhotoExportError.renderingFailed)
                            return
                        }

                        guard pipeline.input.isReadyForMoreMediaData else {
                            Thread.sleep(forTimeInterval: 0.002)
                            continue
                        }

                        if let sampleBuffer = pipeline.output.copyNextSampleBuffer() {
                            guard pipeline.input.append(sampleBuffer) else {
                                recordFailure(context.writer.error ?? RouteShareLivePhotoExportError.renderingFailed)
                                return
                            }
                        } else {
                            pipeline.input.markAsFinished()
                            return
                        }
                    }
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                stateQueue.sync {
                    if let firstError {
                        continuation.resume(throwing: firstError)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    nonisolated private func writeSolidBackgroundVideo(
        to url: URL,
        outputSize: CGSize,
        duration: CMTime,
        nominalFrameRate: Float,
        backgroundColor: UIColor
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
        let solidPixelBuffer = try makeSolidPixelBuffer(
            width: width,
            height: height,
            color: backgroundColor
        )
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        for frameIndex in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard adaptor.append(solidPixelBuffer, withPresentationTime: presentationTime) else {
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

    nonisolated private func makeSolidPixelBuffer(
        width: Int,
        height: Int,
        color: UIColor
    ) throws -> CVPixelBuffer {
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
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw RouteShareLivePhotoExportError.renderingFailed
        }

        context.setFillColor(color.resolvedColor(with: UITraitCollection.current).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    nonisolated private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

    nonisolated private func maxTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
    }

    private func compositeFrameRate(for sources: [PreparedCompositeVideoSource]) -> Int32 {
        let nominalFrameRate = sources
            .map(\.loadedVideo.nominalFrameRate)
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 30
        return max(Int32(nominalFrameRate.rounded()), 30)
    }

    nonisolated private func logAssetCopyFailure(
        _ error: Error,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        context: String
    ) {
        let readerError = reader.error as NSError?
        let writerError = writer.error as NSError?
        print(
            """
            RouteShareLivePhotoExporter \(context) failed:
            thrown=\(detailedErrorDescription(error))
            readerStatus=\(reader.status.rawValue)
            readerError=\(readerError.map(detailedNSErrorDescription) ?? "nil")
            writerStatus=\(writer.status.rawValue)
            writerError=\(writerError.map(detailedNSErrorDescription) ?? "nil")
            """
        )
    }

    nonisolated private func detailedErrorDescription(_ error: Error) -> String {
        detailedNSErrorDescription(error as NSError)
    }

    nonisolated private func detailedNSErrorDescription(_ error: NSError) -> String {
        "\(error.domain)(\(error.code)) \(error.localizedDescription) userInfo=\(error.userInfo)"
    }

    nonisolated private func makeVideoComposition(
        compositionVideoTrack: AVCompositionTrack,
        compositionBackgroundTrack: AVCompositionTrack,
        duration: CMTime,
        overlayImage: UIImage,
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform,
        canvasColor: UIColor,
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
        instruction.backgroundColor = canvasColor.resolvedColor(with: UITraitCollection.current).cgColor

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
        let canvasLayer = CALayer()
        let videoLayer = CALayer()
        let overlayLayer = CALayer()
        let resolvedCanvasColor = canvasColor.resolvedColor(with: UITraitCollection.current).cgColor
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        parentLayer.backgroundColor = resolvedCanvasColor
        canvasLayer.frame = parentLayer.bounds
        canvasLayer.backgroundColor = resolvedCanvasColor
        canvasLayer.isOpaque = true
        videoLayer.frame = parentLayer.bounds
        videoLayer.backgroundColor = resolvedCanvasColor
        overlayLayer.frame = parentLayer.bounds
        overlayLayer.contents = overlayImage.cgImage
        overlayLayer.contentsGravity = .resize
        parentLayer.addSublayer(canvasLayer)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        return videoComposition
    }

    nonisolated private func aspectFillTransform(
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

    nonisolated private func livePhotoMetadata(contentIdentifier: String) -> [AVMetadataItem] {
        let contentIdentifierItem = AVMutableMetadataItem()
        contentIdentifierItem.keySpace = .quickTimeMetadata
        contentIdentifierItem.key = "com.apple.quicktime.content.identifier" as NSString
        contentIdentifierItem.value = contentIdentifier as NSString
        contentIdentifierItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        return [contentIdentifierItem]
    }

    nonisolated private func drawAdjustedAspectFillImage(
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

    nonisolated private func aspectFillRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
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
