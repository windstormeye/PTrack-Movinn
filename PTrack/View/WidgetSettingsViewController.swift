//
//  WidgetSettingsViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import SnapKit
import UIKit

final class WidgetSettingsViewController: UIViewController {
    fileprivate enum SupportedWidget: CaseIterable {
        case weeklyProgress
        case weeklyChart
        case monthlyCalendar
        case annualTrajectory
        case worldMap
        case chinaMap

        var titleKey: AppTextKey {
            switch self {
            case .weeklyProgress:
                return .widgetSmallWeeklyGoal
            case .weeklyChart:
                return .widgetWeeklyChart
            case .monthlyCalendar:
                return .widgetMonthlyCalendar
            case .annualTrajectory:
                return .widgetAnnualTrajectory
            case .worldMap:
                return .widgetWorldMap
            case .chinaMap:
                return .widgetChinaMap
            }
        }

        var familyText: String {
            switch self {
            case .weeklyProgress:
                return "Small"
            case .weeklyChart, .annualTrajectory, .worldMap, .chinaMap:
                return "Medium"
            case .monthlyCalendar:
                return "Large"
            }
        }
    }

    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewScrollView = UIScrollView()
    private let previewStackView = UIStackView()
    private let goalCardView = UIView()
    private let goalTitleLabel = UILabel()
    private let goalTextField = UITextField()
    private let goalUnitLabel = UILabel()
    private let goalStepper = UIStepper()
    private let navigationBackgroundHeight: CGFloat = 124

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureViews()
        registerLanguageObserver()
        registerTraitChangeHandler()
        updateLocalizedText()
        updateGoalControls()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
        updateGoalControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewScrollView.contentInset.right = 16
    }

    private func configureNavigationItem() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = [.top, .bottom]
    }

    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.barStyle = .default
        navigationController?.navigationBar.tintColor = .label
    }

    private func configureViews() {
        navigationBackgroundView.isUserInteractionEnabled = false
        navigationBackgroundView.effect = nil
        navigationBackgroundView.contentView.backgroundColor = .clear

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInset = UIEdgeInsets(top: navigationBackgroundHeight, left: 0, bottom: 28, right: 0)
        scrollView.scrollIndicatorInsets = scrollView.contentInset

        previewScrollView.alwaysBounceHorizontal = true
        previewScrollView.showsHorizontalScrollIndicator = false
        previewScrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        previewStackView.axis = .horizontal
        previewStackView.alignment = .fill
        previewStackView.spacing = 12

        goalCardView.backgroundColor = AppColors.groupedCardBackground
        goalCardView.layer.cornerRadius = 8
        goalCardView.layer.masksToBounds = true

        goalTitleLabel.textColor = AppColors.solidForeground
        goalTitleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        goalTitleLabel.adjustsFontSizeToFitWidth = true
        goalTitleLabel.minimumScaleFactor = 0.74

        goalTextField.textColor = AppColors.solidForeground
        goalTextField.tintColor = AppColors.movinnGreen
        goalTextField.font = .systemFont(ofSize: 28, weight: .bold)
        goalTextField.keyboardType = .decimalPad
        goalTextField.textAlignment = .right
        goalTextField.adjustsFontSizeToFitWidth = true
        goalTextField.minimumFontSize = 14
        goalTextField.delegate = self
        goalTextField.addTarget(self, action: #selector(handleGoalTextFieldEditingChanged), for: .editingChanged)

        goalUnitLabel.textColor = AppColors.foreground(alpha: 0.52)
        goalUnitLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        goalStepper.minimumValue = 1
        goalStepper.maximumValue = 9_999
        goalStepper.stepValue = 10
        goalStepper.addTarget(self, action: #selector(handleGoalStepperValueChanged), for: .valueChanged)

        view.addSubview(scrollView)
        view.addSubview(navigationBackgroundView)
        scrollView.addSubview(contentView)
        contentView.addSubview(previewScrollView)
        previewScrollView.addSubview(previewStackView)
        contentView.addSubview(goalCardView)
        goalCardView.addSubview(goalTitleLabel)
        goalCardView.addSubview(goalTextField)
        goalCardView.addSubview(goalUnitLabel)
        goalCardView.addSubview(goalStepper)

        for widget in SupportedWidget.allCases {
            let cardView = WidgetPreviewCardView()
            cardView.configure(
                widget: widget,
                title: AppLocalization.text(widget.titleKey),
                familyText: widget.familyText
            )
            previewStackView.addArrangedSubview(cardView)
            cardView.snp.makeConstraints { make in
                make.width.equalTo(176)
                make.height.equalTo(198)
            }
        }

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        previewScrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(2)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(210)
        }

        previewStackView.snp.makeConstraints { make in
            make.edges.equalTo(previewScrollView.contentLayoutGuide)
            make.height.equalTo(previewScrollView.frameLayoutGuide)
        }

        goalCardView.snp.makeConstraints { make in
            make.top.equalTo(previewScrollView.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(96)
            make.bottom.equalToSuperview()
        }

        goalTitleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(goalStepper.snp.leading).offset(-12)
        }

        goalStepper.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(goalTitleLabel)
        }

        goalUnitLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.bottom.equalToSuperview().inset(16)
            make.width.equalTo(34)
        }

        goalTextField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalTo(goalUnitLabel.snp.leading).offset(-8)
            make.bottom.equalToSuperview().inset(8)
            make.height.equalTo(40)
        }
    }

    private func registerLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateAppearanceColors()
        }
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.widgets)
        goalTitleLabel.text = AppLocalization.text(.widgetWeeklyGoalDistance)
        goalUnitLabel.text = AppLocalization.text(.kilometers)

        for (index, cardView) in previewStackView.arrangedSubviews.enumerated() {
            guard let cardView = cardView as? WidgetPreviewCardView,
                  SupportedWidget.allCases.indices.contains(index) else {
                continue
            }

            let widget = SupportedWidget.allCases[index]
            cardView.configure(
                widget: widget,
                title: AppLocalization.text(widget.titleKey),
                familyText: widget.familyText
            )
        }
    }

    private func updateAppearanceColors() {
        goalCardView.backgroundColor = AppColors.groupedCardBackground
        goalTitleLabel.textColor = AppColors.solidForeground
        goalTextField.textColor = AppColors.solidForeground
        goalTextField.tintColor = AppColors.movinnGreen
        goalUnitLabel.textColor = AppColors.foreground(alpha: 0.52)
        previewStackView.arrangedSubviews.forEach { view in
            (view as? WidgetPreviewCardView)?.setNeedsDisplay()
        }
    }

    private func updateGoalControls() {
        let kilometers = PTrackWidgetSettingsStore.weeklyGoalDistanceKilometers
        goalStepper.value = kilometers
        goalTextField.text = formattedGoalText(kilometers)
    }

    private func formattedGoalText(_ kilometers: Double) -> String {
        if kilometers.rounded() == kilometers {
            return "\(Int(kilometers))"
        }

        return String(format: "%.1f", kilometers)
    }

    @objc private func handleGoalStepperValueChanged() {
        PTrackWidgetSettingsStore.setWeeklyGoalDistanceKilometers(goalStepper.value)
        goalTextField.text = formattedGoalText(goalStepper.value)
    }

    @objc private func handleGoalTextFieldEditingChanged() {
        guard let kilometers = parsedGoalKilometers() else {
            return
        }

        goalStepper.value = min(max(kilometers, goalStepper.minimumValue), goalStepper.maximumValue)
    }

    private func parsedGoalKilometers() -> Double? {
        let text = goalTextField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".") ?? ""
        guard let value = Double(text), value > 0 else {
            return nil
        }

        return value
    }

    private func commitGoalTextFieldValue() {
        guard let kilometers = parsedGoalKilometers() else {
            updateGoalControls()
            return
        }

        PTrackWidgetSettingsStore.setWeeklyGoalDistanceKilometers(kilometers)
        updateGoalControls()
    }
}

