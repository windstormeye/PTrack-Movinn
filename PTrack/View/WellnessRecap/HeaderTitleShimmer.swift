//
//  HeaderTitleShimmer.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  首页 title 的扫光提示:有新的运动数据或新的指导建议时,
//  在标题文字上做一次从左到右的高光扫过,提示用户点进去看。

import UIKit

enum HeaderTitleShimmer {
    private static let layerName = "com.ptrack.header-title-shimmer"

    /// 把多个标签当作一个整体,播放一次从左到右的连续扫光。
    /// 高光图层挂在它们的共同父视图上,所以 "Movin" 和 "n" 是同一道光扫过。
    static func start(on labels: [UILabel], repeatCount: Float = 10) {
        guard let container = labels.first?.superview else {
            return
        }
        stop(in: container)

        let unionFrame = labels
            .map { $0.convert($0.bounds, to: container) }
            .reduce(CGRect.null) { $0.union($1) }
        guard unionFrame.width > 1, unionFrame.height > 1 else {
            return
        }

        guard let textMask = renderTextImage(of: labels, in: container, region: unionFrame)?.cgImage else {
            return
        }

        let gradientLayer = CAGradientLayer()
        gradientLayer.name = layerName
        gradientLayer.frame = unionFrame
        gradientLayer.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.95).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [-0.4, -0.2, 0]

        // 用文字本身做蒙版,高光只出现在字形上,不会糊成一个方块。
        let maskLayer = CALayer()
        maskLayer.frame = CGRect(origin: .zero, size: unionFrame.size)
        maskLayer.contents = textMask
        gradientLayer.mask = maskLayer
        container.layer.addSublayer(gradientLayer)

        // 动 locations 而不是动图层位置,蒙版始终与文字对齐。
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.4, -0.2, 0]
        animation.toValue = [1, 1.2, 1.4]
        animation.duration = 1.15
        animation.repeatCount = repeatCount
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true

        // 用图层自身的 delegate 判断 finished,避免"新一轮扫光启动时移除旧图层"
        // 触发旧 completion,把刚加上的图层又删掉。
        let delegate = ShimmerAnimationDelegate(layer: gradientLayer)
        animation.delegate = delegate
        gradientLayer.setValue(delegate, forKey: "shimmerDelegate")
        gradientLayer.add(animation, forKey: "shimmer-sweep")
    }

    /// 只有动画自然播完才移除图层。
    private final class ShimmerAnimationDelegate: NSObject, CAAnimationDelegate {
        private weak var layer: CALayer?

        init(layer: CALayer) {
            self.layer = layer
        }

        func animationDidStop(_ animation: CAAnimation, finished: Bool) {
            guard finished else {
                return
            }
            layer?.removeFromSuperlayer()
        }
    }

    static func stop(on labels: [UILabel]) {
        guard let container = labels.first?.superview else {
            return
        }
        stop(in: container)
    }

    private static func stop(in container: UIView) {
        container.layer.sublayers?
            .filter { $0.name == layerName }
            .forEach { $0.removeFromSuperlayer() }
    }

    /// 把这组标签在统一坐标系下渲染成一张图,作为高光蒙版。
    private static func renderTextImage(
        of labels: [UILabel],
        in container: UIView,
        region: CGRect
    ) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = container.traitCollection.displayScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            for label in labels {
                let frameInRegion = label.convert(label.bounds, to: container).offsetBy(
                    dx: -region.minX,
                    dy: -region.minY
                )
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: frameInRegion.minX, y: frameInRegion.minY)
                label.layer.render(in: context.cgContext)
                context.cgContext.restoreGState()
            }
        }
    }
}
