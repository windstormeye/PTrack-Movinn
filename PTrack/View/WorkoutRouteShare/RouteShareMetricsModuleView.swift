//
//  RouteShareMetricsModuleView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

struct RouteShareCalorieFoodOption: CaseIterable, Equatable {
    let emoji: String
    let name: String
    let unit: String
    let kilocalories: Double

    static let allCases: [RouteShareCalorieFoodOption] = [
        RouteShareCalorieFoodOption(emoji: "🥒", name: "黄瓜", unit: "根", kilocalories: 16),
        RouteShareCalorieFoodOption(emoji: "🍅", name: "西红柿", unit: "个", kilocalories: 25),
        RouteShareCalorieFoodOption(emoji: "🍊", name: "橙子", unit: "个", kilocalories: 70),
        RouteShareCalorieFoodOption(emoji: "🍌", name: "香蕉", unit: "根", kilocalories: 120),
        RouteShareCalorieFoodOption(emoji: "🍠", name: "红薯", unit: "块", kilocalories: 160),
        RouteShareCalorieFoodOption(emoji: "🍦", name: "冰淇淋", unit: "个", kilocalories: 200),
        RouteShareCalorieFoodOption(emoji: "🍟", name: "小份薯条", unit: "份", kilocalories: 260),
        RouteShareCalorieFoodOption(emoji: "🍚", name: "米饭", unit: "碗", kilocalories: 200)
    ]

    var menuTitle: String {
        "\(emoji)\(name) \(Int(kilocalories)) 大卡"
    }
}

final class RouteShareMetricsModuleView: UIView {
    let deleteButton = RouteShareModuleChrome.makeDeleteButton()

    private let distanceLabel = UILabel()
    private let durationLabel = UILabel()
    private let timeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(with workout: TrackedWorkout, color: UIColor) {
        distanceLabel.text = workout.distanceText
        durationLabel.text = durationAndElevationText(for: workout)
        timeLabel.text = calorieText(for: workout)
        timeLabel.isHidden = timeLabel.text == nil
        applyColor(color)
    }

    func updateLocalizedText(for workout: TrackedWorkout) {
        durationLabel.text = durationAndElevationText(for: workout)
        timeLabel.text = calorieText(for: workout)
        timeLabel.isHidden = timeLabel.text == nil
    }

    func applyColor(_ color: UIColor) {
        distanceLabel.textColor = color
        durationLabel.textColor = color.withAlphaComponent(0.92)
        timeLabel.textColor = color.withAlphaComponent(0.86)
        applyTextShadow(isVisible: !isEffectivelyBlack(color))
    }