extension WidgetSettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        commitGoalTextFieldValue()
    }
}

private final class WidgetPreviewCardView: UIView {
    private var widget: WidgetSettingsViewController.SupportedWidget = .weeklyProgress
    private let titleLabel = UILabel()
    private let familyLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8))

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(
        widget: WidgetSettingsViewController.SupportedWidget,
        title: String,
        familyText: String
    ) {
        self.widget = widget
        titleLabel.text = title
        familyLabel.text = familyText
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let previewRect = CGRect(
            x: rect.minX + 14,
            y: rect.minY + 46,
            width: rect.width - 28,
            height: rect.height - 62
        )

        switch widget {
        case .weeklyProgress:
            drawWeeklyProgress(in: previewRect)
        case .weeklyChart:
            drawWeeklyChart(in: previewRect)
        case .monthlyCalendar:
            drawMonthlyCalendar(in: previewRect)
        case .annualTrajectory:
            drawAnnualTrajectory(in: previewRect)
        case .worldMap:
            drawWorldMap(in: previewRect)
        case .chinaMap:
            drawChinaMap(in: previewRect)
        }
    }

    private func configureViews() {
        backgroundColor = AppColors.groupedCardBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true
        contentMode = .redraw

        titleLabel.textColor = AppColors.solidForeground
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7

        familyLabel.textColor = AppColors.movinnGreen
        familyLabel.backgroundColor = AppColors.movinnGreen.withAlphaComponent(0.14)
        familyLabel.layer.cornerRadius = 9
        familyLabel.layer.masksToBounds = true
        familyLabel.font = .systemFont(ofSize: 10, weight: .bold)
        familyLabel.textAlignment = .center

        addSubview(titleLabel)
        addSubview(familyLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.top.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualTo(familyLabel.snp.leading).offset(-8)
        }

        familyLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalTo(titleLabel)
        }
    }

    private func drawWeeklyProgress(in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY - 2)
        let radius = min(rect.width, rect.height) * 0.4
        let lineWidth: CGFloat = 12
        let basePath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        UIColor.systemGray4.setStroke()
        basePath.lineWidth = lineWidth
        basePath.lineCapStyle = .round
        basePath.stroke()

        let progressPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + .pi * 1.34,
            clockwise: true
        )
        AppColors.movinnGreen.setStroke()
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        progressPath.stroke()

        drawText(
            "128",
            in: CGRect(x: center.x - 42, y: center.y - 18, width: 84, height: 23),
            font: .systemFont(ofSize: 22, weight: .bold),
            color: AppColors.solidForeground,
            alignment: .center
        )
        drawText(
            "km",
            in: CGRect(x: center.x - 42, y: center.y + 5, width: 84, height: 16),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: AppColors.foreground(alpha: 0.46),
            alignment: .center
        )
    }

    private func drawWeeklyChart(in rect: CGRect) {
        let values: [CGFloat] = [0.22, 0.58, 0.34, 0.76, 0.46, 0.86, 0.52]
        let barWidth = rect.width / CGFloat(values.count) * 0.56
        let maxHeight = rect.height - 26
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) * rect.width / CGFloat(values.count) + barWidth * 0.38
            let height = maxHeight * value
            let barRect = CGRect(x: x, y: rect.maxY - height - 16, width: barWidth, height: height)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: 4)
            AppColors.movinnGreen.withAlphaComponent(index == 5 ? 1 : 0.72).setFill()
            path.fill()
        }
    }

    private func drawMonthlyCalendar(in rect: CGRect) {
        let columns = 7
        let rows = 6
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = (rect.height - 22) / CGFloat(rows)
        let highlightedIndexes: Set<Int> = [4, 7, 12, 18, 23, 30, 35, 38]

        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let center = CGPoint(
                    x: rect.minX + CGFloat(column) * cellWidth + cellWidth / 2,
                    y: rect.minY + 20 + CGFloat(row) * cellHeight + cellHeight / 2
                )
                let radius: CGFloat = highlightedIndexes.contains(index) ? 6 : 2.6
                let path = UIBezierPath(
                    ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                )
                (highlightedIndexes.contains(index)
                    ? AppColors.movinnGreen
                    : AppColors.foreground(alpha: 0.16)
                ).setFill()
                path.fill()
            }
        }
    }

    private func drawAnnualTrajectory(in rect: CGRect) {
        let firstValues: [CGFloat] = [0.1, 0.22, 0.18, 0.38, 0.46, 0.34, 0.64, 0.52, 0.76, 0.68, 0.82]
        let secondValues: [CGFloat] = [0.2, 0.16, 0.32, 0.28, 0.52, 0.48, 0.58, 0.44, 0.66, 0.6, 0.7]
        drawCurve(values: secondValues, in: rect.insetBy(dx: 4, dy: 20), color: AppColors.foreground(alpha: 0.24), lineWidth: 2)
        drawCurve(values: firstValues, in: rect.insetBy(dx: 4, dy: 20), color: AppColors.movinnGreen, lineWidth: 3)
    }

    private func drawWorldMap(in rect: CGRect) {
        let worldRect = rect.insetBy(dx: 2, dy: 20)
        drawMapShape(in: worldRect, highlightPoints: [
            CGPoint(x: worldRect.minX + worldRect.width * 0.72, y: worldRect.minY + worldRect.height * 0.44),
            CGPoint(x: worldRect.minX + worldRect.width * 0.48, y: worldRect.minY + worldRect.height * 0.38)
        ])
    }

    private func drawChinaMap(in rect: CGRect) {
        let chinaRect = CGRect(
            x: rect.minX + rect.width * 0.16,
            y: rect.minY + rect.height * 0.12,
            width: rect.width * 0.68,
            height: rect.height * 0.76
        )
        drawMapShape(in: chinaRect, highlightPoints: [
            CGPoint(x: chinaRect.minX + chinaRect.width * 0.62, y: chinaRect.minY + chinaRect.height * 0.48)
        ])
    }

    private func drawMapShape(in rect: CGRect, highlightPoints: [CGPoint]) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        AppColors.foreground(alpha: 0.08).setFill()
        path.fill()
        AppColors.foreground(alpha: 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        for point in highlightPoints {
            let markerPath = UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            AppColors.movinnGreen.setFill()
            markerPath.fill()
        }
    }

    private func drawCurve(values: [CGFloat], in rect: CGRect, color: UIColor, lineWidth: CGFloat) {
        guard values.count > 1 else {
            return
        }

        let path = UIBezierPath()
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width,
                y: rect.maxY - value * rect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        color.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
