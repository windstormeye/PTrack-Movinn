//
//  WellnessRecapViewController.swift
//  PTrack
//
//  Created by Codex on 2026/8/11.
//
//  首页 title 点击弹出的「指导建议」半屏页:
//  - 顶部固定标题 + 时间范围选择(3 天 / 一周 / 一月 / 半年 / 一年);
//  - 内容为块结构:文本块打字机逐字揭示,图表/表格淡入,从上到下顺序播放;
//  - 点击任意处跳过动画;同一"范围 × 周期"只播一次;减弱动态效果时直接全显。

import SnapKit
import UIKit

final class WellnessRecapViewController: UIViewController {
    private enum Metrics {
        static let contentInset: CGFloat = 20
        static let blockSpacing: CGFloat = 12
        /// 段落标题前的呼吸空间,用于区分内容区块。
        static let sectionTopSpacing: CGFloat = 26
        static let cardPadding: CGFloat = 14
        static let charactersPerSecond: Double = 45
    }

    private enum AnimationStep {
        case typewriter(RecapTypewriterLabel)
        case fade(UIView)
    }

    private let titleLabel = UILabel()
    private let rangeControl = UISegmentedControl()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let authorizeButton = UIButton(type: .system)
    private let disclaimerLabel = UILabel()

    private var selectedRange: WellnessRecapRange = WellnessRecapStore.defaultRange
    private var animationQueue: [AnimationStep] = []
    private var isPlayingAnimation = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // 页面底色用淡灰,内容模块用白/黑,靠明度差建立层级。
        view.backgroundColor = AppColors.groupedCardBackground
        configureViews()
        loadContent(for: selectedRange)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        skipAnimation()
    }

    // MARK: - Setup

    private func configureViews() {
        titleLabel.text = AppLocalization.text(.wellnessRecapSheetTitle)
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        view.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.equalToSuperview().offset(Metrics.contentInset)
        }

        for (index, range) in WellnessRecapRange.allCases.enumerated() {
            rangeControl.insertSegment(withTitle: AppLocalization.text(range.titleKey), at: index, animated: false)
        }
        rangeControl.selectedSegmentIndex = WellnessRecapRange.allCases.firstIndex(of: selectedRange) ?? 0
        rangeControl.addTarget(self, action: #selector(handleRangeChanged), for: .valueChanged)
        rangeControl.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
        view.addSubview(rangeControl)
        rangeControl.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(Metrics.contentInset)
        }

        // 免责声明吸底居中,不随内容滚动。
        disclaimerLabel.text = AppLocalization.text(.wellnessDisclaimer)
        disclaimerLabel.font = .systemFont(ofSize: 11)
        disclaimerLabel.textColor = .tertiaryLabel
        disclaimerLabel.textAlignment = .center
        disclaimerLabel.numberOfLines = 0
        view.addSubview(disclaimerLabel)
        disclaimerLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Metrics.contentInset)
            // 不跟随安全区,否则底部会空出一大块。
            make.bottom.equalToSuperview().inset(12)
        }

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(rangeControl.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(disclaimerLabel.snp.top).offset(-8)
        }

        contentStack.axis = .vertical
        contentStack.spacing = Metrics.blockSpacing
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalTo(view).inset(Metrics.contentInset)
            make.bottom.equalToSuperview().inset(Metrics.contentInset * 2)
        }

        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(rangeControl.snp.bottom).offset(80)
        }

        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = AppLocalization.text(.wellnessAuthButton)
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        authorizeButton.configuration = configuration
        authorizeButton.tintColor = AppColors.movinnGreen
        authorizeButton.isHidden = true
        authorizeButton.addTarget(self, action: #selector(handleAuthorizeTap), for: .touchUpInside)
        view.addSubview(authorizeButton)
        authorizeButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(28)
        }

        let skipTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleContentTap))
        // 不要吞掉分段控件和授权按钮的点击。
        skipTapGesture.cancelsTouchesInView = false
        skipTapGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(skipTapGesture)
    }

    // MARK: - Content Flow

    @objc private func handleRangeChanged() {
        let index = rangeControl.selectedSegmentIndex
        guard WellnessRecapRange.allCases.indices.contains(index) else {
            return
        }
        skipAnimation()
        selectedRange = WellnessRecapRange.allCases[index]
        loadContent(for: selectedRange)
    }

    private func loadContent(for range: WellnessRecapRange) {
        let store = WellnessRecapStore.shared

        guard store.isHealthDataAvailable else {
            render(blocks: [.paragraph(AppLocalization.text(.wellnessEmptyBody))], animated: false)
            return
        }

        guard store.hasRequestedAuthorization else {
            render(
                blocks: [
                    .heading(AppLocalization.text(.wellnessAuthPromptTitle)),
                    .paragraph(AppLocalization.text(.wellnessAuthPromptBody))
                ],
                animated: false
            )
            authorizeButton.isHidden = false
            return
        }

        // 缓存只用于"秒开",随后一定会用最新数据重算;内容有变化就静默换掉。
        let cached = store.cachedReport(for: range)
        if let cached {
            show(report: cached)
        } else {
            clearContent()
            loadingIndicator.startAnimating()
        }

        store.generate(range: range) { [weak self] report in
            guard let self, selectedRange == range else {
                return
            }
            loadingIndicator.stopAnimating()
            guard let report else {
                if cached == nil {
                    render(blocks: [.paragraph(AppLocalization.text(.wellnessEmptyBody))], animated: false)
                }
                return
            }
            if let cached, store.isSameContent(cached, report) {
                // 内容没变,保留当前(可能正在播放的)界面。
                return
            }
            show(report: report)
        }
    }

    @objc private func handleAuthorizeTap() {
        authorizeButton.isHidden = true
        clearContent()
        loadingIndicator.startAnimating()
        let range = selectedRange
        WellnessRecapStore.shared.requestAuthorizationAndGenerate(range: range) { [weak self] report in
            guard let self else {
                return
            }
            loadingIndicator.stopAnimating()
            if let report {
                show(report: report)
            } else {
                render(blocks: [.paragraph(AppLocalization.text(.wellnessEmptyBody))], animated: false)
            }
        }
    }

    private func show(report: WellnessRecapReport) {
        let store = WellnessRecapStore.shared
        let shouldAnimate = !store.hasAnimated(periodID: report.periodID, range: report.range)
            && !UIAccessibility.isReduceMotionEnabled
        render(blocks: report.blocks, animated: shouldAnimate)
        if shouldAnimate {
            store.markAnimated(periodID: report.periodID, range: report.range)
        }
    }

    @objc private func handleContentTap() {
        if isPlayingAnimation {
            skipAnimation()
        }
    }

    // MARK: - Rendering

    private func clearContent() {
        skipAnimation()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func render(blocks: [RecapBlock], animated: Bool) {
        clearContent()
        var steps: [AnimationStep] = []

        var previousView: UIView?

        func add(_ blockView: UIView, topSpacing: CGFloat?) {
            if let topSpacing, let previousView {
                contentStack.setCustomSpacing(topSpacing, after: previousView)
            }
            contentStack.addArrangedSubview(blockView)
            previousView = blockView
        }

        // 连续的建议合并进同一张卡片,块之间用细线分隔。
        var adviceCardStack: UIStackView?

        func adviceCard() -> UIStackView {
            if let adviceCardStack {
                return adviceCardStack
            }
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 0
            let card = makeSurfaceCard(containing: stack)
            add(card, topSpacing: nil)
            adviceCardStack = stack
            return stack
        }

        for (index, block) in blocks.enumerated() {
            if case .advice = block {} else {
                adviceCardStack = nil
            }
            switch block {
            case .heading(let text):
                let label = makeTypewriterLabel(
                    attributed(
                        text.uppercased(with: Locale.current),
                        font: .systemFont(ofSize: 13, weight: .heavy),
                        color: .secondaryLabel,
                        kern: 0.8
                    ),
                    hidden: animated
                )
                add(label, topSpacing: index == 0 ? nil : Metrics.sectionTopSpacing)
                contentStack.setCustomSpacing(10, after: label)
                steps.append(.typewriter(label))
            case .paragraph(let text):
                // 首个段落是总结,给更重的字重与更大字号。
                let isSummary = index == 0
                let label = makeTypewriterLabel(
                    attributed(
                        text,
                        font: .systemFont(ofSize: isSummary ? 17 : 15, weight: isSummary ? .semibold : .regular),
                        color: .label,
                        lineSpacing: isSummary ? 4 : 5
                    ),
                    hidden: animated
                )
                add(label, topSpacing: nil)
                steps.append(.typewriter(label))
            case .metricTable(let rows):
                let table = RecapMetricTableView()
                table.configure(with: rows)
                let card = makeSurfaceCard(containing: table)
                add(card, topSpacing: nil)
                if animated {
                    card.alpha = 0
                }
                steps.append(.fade(card))
            case .chart(let data):
                let chart = RecapBarChartView()
                chart.configure(with: data)
                let card = makeSurfaceCard(containing: chart)
                add(card, topSpacing: 8)
                if animated {
                    card.alpha = 0
                }
                steps.append(.fade(card))
            case .advice(let advice):
                let label = makeTypewriterLabel(makeAdviceText(advice), hidden: animated)
                let isFirstAdvice = !(index > 0 && isAdviceBlock(blocks[index - 1]))
                let row = makeAdviceRow(containing: label, showsSeparator: !isFirstAdvice)
                adviceCard().addArrangedSubview(row)
                steps.append(.typewriter(label))
            case .footnote(let text):
                let label = makeTypewriterLabel(
                    attributed(text, font: .systemFont(ofSize: 12), color: .tertiaryLabel, lineSpacing: 4),
                    hidden: animated
                )
                add(label, topSpacing: Metrics.sectionTopSpacing - 8)
                steps.append(.typewriter(label))
            }
        }

        guard animated else {
            return
        }
        animationQueue = steps
        isPlayingAnimation = true
        playNextStep()
    }

    private func playNextStep() {
        guard isPlayingAnimation else {
            return
        }
        guard !animationQueue.isEmpty else {
            isPlayingAnimation = false
            return
        }
        let step = animationQueue.removeFirst()
        switch step {
        case .typewriter(let label):
            // 建议在卡片内嵌套多层,滚动定位到 contentStack 的直接子视图。
            var target: UIView = label
            while let parent = target.superview, !contentStack.arrangedSubviews.contains(target) {
                if parent === contentStack {
                    break
                }
                target = parent
            }
            scrollToVisible(target)
            label.startReveal(charactersPerSecond: Metrics.charactersPerSecond) { [weak self] in
                self?.playNextStep()
            }
        case .fade(let blockView):
            scrollToVisible(blockView)
            UIView.animate(
                withDuration: 0.32,
                animations: {
                    blockView.alpha = 1
                },
                completion: { [weak self] _ in
                    self?.playNextStep()
                }
            )
        }
    }

    private func skipAnimation() {
        guard isPlayingAnimation || !animationQueue.isEmpty else {
            return
        }
        isPlayingAnimation = false
        for step in animationQueue {
            switch step {
            case .typewriter(let label):
                label.finishReveal()
            case .fade(let blockView):
                blockView.alpha = 1
            }
        }
        animationQueue = []
        // 兜底:把仍在播放的文本块直接补全(建议卡内的标签也要覆盖)。
        finishTypewriterLabels(in: contentStack)
    }

    private func finishTypewriterLabels(in container: UIView) {
        for subview in container.subviews {
            if let label = subview as? RecapTypewriterLabel {
                if label.isAnimating {
                    label.finishReveal()
                }
            } else {
                finishTypewriterLabels(in: subview)
            }
        }
    }

    private func scrollToVisible(_ blockView: UIView) {
        let frame = contentStack.convert(blockView.frame, to: scrollView)
        scrollView.scrollRectToVisible(frame.insetBy(dx: 0, dy: -30), animated: true)
    }

    // MARK: - Text Building

    private func isAdviceBlock(_ block: RecapBlock) -> Bool {
        if case .advice = block {
            return true
        }
        return false
    }

    private func makeTypewriterLabel(_ text: NSAttributedString, hidden: Bool) -> RecapTypewriterLabel {
        let label = RecapTypewriterLabel()
        label.setContent(text, hidden: hidden)
        return label
    }

    /// 内容模块的承载面:白/黑底,与页面的淡灰底形成层级。
    private func makeSurfaceCard(containing contentView: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.solidBackground
        card.layer.cornerRadius = 14
        card.layer.masksToBounds = true
        card.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Metrics.cardPadding)
        }
        return card
    }

    /// 卡片内的单条建议,与上一条之间用细线分隔。
    private func makeAdviceRow(containing contentView: UIView, showsSeparator: Bool) -> UIView {
        let container = UIView()
        container.addSubview(contentView)

        if showsSeparator {
            let separator = UIView()
            separator.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
            container.addSubview(separator)
            separator.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(16)
                make.leading.trailing.equalToSuperview()
                make.height.equalTo(1.0 / view.traitCollection.displayScale)
            }
            contentView.snp.makeConstraints { make in
                make.top.equalTo(separator.snp.bottom).offset(16)
                make.leading.trailing.bottom.equalToSuperview()
            }
        } else {
            contentView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        return container
    }

    private func makeAdviceText(_ advice: RecapAdvice) -> NSAttributedString {
        let builder = NSMutableAttributedString()
        // 依据在最上方,小字次要色,像新闻的导语行。
        builder.append(attributed(
            advice.evidence.uppercased(with: Locale.current) + "\n",
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: advice.category == .risk ? .systemOrange : .tertiaryLabel,
            lineSpacing: 1,
            paragraphSpacing: 5,
            kern: 0.4
        ))
        builder.append(attributed(
            advice.title + "\n",
            font: .systemFont(ofSize: 19, weight: .bold),
            color: .label,
            lineSpacing: 2,
            paragraphSpacing: 6
        ))
        builder.append(attributed(
            advice.body,
            font: .systemFont(ofSize: 15),
            color: .secondaryLabel,
            lineSpacing: 6
        ))

        // 附带的知识点:品牌色小圆点起头,与正文区分,不再用"顺带一提"这类模板前缀。
        if let tip = advice.tip, !tip.isEmpty {
            builder.append(attributed(
                "\n",
                font: .systemFont(ofSize: 6),
                color: .clear
            ))
            let bulletStyle = NSMutableParagraphStyle()
            bulletStyle.lineSpacing = 5
            bulletStyle.headIndent = 20
            bulletStyle.firstLineHeadIndent = 0
            builder.append(NSAttributedString(
                string: "●",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 8, weight: .black),
                    .foregroundColor: AppColors.movinnGreen,
                    .baselineOffset: 3,
                    .kern: 10,
                    .paragraphStyle: bulletStyle
                ]
            ))
            builder.append(NSAttributedString(
                string: tip,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: UIColor.tertiaryLabel,
                    .paragraphStyle: bulletStyle
                ]
            ))
        }
        return builder
    }

    /// 中日韩文本用两端对齐,并放开默认的整词推移策略,
    /// 否则 "15 分钟" 这类数字+汉字的组合会被整体推到下一行,右边缘参差不齐。
    private var usesJustifiedText: Bool {
        switch AppLanguageStore.shared.language {
        case .chinese, .japanese, .korean:
            return true
        default:
            return false
        }
    }

    private func attributed(
        _ text: String,
        font: UIFont,
        color: UIColor,
        lineSpacing: CGFloat = 0,
        paragraphSpacing: CGFloat = 0,
        kern: CGFloat = 0
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        if usesJustifiedText {
            paragraphStyle.alignment = .justified
            paragraphStyle.lineBreakStrategy = []
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        if kern != 0 {
            attributes[.kern] = kern
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}

// MARK: - Presentation Helper

extension WellnessRecapViewController {
    /// 以半屏 sheet 形式弹出;内容超出半屏可上滑到全屏。
    static func present(from presenter: UIViewController) {
        let controller = WellnessRecapViewController()
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        presenter.present(controller, animated: true)
    }
}