    func selectionChromeRect() -> CGRect {
        layoutIfNeeded()
        let contentRect = [distanceLabel, durationLabel, timeLabel]
            .map(textContentRect(for:))
            .reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -7, dy: -5)
        let clippedRect = contentRect.intersection(bounds)
        return clippedRect.isNull || clippedRect.isEmpty ? bounds.insetBy(dx: 12, dy: 8) : clippedRect
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        selectionChromeRect().contains(point)
    }

    private func configureViews() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = false

        distanceLabel.font = .systemFont(ofSize: 38, weight: .heavy)
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.62
        distanceLabel.numberOfLines = 1

        durationLabel.font = .systemFont(ofSize: 18, weight: .bold)
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.7
        durationLabel.numberOfLines = 1

        timeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.7
        timeLabel.numberOfLines = 1
        timeLabel.clipsToBounds = false

        [distanceLabel, durationLabel, timeLabel].forEach { label in
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.36
            label.layer.shadowRadius = 6
            label.layer.shadowOffset = CGSize(width: 0, height: 2)
        }

        addSubview(distanceLabel)
        addSubview(durationLabel)
        addSubview(timeLabel)

        distanceLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        durationLabel.snp.makeConstraints { make in
            make.leading.equalTo(distanceLabel)
            make.top.equalTo(distanceLabel.snp.bottom).offset(2)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(distanceLabel)
            make.top.equalTo(durationLabel.snp.bottom).offset(6)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
            make.height.greaterThanOrEqualTo(18)
            make.bottom.lessThanOrEqualToSuperview().inset(8)
        }
    }

    private func applyTextShadow(isVisible: Bool) {
        [distanceLabel, durationLabel, timeLabel].forEach { label in
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = isVisible ? 0.36 : 0
            label.layer.shadowRadius = isVisible ? 6 : 0
            label.layer.shadowOffset = isVisible ? CGSize(width: 0, height: 2) : .zero
        }
    }

    private func textContentRect(for label: UILabel) -> CGRect {
        guard !label.isHidden,
              let text = label.text,
              !text.isEmpty,
              label.bounds.width > 0,
              label.bounds.height > 0 else {
            return .null
        }

        let fittingSize = label.sizeThatFits(CGSize(
            width: label.bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        let contentWidth = min(ceil(fittingSize.width), label.bounds.width)
        let contentHeight = min(ceil(fittingSize.height), label.bounds.height)
        let xOffset: CGFloat
        switch label.textAlignment {
        case .center:
            xOffset = (label.bounds.width - contentWidth) / 2
        case .right:
            xOffset = label.bounds.width - contentWidth
        case .natural where effectiveUserInterfaceLayoutDirection == .rightToLeft:
            xOffset = label.bounds.width - contentWidth
        default:
            xOffset = 0
        }
        let yOffset = (label.bounds.height - contentHeight) / 2

        return CGRect(
            x: label.frame.minX + xOffset,
            y: label.frame.minY + yOffset,
            width: contentWidth,
            height: contentHeight
        )
    }

    private func isEffectivelyBlack(_ color: UIColor) -> Bool {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if resolvedColor.getWhite(&white, alpha: &alpha) {
            return white < 0.08
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return max(red, green, blue) < 0.08
        }

        return false
    }

    private func durationAndElevationText(for workout: TrackedWorkout) -> String {
        if let elevationGainText = workout.elevationGainText {
            return "\(workout.durationText) · \(elevationGainText)"
        }

        return workout.durationText
    }

    private func calorieText(for workout: TrackedWorkout) -> String? {
        guard let caloriesKilocalories = workout.displayEnergyBurnedKilocalories,
              caloriesKilocalories.isFinite,
              caloriesKilocalories > 0 else {
            return nil
        }

        return AppLocalization.format(
            workout.isDisplayEnergyBurnedEstimated ? .estimatedBurnedCaloriesFormat : .burnedCaloriesFormat,
            caloriesKilocalories
        )
    }
}

final class RouteShareCalorieModuleView: UIView {
    static let preferredWidth: CGFloat = 88
    static let minimumPreferredHeight: CGFloat = 132

    let deleteButton = RouteShareModuleChrome.makeDeleteButton()

    private let caloriePileView = RouteShareCaloriePileView()
    private var caloriePileHeightConstraint: Constraint?
    private var currentWorkout: TrackedWorkout?
    private var selectedCalorieFoodOption: RouteShareCalorieFoodOption?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    var calorieFoodOption: RouteShareCalorieFoodOption? {
        selectedCalorieFoodOption
    }

    var preferredHeight: CGFloat {
        max(Self.minimumPreferredHeight, caloriePileView.preferredHeight)
    }

    func configure(with workout: TrackedWorkout) {
        currentWorkout = workout
        updateCaloriePile()
    }

    func updateLocalizedText(for workout: TrackedWorkout) {
        currentWorkout = workout
        updateCaloriePile()
    }

    func setCalorieFoodOption(_ option: RouteShareCalorieFoodOption?) {
        selectedCalorieFoodOption = option
        updateCaloriePile()
        setNeedsLayout()
    }

    func selectionChromeRect() -> CGRect {
        layoutIfNeeded()
        let chromeRect = caloriePileView.frame.insetBy(dx: -7, dy: -7)
        let clippedRect = chromeRect.intersection(bounds)
        return clippedRect.isNull || clippedRect.isEmpty ? bounds.insetBy(dx: 4, dy: 4) : clippedRect
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        selectionChromeRect().contains(point)
    }

    private func configureViews() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = false
        clipsToBounds = false

        addSubview(caloriePileView)

        caloriePileView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(6)
            make.centerY.equalToSuperview()
            caloriePileHeightConstraint = make.height.equalTo(Self.minimumPreferredHeight).constraint
        }
    }

    private func updateCaloriePile() {
        guard let selectedCalorieFoodOption,
              let caloriesKilocalories = currentWorkout?.displayEnergyBurnedKilocalories,
              caloriesKilocalories.isFinite,
              caloriesKilocalories > 0 else {
            caloriePileView.isHidden = true
            return
        }

        caloriePileView.configure(option: selectedCalorieFoodOption, caloriesKilocalories: caloriesKilocalories)
        caloriePileHeightConstraint?.update(offset: caloriePileView.preferredHeight)
        caloriePileView.isHidden = false
    }
}

