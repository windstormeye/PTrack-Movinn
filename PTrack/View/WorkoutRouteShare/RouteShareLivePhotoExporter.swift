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
        let videoTimeRange: CMTimeRange
        let audioTimeRange: CMTimeRange?
        let duration: CMTime
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let nominalFrameRate: Float
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

    private func renderLivePhoto(
        stillImage: UIImage,
        overlayImage: UIImage,
        outputSize: CGSize,
        backgroundTransform: RouteShareBackgroundRenderTransform,
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
        includesAudio: Bool,
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

    nonisolated private func writeWhiteBackgroundVideo(
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

    nonisolated private func makeWhitePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
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

    nonisolated private func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
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
