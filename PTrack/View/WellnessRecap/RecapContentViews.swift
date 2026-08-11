//
//  RecapContentViews.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  指导页的非文本内容块:柱状趋势图与指标对比表。纯 CoreGraphics/UIKit,无依赖。

import SnapKit
import UIKit

// MARK: - Bar Chart

final class RecapBarChartView: UIView {
    private enum Metrics {
        static let chartHeight: CGFloat = 156
        static let topPadding: CGFloat = 34
        static let bottomPadding: CGFloat = 20
        static let barSpacingRatio: CGFloat = 0.35
    }

    private var data: RecapChartData?
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
        }
        snp.makeConstraints { make in
            make.height.equalTo(Metrics.chartHeight)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: RecapBarChartView, _) in
            view.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with data: RecapChartData) {
        self.data = data
        titleLabel.text = data.title
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let data, !data.points.isEmpty, let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let plotRect = CGRect(
            x: 0,
            y: Metrics.topPadding,
            width: bounds.width,
            height: bounds.height - Metrics.topPadding - Metrics.bottomPadding
        )
        let values = data.points.compactMap(\.value)
        guard !values.isEmpty else {
            return
        }
        var maxValue = max(values.max() ?? 1, data.baseline ?? 0)
        maxValue = maxValue <= 0 ? 1 : maxValue * 1.12

        let slotWidth = plotRect.width / CGFloat(data.points.count)
        let barWidth = max(2, slotWidth * (1 - Metrics.barSpacingRatio))

        // 柱体。
        for (index, point) in data.points.enumerated() {
            guard let value = point.value else {
                continue
            }
            let height = max(2, plotRect.height * CGFloat(value / maxValue))
            let barRect = CGRect(
                x: plotRect.minX + CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2,
                y: plotRect.maxY - height,
                width: barWidth,
                height: height
            )
            let path = UIBezierPath(
                roundedRect: barRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: min(3, barWidth / 2), height: min(3, barWidth / 2))
            )
            AppColors.movinnGreen.withAlphaComponent(0.85).setFill()
            path.fill()
        }

        // 基线虚线 + 数值。
        if let baseline = data.baseline, baseline > 0, baseline <= maxValue {
            let y = plotRect.maxY - plotRect.height * CGFloat(baseline / maxValue)
            context.saveGState()
            context.setStrokeColor(UIColor.secondaryLabel.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.move(to: CGPoint(x: plotRect.minX, y: y))
            context.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.strokePath()
            context.restoreGState()

            let baselineText = Self.compactNumber(baseline) as NSString
            baselineText.draw(
                at: CGPoint(x: plotRect.maxX - baselineText.size(withAttributes: Self.axisAttributes).width, y: y - 14),
                withAttributes: Self.axisAttributes
            )
        }

        // 峰值标注。
        if let maxPointValue = values.max() {
            let peakText = Self.compactNumber(maxPointValue) as NSString
            peakText.draw(at: CGPoint(x: plotRect.minX, y: Metrics.topPadding - 16), withAttributes: Self.axisAttributes)
        }

        // 稀疏 x 轴标签:首、中、尾。
        let labelIndices: [Int] = data.points.count <= 3
            ? Array(data.points.indices)
            : [0, data.points.count / 2, data.points.count - 1]
        for index in labelIndices {
            let text = data.points[index].label as NSString
            let size = text.size(withAttributes: Self.axisAttributes)
            var x = plotRect.minX + CGFloat(index) * slotWidth + (slotWidth - size.width) / 2
            x = min(max(x, 0), bounds.width - size.width)
            text.draw(at: CGPoint(x: x, y: plotRect.maxY + 4), withAttributes: Self.axisAttributes)
        }
    }

    private static let axisAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: UIColor.tertiaryLabel
    ]

    private static func compactNumber(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "%.1fw", value / 10000)
        }
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return String(Int(value.rounded()))
    }
}

// MARK: - Metric Table

final class RecapMetricTableView: UIView {
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stackView.axis = .vertical
        stackView.spacing = 0
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with rows: [RecapMetricRow]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        stackView.addArrangedSubview(makeRow(
            name: AppLocalization.text(.wellnessTableHeaderMetric),
            current: AppLocalization.text(.wellnessTableHeaderCurrent),
            reference: AppLocalization.text(.wellnessTableHeaderReference),
            delta: AppLocalization.text(.wellnessTableHeaderChange),
            deltaColor: .tertiaryLabel,
            isHeader: true
        ))

