//
//  RouteShareColorPickerViewController.swift
//  PTrack
//
//  Created by Codex on 2026/7/1.
//

import SnapKit
import UIKit

final class RouteShareColorPickerViewController: UIViewController {
    private enum Layout {
        static let topInset: CGFloat = 14
        static let horizontalInset: CGFloat = 22
        static let closeButtonSize: CGFloat = 34
        static let paletteTopSpacing: CGFloat = 12
        static let paletteHeight: CGFloat = 228
        static let bottomInset: CGFloat = 20
        static var preferredContentHeight: CGFloat {
            topInset + closeButtonSize + paletteTopSpacing + paletteHeight + bottomInset
        }
    }

    private static let preferredPanelContentHeight = Layout.preferredContentHeight

    private let onColorChanged: (UIColor) -> Void
    private let panelView = UIView()
    private let closeButton = UIButton(type: .system)
    private let paletteView = RouteShareColorSpectrumView()
    private var panelHeightConstraint: Constraint?

    init(
        initialColor: UIColor,
        onColorChanged: @escaping (UIColor) -> Void
    ) {
        self.onColorChanged = onColorChanged
        super.init(nibName: nil, bundle: nil)
        paletteView.selectedColor = initialColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateColors()
        }
        updateColors()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updatePanelHeight()
    }

    private func configureViews() {
        view.backgroundColor = .clear

        panelView.backgroundColor = AppColors.solidBackground
        panelView.layer.cornerRadius = 24
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.layer.masksToBounds = true

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = AppColors.solidForeground
        closeButton.addTarget(self, action: #selector(dismissPicker), for: .touchUpInside)

        paletteView.layer.cornerRadius = 16
        paletteView.layer.masksToBounds = false
        paletteView.addTarget(self, action: #selector(handlePaletteChanged), for: .valueChanged)

        view.addSubview(panelView)
        panelView.addSubview(closeButton)
        panelView.addSubview(paletteView)

        panelView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            panelHeightConstraint = make.height.equalTo(Self.preferredPanelContentHeight).constraint
        }

        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.topInset)
            make.trailing.equalToSuperview().inset(18)
            make.size.equalTo(Layout.closeButtonSize)
        }

        paletteView.snp.makeConstraints { make in
            make.top.equalTo(closeButton.snp.bottom).offset(Layout.paletteTopSpacing)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset)
            make.height.equalTo(Layout.paletteHeight)
            make.bottom.equalTo(panelView.safeAreaLayoutGuide).inset(Layout.bottomInset)
        }

        updatePanelHeight()
    }

    private func updateColors() {
        panelView.backgroundColor = AppColors.solidBackground
        closeButton.tintColor = AppColors.solidForeground
    }

    private func updatePanelHeight() {
        panelHeightConstraint?.update(offset: Self.preferredPanelContentHeight + view.safeAreaInsets.bottom)
    }

    @objc private func handlePaletteChanged() {
        onColorChanged(paletteView.selectedColor)
    }

    @objc private func dismissPicker() {
        dismiss(animated: true)
    }
}

private final class RouteShareColorSpectrumView: UIControl {
    private static let paletteImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private let imageView = UIImageView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let markerView = UIView()
    private var cachedImageSize: CGSize = .zero
    private var cachedImage: UIImage?
    private var imageGenerationID = 0
    private var selectedPoint: CGPoint = .zero

