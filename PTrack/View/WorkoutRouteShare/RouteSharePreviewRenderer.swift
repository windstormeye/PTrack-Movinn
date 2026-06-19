//
//  RouteSharePreviewRenderer.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import UIKit

enum RouteSharePreviewRenderer {
    static func outputPixelSize(for previewSize: CGSize) -> CGSize {
        let aspectRatio = previewSize.width > 0 && previewSize.height > 0
            ? previewSize.height / previewSize.width
            : 1.25
        let width: CGFloat = 1080
        let height = Int((width * aspectRatio).rounded())
        return CGSize(width: width, height: CGFloat(height + height % 2))
    }

    static func image(
        from previewView: UIView,
        setSelectionChromeHidden: (Bool) -> Void,
        restoreSelection: () -> Void
    ) -> UIImage {
        setSelectionChromeHidden(true)
        defer {
            restoreSelection()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: previewView.bounds, format: format).image { _ in
            previewView.drawHierarchy(in: previewView.bounds, afterScreenUpdates: true)
        }
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
        defer {
            zip(backgroundViews, hiddenStates).forEach { view, isHidden in
                view.isHidden = isHidden
            }
            previewView.backgroundColor = backgroundColor
            restoreSelection()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            previewView.drawHierarchy(
                in: CGRect(origin: .zero, size: outputSize),
                afterScreenUpdates: true
            )
        }
    }
}
