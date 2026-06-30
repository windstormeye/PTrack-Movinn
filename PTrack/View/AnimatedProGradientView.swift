//
//  AnimatedProGradientView.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import UIKit

final class AnimatedProGradientView: UIView {
    enum Style: Equatable {
        case paywallBackground
        case proCard
        case inactiveCard
    }

    private let baseColorLayer = CALayer()
    private let colorBlockLayers = [CALayer(), CALayer(), CALayer(), CALayer()]
    private let bottomGradientLayer = CAGradientLayer()
    private let tintOverlayLayer = CALayer()
    private var style: Style = .paywallBackground
    private var overrideTraitCollection: UITraitCollection?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayers()
        registerTraitChangeHandler()
        apply(style: style)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
        registerTraitChangeHandler()
        apply(style: style)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        baseColorLayer.frame = bounds
        bottomGradientLayer.frame = bounds
        tintOverlayLayer.frame = bounds
        layoutColorBlocks()
    }

    func apply(style: Style, traitCollection overrideTraitCollection: UITraitCollection? = nil) {
        self.style = style
        self.overrideTraitCollection = overrideTraitCollection
        let palette = currentPalette
        backgroundColor = palette.backgroundColor
        baseColorLayer.backgroundColor = palette.backgroundColor.cgColor
        configureTintOverlay(with: palette)
        configureBottomGradient(with: palette)

        for (index, layer) in colorBlockLayers.enumerated() {
            configureColorBlockLayer(layer, index: index, palette: palette)
        }

        setNeedsLayout()
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.apply(style: view.style, traitCollection: view.overrideTraitCollection)
        }
    }

    private func configureLayers() {
        clipsToBounds = true
        layer.addSublayer(baseColorLayer)

        for blockLayer in colorBlockLayers {
            blockLayer.contentsGravity = .resizeAspectFill
            blockLayer.allowsEdgeAntialiasing = true
            blockLayer.magnificationFilter = .linear
            blockLayer.minificationFilter = .linear
            layer.addSublayer(blockLayer)
        }

        layer.addSublayer(tintOverlayLayer)
        bottomGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        bottomGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        bottomGradientLayer.locations = [0, 0.58, 1]
        layer.addSublayer(bottomGradientLayer)
    }

    private func configureColorBlockLayer(
        _ layer: CALayer,
        index: Int,
        palette: ColorBlockPalette
    ) {
        let color = palette.blockColors[index % palette.blockColors.count]
        layer.contents = Self.colorBlockImage(for: color, alpha: palette.blockAlpha).cgImage
        layer.opacity = Float(palette.layerOpacity)
    }

    private func configureTintOverlay(with palette: ColorBlockPalette) {
        tintOverlayLayer.backgroundColor = palette.tintColor.withAlphaComponent(palette.tintAlpha).cgColor
        tintOverlayLayer.isHidden = palette.tintAlpha <= 0
    }

    private func configureBottomGradient(with palette: ColorBlockPalette) {
        bottomGradientLayer.isHidden = palette.bottomGradientAlpha <= 0
        bottomGradientLayer.colors = [
            palette.bottomGradientColor.withAlphaComponent(0).cgColor,
            palette.bottomGradientColor.withAlphaComponent(palette.bottomGradientAlpha * 0.32).cgColor,
            palette.bottomGradientColor.withAlphaComponent(palette.bottomGradientAlpha).cgColor
        ]
    }

    private func layoutColorBlocks() {
        guard !bounds.isEmpty else {
            return
        }

        let palette = currentPalette
        let frames = initialBlockFrames(for: palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in colorBlockLayers.enumerated() {
            layer.frame = frames[index]
        }
        CATransaction.commit()
    }

    private func initialBlockFrames(for palette: ColorBlockPalette) -> [CGRect] {
        [
            blockFrame(center: CGPoint(x: 0.18, y: 0.12), scale: palette.scaleRange.lowerBound),
            blockFrame(center: CGPoint(x: 0.82, y: 0.22), scale: palette.scaleRange.upperBound * 0.9),
            blockFrame(center: CGPoint(x: 0.22, y: 0.82), scale: palette.scaleRange.upperBound),
            blockFrame(center: CGPoint(x: 0.76, y: 0.78), scale: (palette.scaleRange.lowerBound + palette.scaleRange.upperBound) / 2)
        ]
    }

    private func blockFrame(center: CGPoint, scale: CGFloat) -> CGRect {
        let side = max(bounds.width, bounds.height) * scale
        let origin = CGPoint(
            x: bounds.width * center.x - side / 2,
            y: bounds.height * center.y - side / 2
        )
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }

    private var currentPalette: ColorBlockPalette {
        Self.palette(for: style, traitCollection: overrideTraitCollection ?? traitCollection)
    }

    private static let colorBlockImageCache = NSCache<NSString, UIImage>()

    private static func colorBlockImage(for color: UIColor, alpha: CGFloat) -> UIImage {
        let components = rgbaComponents(for: color)
        let cacheKey = NSString(
            format: "%.3f-%.3f-%.3f-%.3f-%.3f",
            components.red,
            components.green,
            components.blue,
            components.alpha,
            alpha
        )
        if let cachedImage = colorBlockImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let imageSize = CGSize(width: 180, height: 180)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = false

        let image = UIGraphicsImageRenderer(size: imageSize, format: rendererFormat).image { rendererContext in
            let context = rendererContext.cgContext
            let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
            let colors = [
                color.withAlphaComponent(alpha).cgColor,
                color.withAlphaComponent(alpha * 0.34).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.48, 1]

            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else {
                return
            }

            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: imageSize.width / 2,
                options: [.drawsAfterEndLocation]
            )
        }
        colorBlockImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func rgbaComponents(for color: UIColor) -> (
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }

        let components = color.cgColor.components ?? []
        if components.count >= 4 {
            return (components[0], components[1], components[2], components[3])
        }
        if components.count >= 2 {
            return (components[0], components[0], components[0], components[1])
        }
        return (0, 0, 0, 1)
    }

    private static func palette(for style: Style, traitCollection: UITraitCollection) -> ColorBlockPalette {
        switch style {
        case .paywallBackground:
            return ColorBlockPalette(
                backgroundColor: .black,
                blockColors: [
                    AppColors.movinnGreen,
                    UIColor(red: 0.28, green: 0.42, blue: 0.03, alpha: 1),
                    UIColor(red: 0.08, green: 0.24, blue: 0.03, alpha: 1),
                    UIColor(red: 0.02, green: 0.10, blue: 0.05, alpha: 1)
                ],
                blockAlpha: 0.58,
                layerOpacity: 0.68,
                scaleRange: 0.78...1.55,
                tintColor: .black,
                tintAlpha: 0.06,
                bottomGradientColor: .black,
                bottomGradientAlpha: 0
            )
        case .proCard:
            if traitCollection.userInterfaceStyle == .dark {
                return ColorBlockPalette(
                    backgroundColor: UIColor(red: 0.36, green: 0.52, blue: 0.02, alpha: 1),
                    blockColors: [
                        AppColors.movinnGreen,
                        UIColor(red: 0.68, green: 0.86, blue: 0.10, alpha: 1),
                        UIColor(red: 0.18, green: 0.28, blue: 0.01, alpha: 1),
                        UIColor(red: 0.48, green: 0.66, blue: 0.03, alpha: 1)
                    ],
                    blockAlpha: 0.58,
                    layerOpacity: 0.72,
                    scaleRange: 1.05...1.8,
                    tintColor: .black,
                    tintAlpha: 0.06,
                    bottomGradientColor: .black,
                    bottomGradientAlpha: 0.34
                )
            }

            return ColorBlockPalette(
                backgroundColor: UIColor(red: 0.58, green: 0.76, blue: 0.02, alpha: 1),
                blockColors: [
                    AppColors.movinnGreen,
                    UIColor(red: 0.78, green: 0.94, blue: 0.18, alpha: 1),
                    UIColor(red: 0.38, green: 0.58, blue: 0.02, alpha: 1),
                    UIColor.white
                ],
                blockAlpha: 0.56,
                layerOpacity: 0.74,
                scaleRange: 1.05...1.8,
                tintColor: .white,
                tintAlpha: 0.07,
                bottomGradientColor: .white,
                bottomGradientAlpha: 0.28
            )
        case .inactiveCard:
            if traitCollection.userInterfaceStyle == .dark {
                return ColorBlockPalette(
                    backgroundColor: UIColor(white: 0.08, alpha: 1),
                    blockColors: [
                        UIColor(white: 0.02, alpha: 1),
                        UIColor(white: 0.16, alpha: 1),
                        UIColor(white: 0.26, alpha: 1),
                        UIColor(white: 0.11, alpha: 1)
                    ],
                    blockAlpha: 0.82,
                    layerOpacity: 0.78,
                    scaleRange: 1.0...1.78,
                    tintColor: .black,
                    tintAlpha: 0.08,
                    bottomGradientColor: .black,
                    bottomGradientAlpha: 0.46
                )
            }

            return ColorBlockPalette(
                backgroundColor: UIColor(white: 0.88, alpha: 1),
                blockColors: [
                    UIColor.white,
                    UIColor(white: 0.82, alpha: 1),
                    UIColor(white: 0.96, alpha: 1),
                    UIColor(white: 0.72, alpha: 1)
                ],
                blockAlpha: 0.7,
                layerOpacity: 0.72,
                scaleRange: 1.0...1.75,
                tintColor: .white,
                tintAlpha: 0.1,
                bottomGradientColor: .white,
                bottomGradientAlpha: 0.42
            )
        }
    }
}

private struct ColorBlockPalette {
    let backgroundColor: UIColor
    let blockColors: [UIColor]
    let blockAlpha: CGFloat
    let layerOpacity: CGFloat
    let scaleRange: ClosedRange<CGFloat>
    let tintColor: UIColor
    let tintAlpha: CGFloat
    let bottomGradientColor: UIColor
    let bottomGradientAlpha: CGFloat
}
