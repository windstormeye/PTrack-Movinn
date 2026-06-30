//
//  WidgetSettingsViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import SnapKit
import SwiftUI
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
    private let previewAreaView = UIView()
    private let previewCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceHorizontal = true
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.decelerationRate = .fast
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.clipsToBounds = false
        return collectionView
    }()
    private let previewPageControl = UIPageControl()
    private let goalCardView = UIView()
    private let goalTitleLabel = UILabel()
    private let goalTextField = UITextField()
    private let goalUnitLabel = UILabel()
    private let goalStepper = UIStepper()
    private let goalStepperFeedbackGenerator = UISelectionFeedbackGenerator()
    private var goalDoneButton: UIBarButtonItem?
    private var widgetSnapshot = PTrackWidgetSnapshotReader.loadSnapshot()
    private let navigationBackgroundHeight: CGFloat = 124

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureViews()
        registerLanguageObserver()
        registerKeyboardObservers()
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
        widgetSnapshot = PTrackWidgetSnapshotReader.loadSnapshot()
        updateGoalControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewCollectionView.collectionViewLayout.invalidateLayout()
        updatePreviewPageControlCurrentPage()
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

        previewCollectionView.dataSource = self
        previewCollectionView.delegate = self
        previewCollectionView.register(
            WidgetPreviewCollectionViewCell.self,
            forCellWithReuseIdentifier: WidgetPreviewCollectionViewCell.reuseIdentifier
        )

        previewPageControl.numberOfPages = SupportedWidget.allCases.count
        previewPageControl.currentPage = 0
        previewPageControl.hidesForSinglePage = true
        previewPageControl.isUserInteractionEnabled = false
        previewPageControl.currentPageIndicatorTintColor = AppColors.movinnGreen
        previewPageControl.pageIndicatorTintColor = AppColors.foreground(alpha: 0.18)
        previewPageControl.backgroundStyle = .minimal

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
        configureGoalKeyboardAccessory()

        goalUnitLabel.textColor = AppColors.foreground(alpha: 0.52)
        goalUnitLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        goalStepper.minimumValue = 1
        goalStepper.maximumValue = 9_999
        goalStepper.stepValue = 10
        goalStepper.addTarget(self, action: #selector(handleGoalStepperValueChanged), for: .valueChanged)
        goalStepperFeedbackGenerator.prepare()

        view.addSubview(scrollView)
        view.addSubview(navigationBackgroundView)
        scrollView.addSubview(contentView)
        contentView.addSubview(previewAreaView)
        previewAreaView.addSubview(previewCollectionView)
        previewAreaView.addSubview(previewPageControl)
        contentView.addSubview(goalCardView)
        goalCardView.addSubview(goalTitleLabel)
        goalCardView.addSubview(goalTextField)
        goalCardView.addSubview(goalUnitLabel)
        goalCardView.addSubview(goalStepper)

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
            make.height.greaterThanOrEqualTo(scrollView.frameLayoutGuide).offset(-(navigationBackgroundHeight + 28))
        }

        previewAreaView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(goalCardView.snp.top).offset(-18)
        }

        previewCollectionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview().offset(-22)
            make.height.equalTo(356)
        }

        previewPageControl.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.centerX.equalToSuperview()
            make.height.equalTo(20)
        }

        goalCardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(96)
            make.bottom.equalToSuperview().inset(20)
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

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
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
        goalDoneButton?.title = AppLocalization.text(.ok)

        updateWidgetPreviewCards()
    }

    private func updateWidgetPreviewCards() {
        for cell in previewCollectionView.visibleCells {
            guard let cell = cell as? WidgetPreviewCollectionViewCell,
                  let indexPath = previewCollectionView.indexPath(for: cell) else {
                continue
            }

            configurePreviewCell(cell, at: indexPath)
        }
    }

    private func updateAppearanceColors() {
        goalCardView.backgroundColor = AppColors.groupedCardBackground
        goalTitleLabel.textColor = AppColors.solidForeground
        goalTextField.textColor = AppColors.solidForeground
        goalTextField.tintColor = AppColors.movinnGreen
        goalUnitLabel.textColor = AppColors.foreground(alpha: 0.52)
        previewPageControl.currentPageIndicatorTintColor = AppColors.movinnGreen
        previewPageControl.pageIndicatorTintColor = AppColors.foreground(alpha: 0.18)
        previewCollectionView.visibleCells.forEach { cell in
            (cell as? WidgetPreviewCollectionViewCell)?.updateAppearance()
        }
    }

    private func updateGoalControls() {
        let kilometers = PTrackWidgetSettingsStore.weeklyGoalDistanceKilometers
        goalStepper.value = kilometers
        goalTextField.text = formattedGoalText(kilometers)
        updateWidgetPreviewCards()
    }

    private func formattedGoalText(_ kilometers: Double) -> String {
        if kilometers.rounded() == kilometers {
            return "\(Int(kilometers))"
        }

        return String(format: "%.1f", kilometers)
    }

    @objc private func handleGoalStepperValueChanged() {
        goalStepperFeedbackGenerator.selectionChanged()
        goalStepperFeedbackGenerator.prepare()
        PTrackWidgetSettingsStore.setWeeklyGoalDistanceKilometers(goalStepper.value)
        goalTextField.text = formattedGoalText(goalStepper.value)
        updateWidgetPreviewCards()
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

    private func configureGoalKeyboardAccessory() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(
            title: AppLocalization.text(.ok),
            style: .done,
            target: self,
            action: #selector(handleGoalInputDoneButtonTapped)
        )
        goalDoneButton = doneButton
        toolbar.items = [flexibleSpace, doneButton]
        goalTextField.inputAccessoryView = toolbar
    }

    @objc private func handleGoalInputDoneButtonTapped() {
        commitGoalTextFieldValue()
        goalTextField.resignFirstResponder()
    }

    @objc private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        updateKeyboardAvoidance(with: notification, hidesKeyboard: false)
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        updateKeyboardAvoidance(with: notification, hidesKeyboard: true)
    }

    private func updateKeyboardAvoidance(with notification: Notification, hidesKeyboard: Bool) {
        let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let keyboardFrameInView = view.convert(keyboardFrame, from: nil)
        let keyboardOverlap = hidesKeyboard ? 0 : max(view.bounds.maxY - keyboardFrameInView.minY, 0)
        let bottomInset = keyboardOverlap > 0 ? keyboardOverlap + 18 : 28
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRawValue = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
            ?? UInt(UIView.AnimationOptions.curveEaseInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)

        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.scrollView.contentInset.bottom = bottomInset
            var indicatorInsets = self.scrollView.verticalScrollIndicatorInsets
            indicatorInsets.bottom = bottomInset
            self.scrollView.verticalScrollIndicatorInsets = indicatorInsets
            self.view.layoutIfNeeded()
        } completion: { _ in
            guard keyboardOverlap > 0, self.goalTextField.isFirstResponder else {
                return
            }

            let visibleRect = self.goalCardView.frame.insetBy(dx: 0, dy: -12)
            self.scrollView.scrollRectToVisible(visibleRect, animated: true)
        }
    }

    private func configurePreviewCell(_ cell: WidgetPreviewCollectionViewCell, at indexPath: IndexPath) {
        guard SupportedWidget.allCases.indices.contains(indexPath.item) else {
            return
        }

        let widget = SupportedWidget.allCases[indexPath.item]
        cell.configure(
            widget: widget,
            title: AppLocalization.text(widget.titleKey),
            familyText: widget.familyText,
            snapshot: widgetSnapshot,
            goalDistanceMeters: PTrackWidgetSettingsStore.weeklyGoalDistanceMeters
        )
    }

    private func updatePreviewPageControlCurrentPage() {
        let pageWidth = previewCollectionView.bounds.width
        guard pageWidth > 0 else {
            previewPageControl.currentPage = 0
            return
        }

        let rawPage = previewCollectionView.contentOffset.x / pageWidth
        let page = Int(round(rawPage))
        previewPageControl.currentPage = min(max(page, 0), SupportedWidget.allCases.count - 1)
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

extension WidgetSettingsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        SupportedWidget.allCases.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WidgetPreviewCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? WidgetPreviewCollectionViewCell else {
            return UICollectionViewCell()
        }

        configurePreviewCell(cell, at: indexPath)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let cell = cell as? WidgetPreviewCollectionViewCell else {
            return
        }

        configurePreviewCell(cell, at: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        .zero
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === previewCollectionView else {
            return
        }

        updatePreviewPageControlCurrentPage()
    }
}