private final class RouteShareCaloriePileView: UIView {
    private struct EmojiPileMetrics {
        let emojiSize: CGFloat
        let rowStep: CGFloat
        let columnStep: CGFloat
        let columnCount: Int
        let rowCount: Int
    }

    private static let renderedPileImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private let emojiImageView = UIImageView()
    private let countPillView = UIView()
    private let countLabel = UILabel()
    private var visibleEmojiCount = 0
    private var currentEmoji = ""
    private var currentRenderKey: NSString?
    private(set) var preferredHeight: CGFloat = 124

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(option: RouteShareCalorieFoodOption, caloriesKilocalories: Double) {
        let count = caloriesKilocalories / option.kilocalories
        currentEmoji = option.emoji
        visibleEmojiCount = roundedFoodCount(for: count)
        preferredHeight = preferredHeight(for: visibleEmojiCount)
        currentRenderKey = nil
        countLabel.text = calorieCountText(count: visibleEmojiCount, unit: option.unit)
        setNeedsLayout()
    }

    private func configureViews() {
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = false

        emojiImageView.backgroundColor = .clear
        emojiImageView.contentMode = .scaleToFill
        emojiImageView.clipsToBounds = false

        countPillView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        countPillView.layer.cornerRadius = 9
        countPillView.layer.shadowColor = UIColor.black.cgColor
        countPillView.layer.shadowOpacity = 0.16
        countPillView.layer.shadowRadius = 4
        countPillView.layer.shadowOffset = CGSize(width: 0, height: 1)

        countLabel.font = .systemFont(ofSize: 10, weight: .bold)
        countLabel.textColor = .black
        countLabel.textAlignment = .center
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.72

        addSubview(emojiImageView)
        addSubview(countPillView)
        countPillView.addSubview(countLabel)

        emojiImageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(countPillView.snp.top).offset(5)
        }