    var selectedColor: UIColor = .white {
        didSet {
            selectedPoint = Self.point(for: selectedColor, in: bounds.size)
            markerView.backgroundColor = selectedColor
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.layer.cornerRadius = layer.cornerRadius
        imageView.layer.masksToBounds = true
        updatePaletteImageIfNeeded()
        if selectedPoint == .zero {
            selectedPoint = Self.point(for: selectedColor, in: bounds.size)
        }
        updateMarkerFrame()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(with: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(with: touch)
        return true
    }

    private func configureViews() {
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = AppColors.placeholderBackground

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = AppColors.foreground(alpha: 0.42)

        markerView.isUserInteractionEnabled = false
        markerView.layer.borderWidth = 3
        markerView.layer.borderColor = UIColor.white.cgColor
        markerView.layer.shadowColor = UIColor.black.cgColor
        markerView.layer.shadowOpacity = 0.24
        markerView.layer.shadowRadius = 5
        markerView.layer.shadowOffset = CGSize(width: 0, height: 2)

        addSubview(imageView)
        addSubview(loadingIndicator)
        addSubview(markerView)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func updateSelection(with touch: UITouch) {
        let location = touch.location(in: self)
        let clampedPoint = CGPoint(
            x: min(max(location.x, 0), bounds.width),
            y: min(max(location.y, 0), bounds.height)
        )
        selectedPoint = clampedPoint
        selectedColor = Self.color(at: clampedPoint, in: bounds.size)
        selectedPoint = clampedPoint
        updateMarkerFrame()
        sendActions(for: .valueChanged)
    }

    private func updateMarkerFrame() {
        let markerSize: CGFloat = 26
        let markerRadius = markerSize / 2
        markerView.bounds = CGRect(origin: .zero, size: CGSize(width: markerSize, height: markerSize))
        markerView.center = selectedPoint
        markerView.layer.cornerRadius = markerRadius
        markerView.backgroundColor = selectedColor
    }

    private func updatePaletteImageIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else {
            imageView.image = nil
            loadingIndicator.stopAnimating()
            return
        }

        let imageSize = CGSize(
            width: max(round(bounds.width), 1),
            height: max(round(bounds.height), 1)
        )
        let cacheKey = NSString(format: "%.0fx%.0f", imageSize.width, imageSize.height)
        guard cachedImage == nil || cachedImageSize != imageSize else {
            return
        }

        cachedImageSize = imageSize
        if let cachedImage = Self.paletteImageCache.object(forKey: cacheKey) {
            self.cachedImage = cachedImage
            imageView.image = cachedImage
            loadingIndicator.stopAnimating()
            return
        }

        cachedImage = nil
        imageView.image = nil
        loadingIndicator.startAnimating()

        imageGenerationID += 1
        let generationID = imageGenerationID
        DispatchQueue.global(qos: .userInitiated).async { [imageSize] in
            let cgImage = Self.makePaletteCGImage(size: imageSize)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.imageGenerationID == generationID,
                      self.cachedImageSize == imageSize else {
                    return
                }

                if let cgImage {
                    let image = UIImage(cgImage: cgImage)
                    let cost = max(Int(imageSize.width * imageSize.height * 4), 1)
                    Self.paletteImageCache.setObject(image, forKey: cacheKey, cost: cost)
                    self.cachedImage = image
                    self.imageView.image = image
                }
                self.loadingIndicator.stopAnimating()
            }
        }
    }

    private static func makePaletteCGImage(size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            let vertical = CGFloat(y) / CGFloat(max(height - 1, 1))
            for x in 0..<width {
                let hue = CGFloat(x) / CGFloat(max(width - 1, 1))
                let color = rgbByteComponents(hue: hue, vertical: vertical)
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func color(at point: CGPoint, in size: CGSize) -> UIColor {
        let hue = size.width > 0 ? min(max(point.x / size.width, 0), 1) : 0
        let vertical = size.height > 0 ? min(max(point.y / size.height, 0), 1) : 0
        return color(hue: hue, vertical: vertical)
    }

    private static func color(hue: CGFloat, vertical: CGFloat) -> UIColor {
        let rgb = rgbComponents(hue: hue, vertical: vertical)
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    private static func rgbComponents(hue: CGFloat, vertical: CGFloat) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let hueRGB = rgbComponents(forHue: hue)
        if vertical <= 0.5 {
            let amount = vertical * 2
            return (
                red: 1 + (hueRGB.red - 1) * amount,
                green: 1 + (hueRGB.green - 1) * amount,
                blue: 1 + (hueRGB.blue - 1) * amount
            )
        }

        let amount = (vertical - 0.5) * 2
        return (
            red: hueRGB.red * (1 - amount),
            green: hueRGB.green * (1 - amount),
            blue: hueRGB.blue * (1 - amount)
        )
    }

    private static func rgbByteComponents(hue: CGFloat, vertical: CGFloat) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let rgb = rgbComponents(hue: hue, vertical: vertical)
        return (
            red: UInt8(min(max(rgb.red * 255, 0), 255).rounded()),
            green: UInt8(min(max(rgb.green * 255, 0), 255).rounded()),
            blue: UInt8(min(max(rgb.blue * 255, 0), 255).rounded())
        )
    }

    private static func point(for color: UIColor, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else {
            return .zero
        }

        let resolvedColor = color.resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }

        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let hue = hueComponent(red: red, green: green, blue: blue)
        let vertical: CGFloat
        if maxComponent >= 0.995 {
            vertical = (1 - minComponent) / 2
        } else {
            vertical = 0.5 + (1 - maxComponent) / 2
        }

        return CGPoint(
            x: hue * size.width,
            y: min(max(vertical, 0), 1) * size.height
        )
    }

    private static func rgbComponents(forHue hue: CGFloat) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let scaledHue = (hue.truncatingRemainder(dividingBy: 1)) * 6
        let segment = Int(floor(scaledHue))
        let fraction = scaledHue - CGFloat(segment)
        let inverseFraction = 1 - fraction

        switch segment {
        case 0:
            return (1, fraction, 0)
        case 1:
            return (inverseFraction, 1, 0)
        case 2:
            return (0, 1, fraction)
        case 3:
            return (0, inverseFraction, 1)
        case 4:
            return (fraction, 0, 1)
        default:
            return (1, 0, inverseFraction)
        }
    }

    private static func hueComponent(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        guard delta > 0 else {
            return 0
        }

        let hue: CGFloat
        if maxComponent == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxComponent == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        return hue < 0 ? (hue + 6) / 6 : hue / 6
    }
}