private struct WidgetSettingsPreviewHostView: View {
    let widget: WidgetSettingsViewController.SupportedWidget
    let snapshot: PTrackWidgetSnapshot
    let goalDistanceMeters: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = fittedSize(in: proxy.size)
            let cornerRadius = min(size.height * 0.22, 32)
            content
                .frame(width: size.width, height: size.height)
                .background(WidgetSettingsPreviewBackgroundView())
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: 12, x: 0, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widget {
        case .weeklyProgress:
            PTrackWeeklyProgressWidgetContentView(snapshot: snapshot, goalDistanceMeters: goalDistanceMeters)
        case .weeklyChart:
            PTrackWeeklyChartWidgetContentView(snapshot: snapshot)
        case .monthlyCalendar:
            PTrackMonthlyCalendarWidgetContentView(snapshot: snapshot)
        case .annualTrajectory:
            PTrackAnnualTrajectoryWidgetContentView(snapshot: snapshot)
        case .worldMap:
            PTrackLocationMapWidgetContentView(
                snapshot: snapshot,
                map: .world,
                brightensDarkOutlinesInPreview: true
            )
        case .chinaMap:
            PTrackLocationMapWidgetContentView(
                snapshot: snapshot,
                map: .china,
                brightensDarkOutlinesInPreview: true
            )
        }
    }

    private func fittedSize(in bounds: CGSize) -> CGSize {
        switch widget {
        case .weeklyProgress, .monthlyCalendar:
            return fittedSize(aspectRatio: 1, preferredHeight: widget == .weeklyProgress ? 158 : 300, in: bounds)
        case .weeklyChart, .annualTrajectory, .worldMap, .chinaMap:
            return fittedSize(aspectRatio: 2.08, preferredHeight: 158, in: bounds)
        }
    }

    private func fittedSize(aspectRatio: CGFloat, preferredHeight: CGFloat, in bounds: CGSize) -> CGSize {
        let maxWidth = max(bounds.width - 32, 1)
        let maxHeight = max(bounds.height - 56, 1)
        let height = min(preferredHeight, maxHeight, maxWidth / max(aspectRatio, 0.1))

        return CGSize(width: height * aspectRatio, height: height)
    }

    private var borderColor: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.14)
        default:
            return Color.black.opacity(0.10)
        }
    }

    private var shadowColor: Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.26)
        default:
            return Color.black.opacity(0.12)
        }
    }
}

private struct WidgetSettingsPreviewBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            LinearGradient(
                colors: highlightColors,
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var backgroundColors: [Color] {
        switch colorScheme {
        case .dark:
            return [
                Color(red: 0.15, green: 0.15, blue: 0.16),
                Color(red: 0.11, green: 0.11, blue: 0.12)
            ]
        default:
            return [
                Color(red: 1.00, green: 1.00, blue: 1.00),
                Color(red: 0.98, green: 0.98, blue: 0.99)
            ]
        }
    }

    private var highlightColors: [Color] {
        switch colorScheme {
        case .dark:
            return [
                Color.white.opacity(0.035),
                Color.clear
            ]
        default:
            return [
                Color.white.opacity(0.58),
                Color.clear
            ]
        }
    }
}

private final class WidgetPreviewCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "WidgetPreviewCollectionViewCell"

    private var hostingController: UIHostingController<WidgetSettingsPreviewHostView>?

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
        familyText: String,
        snapshot: PTrackWidgetSnapshot,
        goalDistanceMeters: Double
    ) {
        accessibilityLabel = "\(title), \(familyText)"

        let rootView = WidgetSettingsPreviewHostView(
            widget: widget,
            snapshot: snapshot,
            goalDistanceMeters: goalDistanceMeters
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.clipsToBounds = false
            hostingController.view.isUserInteractionEnabled = false
            contentView.addSubview(hostingController.view)
            hostingController.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            self.hostingController = hostingController
        }
    }

    func updateAppearance() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        hostingController?.view.backgroundColor = .clear
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        clipsToBounds = false
        isAccessibilityElement = true
    }
}