        countPillView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(3)
            make.height.equalTo(18)
            make.leading.greaterThanOrEqualToSuperview().offset(2)
            make.trailing.lessThanOrEqualToSuperview().inset(2)
        }

        countLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRenderedEmojiPileIfNeeded()
    }

    private func updateRenderedEmojiPileIfNeeded() {
        let imageSize = emojiImageView.bounds.size
        guard visibleEmojiCount > 0,
              !currentEmoji.isEmpty,
              imageSize.width > 0,
              imageSize.height > 0 else {
            emojiImageView.image = nil
            currentRenderKey = nil
            return
        }

        let screenScale = window?.screen.scale ?? UIScreen.main.scale
        let pixelWidth = Int(round(imageSize.width * screenScale))
        let pixelHeight = Int(round(imageSize.height * screenScale))
        let renderKey = NSString(
            string: "\(currentEmoji)|\(visibleEmojiCount)|\(pixelWidth)x\(pixelHeight)|\(Int(screenScale * 100))"
        )
        guard renderKey != currentRenderKey else {
            return
        }

        if let cachedImage = Self.renderedPileImageCache.object(forKey: renderKey) {
            emojiImageView.image = cachedImage
            currentRenderKey = renderKey
            return
        }

        let image = renderEmojiPileImage(
            emoji: currentEmoji,
            count: visibleEmojiCount,
            size: imageSize,
            screenScale: screenScale
        )
        let cost = max(pixelWidth * pixelHeight * 4, 1)
        Self.renderedPileImageCache.setObject(image, forKey: renderKey, cost: cost)
        emojiImageView.image = image
        currentRenderKey = renderKey
    }

    private func renderEmojiPileImage(
        emoji: String,
        count: Int,
        size: CGSize,
        screenScale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        format.opaque = false
        let metrics = emojiPileMetrics(for: count, in: size)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let emojiText = NSString(string: emoji)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.emojiSize),
            .paragraphStyle: paragraphStyle
        ]
        let pileHeight = metrics.emojiSize + CGFloat(max(metrics.rowCount - 1, 0)) * metrics.rowStep
        let pileWidth = metrics.emojiSize + CGFloat(max(metrics.columnCount - 1, 0)) * metrics.columnStep
        let startY = (size.height - pileHeight) / 2
        let startX = (size.width - pileWidth) / 2 + metrics.emojiSize / 2

        return renderer.image { context in
            let cgContext = context.cgContext
            for index in 0..<count {
                let column = index % metrics.columnCount
                let row = index / metrics.columnCount
                let xJitter = deterministicOffset(index: index, multiplier: 37, modulus: 19) * metrics.emojiSize * 0.16
                let yJitter = deterministicOffset(index: index, multiplier: 23, modulus: 13) * metrics.emojiSize * 0.08
                let staggerY = CGFloat(column % 2) * metrics.rowStep * 0.42
                let center = CGPoint(
                    x: startX + CGFloat(column) * metrics.columnStep + xJitter,
                    y: startY + CGFloat(row) * metrics.rowStep + staggerY + yJitter + metrics.emojiSize / 2
                )
                let rotation = deterministicOffset(index: index, multiplier: 31, modulus: 25) * .pi / 9
                let emojiScale = 0.94 + deterministicPositiveOffset(index: index, multiplier: 17, modulus: 7) * 0.025
                let drawSize = metrics.emojiSize * 1.18

                cgContext.saveGState()
                cgContext.translateBy(x: center.x, y: center.y)
                cgContext.rotate(by: rotation)
                cgContext.scaleBy(x: emojiScale, y: emojiScale)
                cgContext.setShadow(
                    offset: CGSize(width: 0, height: max(metrics.emojiSize * 0.04, 0.35)),
                    blur: max(metrics.emojiSize * 0.1, 0.8),
                    color: UIColor.black.withAlphaComponent(0.18).cgColor
                )
                emojiText.draw(
                    in: CGRect(x: -drawSize / 2, y: -drawSize / 2, width: drawSize, height: drawSize),
                    withAttributes: attributes
                )
                cgContext.restoreGState()
            }
        }
    }

    private func emojiPileMetrics(for count: Int, in size: CGSize) -> EmojiPileMetrics {
        let emojiSize = emojiSize(for: count)
        let rowStep = emojiSize * 0.44
        let columnStep = emojiSize * 0.58
        let maxColumns = max(Int(floor((size.width - emojiSize) / columnStep)) + 1, 1)
        let columnCount = min(preferredColumnCount(for: count), maxColumns)
        let rowCount = Int(ceil(Double(count) / Double(columnCount)))
        return EmojiPileMetrics(
            emojiSize: emojiSize,
            rowStep: rowStep,
            columnStep: columnStep,
            columnCount: columnCount,
            rowCount: rowCount
        )
    }

    private func preferredHeight(for count: Int) -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : 76
        let metrics = emojiPileMetrics(for: count, in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let pileHeight = metrics.emojiSize + CGFloat(max(metrics.rowCount - 1, 0)) * metrics.rowStep
        return max(124, ceil(pileHeight + 28))
    }

    private func roundedFoodCount(for count: Double) -> Int {
        max(Int(count.rounded()), 1)
    }

    private func preferredColumnCount(for count: Int) -> Int {
        switch count {
        case 1...3:
            return 1
        case 4...10:
            return 2
        case 11...30:
            return 3
        case 31...80:
            return 4
        case 81...160:
            return 5
        case 161...320:
            return 6
        default:
            return max(6, Int(ceil(sqrt(Double(count) / 2.0))))
        }
    }

    private func emojiSize(for count: Int) -> CGFloat {
        switch count {
        case 1...14:
            return 28
        case 15...50:
            return 25
        case 51...120:
            return 22
        case 121...240:
            return 19
        case 241...500:
            return 16
        default:
            return 13
        }
    }

    private func deterministicOffset(index: Int, multiplier: Int, modulus: Int) -> CGFloat {
        let centeredValue = (index * multiplier) % modulus - modulus / 2
        return CGFloat(centeredValue) / CGFloat(max(modulus / 2, 1))
    }

    private func deterministicPositiveOffset(index: Int, multiplier: Int, modulus: Int) -> CGFloat {
        CGFloat((index * multiplier) % modulus) / CGFloat(max(modulus - 1, 1))
    }

    private func calorieCountText(count: Int, unit: String) -> String {
        "≈\(count)\(unit)"
    }
}