        for row in rows {
            let separator = UIView()
            separator.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
            stackView.addArrangedSubview(separator)
            separator.snp.makeConstraints { make in
                make.height.equalTo(1.0 / traitCollection.displayScale)
            }
            let deltaColor: UIColor
            switch row.deltaDirection {
            case 1: deltaColor = AppColors.movinnGreen
            case -1: deltaColor = .systemOrange
            default: deltaColor = .secondaryLabel
            }
            stackView.addArrangedSubview(makeRow(
                name: row.name,
                current: row.current,
                reference: row.reference,
                delta: row.delta,
                deltaColor: deltaColor,
                isHeader: false
            ))
        }
    }

    private func makeRow(
        name: String,
        current: String,
        reference: String,
        delta: String,
        deltaColor: UIColor,
        isHeader: Bool
    ) -> UIView {
        let container = UIView()
        let nameLabel = UILabel()
        let currentLabel = UILabel()
        let referenceLabel = UILabel()
        let deltaLabel = UILabel()

        let font: UIFont = isHeader
            ? .systemFont(ofSize: 11, weight: .semibold)
            : .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        nameLabel.font = isHeader ? font : .systemFont(ofSize: 14, weight: .regular)
        nameLabel.textColor = isHeader ? .tertiaryLabel : .label
        [currentLabel, referenceLabel, deltaLabel].forEach { label in
            label.font = font
            label.textAlignment = .right
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
        }
        currentLabel.textColor = isHeader ? .tertiaryLabel : .label
        referenceLabel.textColor = isHeader ? .tertiaryLabel : .secondaryLabel
        deltaLabel.textColor = deltaColor

        nameLabel.text = name
        currentLabel.text = current
        referenceLabel.text = reference
        deltaLabel.text = delta

        [nameLabel, currentLabel, referenceLabel, deltaLabel].forEach(container.addSubview)
        nameLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.greaterThanOrEqualTo(60)
        }
        deltaLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.equalTo(52)
        }
        referenceLabel.snp.makeConstraints { make in
            make.trailing.equalTo(deltaLabel.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
            make.width.equalTo(72)
        }
        currentLabel.snp.makeConstraints { make in
            make.trailing.equalTo(referenceLabel.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
            make.width.equalTo(72)
            make.leading.greaterThanOrEqualTo(nameLabel.snp.trailing).offset(8)
        }
        container.snp.makeConstraints { make in
            make.height.equalTo(isHeader ? 32 : 44)
        }
        return container
    }
}

// MARK: - Typewriter Label

/// 打字机文本块:完整文本先以透明色排版(布局稳定),按合成字符逐步恢复真实颜色。
/// CADisplayLink 会强引用 target,直接用 self 会导致标签无法释放。
private final class DisplayLinkProxy {
    weak var target: RecapTypewriterLabel?

    init(target: RecapTypewriterLabel) {
        self.target = target
    }

    @objc func handle(_ link: CADisplayLink) {
        guard let target else {
            link.invalidate()
            return
        }
        target.handleDisplayLink(link)
    }
}

final class RecapTypewriterLabel: UILabel {
    private var fullText: NSAttributedString?
    private var boundaries: [Int] = []
    private var revealedIndex = 0
    private var pending: Double = 0
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var onFinished: (() -> Void)?

    var isAnimating: Bool {
        displayLink != nil
    }

    func setContent(_ attributedText: NSAttributedString, hidden: Bool) {
        numberOfLines = 0
        fullText = attributedText
        boundaries = []
        revealedIndex = 0
        if hidden {
            let string = attributedText.string as NSString
            var location = 0
            while location < string.length {
                let range = string.rangeOfComposedCharacterSequence(at: location)
                location = range.location + range.length
                boundaries.append(location)
            }
            self.attributedText = maskedText(revealUpTo: 0)
        } else {
            self.attributedText = attributedText
        }
    }

    func startReveal(charactersPerSecond: Double, onFinished: @escaping () -> Void) {
        // 重入保护:上一条动画未结束就再次调用会留下野链接。
        displayLink?.invalidate()
        displayLink = nil
        guard fullText != nil, !boundaries.isEmpty else {
            onFinished()
            return
        }
        self.onFinished = onFinished
        pending = 0
        revealSpeed = charactersPerSecond
        let proxy = DisplayLinkProxy(target: self)
        displayLinkProxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handle(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit {
        displayLink?.invalidate()
    }

    private var revealSpeed: Double = 45

    func finishReveal() {
        guard let fullText else {
            return
        }
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        revealedIndex = boundaries.count
        attributedText = fullText
        let finished = onFinished
        onFinished = nil
        finished?()
    }

    fileprivate func handleDisplayLink(_ link: CADisplayLink) {
        pending += revealSpeed * link.duration
        let step = Int(pending)
        guard step > 0 else {
            return
        }
        pending -= Double(step)
        revealedIndex = min(revealedIndex + step, boundaries.count)
        if revealedIndex >= boundaries.count {
            finishReveal()
        } else {
            attributedText = maskedText(revealUpTo: revealedIndex)
        }
    }

    private func maskedText(revealUpTo index: Int) -> NSAttributedString? {
        guard let fullText else {
            return nil
        }
        let masked = NSMutableAttributedString(attributedString: fullText)
        let fromLocation = index == 0 ? 0 : boundaries[index - 1]
        if fromLocation < masked.length {
            masked.addAttribute(
                .foregroundColor,
                value: UIColor.clear,
                range: NSRange(location: fromLocation, length: masked.length - fromLocation)
            )
        }
        return masked
    }
}
