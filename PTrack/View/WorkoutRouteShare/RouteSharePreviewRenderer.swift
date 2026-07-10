//
//  RouteSharePreviewRenderer.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import UIKit

enum RouteSharePreviewRenderer {
    private final class TiledImageRenderJob {
        private let previewView: UIView
        private let setSelectionChromeHidden: (Bool) -> Void
        private let restoreSelection: () -> Void
        private let progressHandler: (Double) -> Void
        private let completion: (Result<UIImage, Error>) -> Void
        private let outputScale: CGFloat
        private let pixelWidth: Int
        private let pixelHeight: Int
        private let tileHeight = 512
        private let tileOverlap = 2
        private let compositionQueue = DispatchQueue(
            label: "com.ptrack.route-share.preview-render",
            qos: .userInitiated
        )
        private var bitmapContext: CGContext?
        private var nextTileY = 0
        private var hasFinished = false

        init(
            previewView: UIView,
            setSelectionChromeHidden: @escaping (Bool) -> Void,
            restoreSelection: @escaping () -> Void,
            progressHandler: @escaping (Double) -> Void,
            completion: @escaping (Result<UIImage, Error>) -> Void
        ) {
            self.previewView = previewView
            self.setSelectionChromeHidden = setSelectionChromeHidden
            self.restoreSelection = restoreSelection
            self.progressHandler = progressHandler
            self.completion = completion
            outputScale = max(UIScreen.main.scale, 1)
            pixelWidth = max(Int(ceil(previewView.bounds.width * outputScale)), 1)
            pixelHeight = max(Int(ceil(previewView.bounds.height * outputScale)), 1)
        }

        func start() {
            setSelectionChromeHidden(true)
            RouteSharePreviewRenderer.prepareForCapture(previewView)
            progressHandler(0.02)

            let pixelWidth = self.pixelWidth
            let pixelHeight = self.pixelHeight
            compositionQueue.async { [self] in
                guard let context = Self.makeBitmapContext(width: pixelWidth, height: pixelHeight) else {
                    DispatchQueue.main.async { [self] in
                        finish(.failure(RouteShareLivePhotoExportError.renderingFailed))
                    }
                    return
                }

                bitmapContext = context
                DispatchQueue.main.async { [self] in
                    captureNextTile()
                }
            }
        }

        private func captureNextTile() {
            guard !hasFinished else {
                return
            }
            guard nextTileY < pixelHeight else {
                finishCompositing()
                return
            }

            let coreStartY = nextTileY
            let coreEndY = min(coreStartY + tileHeight, pixelHeight)
            let captureStartY = max(coreStartY - tileOverlap, 0)
            let captureEndY = min(coreEndY + tileOverlap, pixelHeight)
            let captureHeight = captureEndY - captureStartY
            let outputSize = CGSize(width: pixelWidth, height: pixelHeight)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let tileImage = autoreleasepool {
                UIGraphicsImageRenderer(
                    size: CGSize(width: pixelWidth, height: captureHeight),
                    format: format
                ).image { _ in
                    previewView.drawHierarchy(
                        in: CGRect(
                            x: 0,
                            y: -CGFloat(captureStartY),
                            width: outputSize.width,
                            height: outputSize.height
                        ),
                        afterScreenUpdates: false
                    )
                }
            }

            guard let tileCGImage = tileImage.cgImage else {
                finish(.failure(RouteShareLivePhotoExportError.renderingFailed))
                return
            }

            compositionQueue.async { [self] in
                guard let bitmapContext else {
                    DispatchQueue.main.async { [self] in
                        finish(.failure(RouteShareLivePhotoExportError.renderingFailed))
                    }
                    return
                }

                bitmapContext.draw(
                    tileCGImage,
                    in: CGRect(
                        x: 0,
                        y: pixelHeight - captureStartY - captureHeight,
                        width: pixelWidth,
                        height: captureHeight
                    )
                )
                let progress = Double(coreEndY) / Double(pixelHeight)
                DispatchQueue.main.async { [self] in
                    guard !hasFinished else {
                        return
                    }
                    nextTileY = coreEndY
                    progressHandler(0.02 + progress * 0.94)
                    captureNextTile()
                }
            }
        }

        private func finishCompositing() {
            compositionQueue.async { [self] in
                guard let outputCGImage = bitmapContext?.makeImage() else {
                    DispatchQueue.main.async { [self] in
                        finish(.failure(RouteShareLivePhotoExportError.renderingFailed))
                    }
                    return
                }

                DispatchQueue.main.async { [self] in
                    let image = UIImage(cgImage: outputCGImage, scale: outputScale, orientation: .up)
                    progressHandler(1)
                    finish(.success(image))
                }
            }
        }

        private func finish(_ result: Result<UIImage, Error>) {
            guard !hasFinished else {
                return
            }
            hasFinished = true
            bitmapContext = nil
            setSelectionChromeHidden(false)
            restoreSelection()
            completion(result)
        }

        nonisolated private static func makeBitmapContext(width: Int, height: Int) -> CGContext? {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                return nil
            }
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            return context
        }
    }

    static func outputPixelSize(for previewSize: CGSize) -> CGSize {
        let aspectRatio = previewSize.width > 0 && previewSize.height > 0
            ? previewSize.height / previewSize.width
            : 1.25
        let width: CGFloat = 1080
        let height = Int((width * aspectRatio).rounded())
        return CGSize(width: width, height: CGFloat(height + height % 2))
    }

    static func renderImage(
        from previewView: UIView,
        setSelectionChromeHidden: @escaping (Bool) -> Void,
        restoreSelection: @escaping () -> Void,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        TiledImageRenderJob(
            previewView: previewView,
            setSelectionChromeHidden: setSelectionChromeHidden,
            restoreSelection: restoreSelection,
            progressHandler: progressHandler,
            completion: completion
        ).start()
    }

    static func overlayImage(
        from previewView: UIView,
        backgroundViews: [UIView],
        outputSize: CGSize,
        setSelectionChromeHidden: (Bool) -> Void,
        restoreSelection: () -> Void
    ) -> UIImage {
        let hiddenStates = backgroundViews.map(\.isHidden)
        let backgroundColor = previewView.backgroundColor

        backgroundViews.forEach { $0.isHidden = true }
        previewView.backgroundColor = .clear
        setSelectionChromeHidden(true)
        prepareForCapture(previewView)
        defer {
            zip(backgroundViews, hiddenStates).forEach { view, isHidden in
                view.isHidden = isHidden
            }
            previewView.backgroundColor = backgroundColor
            setSelectionChromeHidden(false)
            restoreSelection()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            previewView.drawHierarchy(
                in: CGRect(origin: .zero, size: outputSize),
                afterScreenUpdates: false
            )
        }
    }

    private static func prepareForCapture(_ view: UIView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.layer.setNeedsDisplay()
        view.layer.displayIfNeeded()
        CATransaction.flush()
    }
}
