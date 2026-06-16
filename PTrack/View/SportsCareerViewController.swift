//
//  SportsCareerViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/16.
//

import SnapKit
import UIKit

final class SportsCareerViewController: UIViewController {
    private let workouts: [TrackedWorkout]
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStackView = UIStackView()
    private let totalDistanceCard = CareerMetricCardView()
    private let totalCountCard = CareerMetricCardView()
    private let totalDurationCard = CareerMetricCardView()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()

    private var animatedValueLabels: [AnimatedMetricLabel] = []
    private var sportTypeGridView: CareerSportTypeGridView?
    private var hasPlayedAppearanceAnimation = false
    private let navigationBackgroundHeight: CGFloat = 124

    init(workouts: [TrackedWorkout]) {
        self.workouts = workouts
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureNavigationBar()
        configureViews()
        registerLanguageObserver()
        applyStatistics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playAppearanceAnimationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
    }

    private func configureNavigationItem() {
        title = AppLocalization.text(.sportsCareer)
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
        view.backgroundColor = .systemBackground

        navigationBackgroundView.isUserInteractionEnabled = false
        navigationBackgroundView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        navigationBackgroundMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        navigationBackgroundMask.locations = [0, 0.58, 1]
        navigationBackgroundView.layer.mask = navigationBackgroundMask

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 28,
            right: 0
        )
        scrollView.scrollIndicatorInsets = scrollView.contentInset

        contentStackView.axis = .vertical
        contentStackView.spacing = 18
        contentStackView.alpha = 0
        contentStackView.transform = CGAffineTransform(translationX: 0, y: 28)

        view.addSubview(scrollView)
        view.addSubview(navigationBackgroundView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStackView)

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
        }

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        contentStackView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview()
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

    @objc private func handleLanguageDidChange() {
        title = AppLocalization.text(.sportsCareer)
        applyStatistics()
    }

    private func applyStatistics() {
        animatedValueLabels.removeAll()
        contentStackView.arrangedSubviews.forEach { view in
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let statistics = SportsCareerStatistics(workouts: workouts)
        let metricGridView = makeMetricGridView(statistics: statistics)
        contentStackView.addArrangedSubview(metricGridView)
        contentStackView.addArrangedSubview(makeSportTypeSummaryView(rows: statistics.sportRows))

        if hasPlayedAppearanceAnimation {
            animatedValueLabels.forEach { $0.setFinalValueWithoutAnimation() }
            sportTypeGridView?.showFinalValues()
        }
    }

    private func makeMetricGridView(statistics: SportsCareerStatistics) -> UIView {
        let containerView = UIView()
        let stackView = UIStackView(arrangedSubviews: [totalDistanceCard, totalCountCard, totalDurationCard])
        stackView.axis = .vertical
        stackView.spacing = 10

        totalDistanceCard.configure(
            title: AppLocalization.text(.totalWorkoutDistance),
            value: statistics.totalDistanceMeters / 1000,
            formatter: { String(format: "%.1f km", $0) }
        )
        totalCountCard.configure(
            title: AppLocalization.text(.totalWorkoutCount),
            value: Double(statistics.totalCount),
            formatter: { AppLocalization.format(.totalActivityCountFormat, Int($0.rounded())) }
        )
        totalDurationCard.configure(
            title: AppLocalization.text(.totalWorkoutTime),
            value: statistics.totalDurationSeconds,
            formatter: careerDurationText
        )

        animatedValueLabels.append(contentsOf: [
            totalDistanceCard.valueLabel,
            totalCountCard.valueLabel,
            totalDurationCard.valueLabel
        ])

        containerView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return containerView
    }

    private func makeSportTypeSummaryView(rows: [SportsCareerStatistics.SportRow]) -> UIView {
        let containerView = UIView()
        let gridView = CareerSportTypeGridView()

        gridView.configure(rows: rows)
        sportTypeGridView = gridView

        containerView.addSubview(gridView)
        gridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return containerView
    }

    private func playAppearanceAnimationIfNeeded() {
        guard !hasPlayedAppearanceAnimation else {
            return
        }

        hasPlayedAppearanceAnimation = true
        contentStackView.alpha = 0
        contentStackView.transform = CGAffineTransform(translationX: 0, y: 28)

        animatedValueLabels.forEach { $0.animateFromZero(duration: 0.9) }
        sportTypeGridView?.animateValuesFromZero(duration: 0.9)

        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.contentStackView.alpha = 1
            self.contentStackView.transform = .identity
        }
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

}

private struct SportsCareerStatistics {
    struct SportRow {
        let title: String
        let symbolName: String
        let iconStyle: CareerSportIconStyle
        let count: Int
        let distanceMeters: Double
        let durationSeconds: TimeInterval
    }

    let totalDistanceMeters: Double
    let totalCount: Int
    let totalDurationSeconds: TimeInterval
    let sportRows: [SportRow]

    init(workouts: [TrackedWorkout]) {
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        totalCount = workouts.count
        totalDurationSeconds = workouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }

        sportRows = Dictionary(grouping: workouts, by: \.title)
            .map { title, workouts in
                SportRow(
                    title: title,
                    symbolName: workouts.first?.symbolName ?? "figure.walk",
                    iconStyle: CareerSportIconStyle(symbolName: workouts.first?.symbolName ?? "figure.walk"),
                    count: workouts.count,
                    distanceMeters: workouts.reduce(0) { $0 + $1.distanceMeters },
                    durationSeconds: workouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
                )
            }
            .sorted {
                if $0.distanceMeters == $1.distanceMeters {
                    if $0.count == $1.count {
                        return $0.title < $1.title
                    }

                    return $0.count > $1.count
                }

                return $0.distanceMeters > $1.distanceMeters
            }
    }
}

private func careerDurationText(_ value: Double) -> String {
    let totalMinutes = max(Int(value / 60), 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return AppLocalization.format(.durationHoursMinutesFormat, hours, minutes)
    }

    return AppLocalization.format(.durationMinutesFormat, minutes)
}

private func careerDistanceText(_ value: Double) -> String {
    if value >= 1000 {
        return String(format: "%.1f km", value / 1000)
    }

    if value > 0 {
        return AppLocalization.format(.distanceMetersFormat, value)
    }

    return AppLocalization.text(.unknownDistance)
}

private func careerDistanceAttributedText(_ value: Double) -> NSAttributedString {
    careerEmphasizedNumberText(
        careerDistanceText(value),
        numberFont: .systemFont(ofSize: 22, weight: .bold),
        unitFont: .systemFont(ofSize: 13, weight: .bold),
        color: AppColors.movinnGreen
    )
}

private func careerDurationAttributedText(_ value: Double) -> NSAttributedString {
    careerEmphasizedNumberText(
        careerDurationText(value),
        numberFont: .systemFont(ofSize: 18, weight: .bold),
        unitFont: .systemFont(ofSize: 12, weight: .semibold),
        color: .black
    )
}

private func careerEmphasizedNumberText(
    _ text: String,
    numberFont: UIFont,
    unitFont: UIFont,
    color: UIColor
) -> NSAttributedString {
    let attributedText = NSMutableAttributedString(
        string: text,
        attributes: [
            .font: unitFont,
            .foregroundColor: color
        ]
    )
    let nsText = text as NSString
    let numberCharacterSet = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))
    var rangeStart: Int?

    for index in 0..<nsText.length {
        let scalar = UnicodeScalar(nsText.character(at: index))
        let isNumberCharacter = scalar.map { numberCharacterSet.contains($0) } ?? false
        if isNumberCharacter {
            if rangeStart == nil {
                rangeStart = index
            }
        } else if let start = rangeStart {
            attributedText.addAttributes([.font: numberFont], range: NSRange(location: start, length: index - start))
            rangeStart = nil
        }
    }

    if let start = rangeStart {
        attributedText.addAttributes([.font: numberFont], range: NSRange(location: start, length: nsText.length - start))
    }

    return attributedText
}

private struct CareerSportIconStyle {
    let pointSize: CGFloat
    let weight: UIImage.SymbolWeight
    let canvasSize: CGFloat

    init(symbolName: String) {
        switch symbolName {
        case "figure.outdoor.cycle":
            pointSize = 34
            canvasSize = 32
        case "figure.indoor.cycle":
            pointSize = 20
            canvasSize = 32
        case "figure.run":
            pointSize = 31
            canvasSize = 32
        case "figure.walk":
            pointSize = 22
            canvasSize = 32
        case "figure.hiking":
            pointSize = 22
            canvasSize = 32
        case "figure.walk.motion":
            pointSize = 30
            canvasSize = 34
        case "figure.open.water.swim":
            pointSize = 29
            canvasSize = 34
        default:
            pointSize = 30
            canvasSize = 32
        }
        weight = .semibold
    }

    var symbolConfiguration: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    }
}

private final class CareerSportTypeGridView: UIView {
    private enum Layout {
        static let columnCount: CGFloat = 3
        static let itemHeight: CGFloat = 142
        static let itemSpacing: CGFloat = 10
    }

    private let collectionView: UICollectionView
    private var rows: [SportsCareerStatistics.SportRow] = []
    private var heightConstraint: Constraint?
    private var shouldAnimateValues = false
    private var animatedIndexPaths = Set<IndexPath>()

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = Layout.itemSpacing
        layout.minimumInteritemSpacing = Layout.itemSpacing
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = Layout.itemSpacing
        layout.minimumInteritemSpacing = Layout.itemSpacing
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(coder: coder)
        configureViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    func configure(rows: [SportsCareerStatistics.SportRow]) {
        self.rows = rows
        shouldAnimateValues = false
        animatedIndexPaths.removeAll()
        collectionView.reloadData()
        heightConstraint?.update(offset: collectionHeight(for: rows.count))
    }

    func animateValuesFromZero(duration: TimeInterval) {
        shouldAnimateValues = true
        animatedIndexPaths.removeAll()
        collectionView.layoutIfNeeded()
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? CareerSportTypeCell else {
                continue
            }

            cell.animateValuesFromZero(duration: duration)
            animatedIndexPaths.insert(indexPath)
        }
    }

    func showFinalValues() {
        shouldAnimateValues = false
        for cell in collectionView.visibleCells {
            (cell as? CareerSportTypeCell)?.setFinalValues()
        }
    }

    private func configureViews() {
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CareerSportTypeCell.self, forCellWithReuseIdentifier: CareerSportTypeCell.reuseIdentifier)

        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            heightConstraint = make.height.equalTo(0).constraint
        }
    }

    private func collectionHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else {
            return 0
        }

        let rows = ceil(CGFloat(itemCount) / Layout.columnCount)
        return rows * Layout.itemHeight + max(rows - 1, 0) * Layout.itemSpacing
    }
}

extension CareerSportTypeGridView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rows.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CareerSportTypeCell.reuseIdentifier,
            for: indexPath
        ) as? CareerSportTypeCell else {
            return UICollectionViewCell()
        }

        cell.configure(with: rows[indexPath.item])
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard shouldAnimateValues,
              !animatedIndexPaths.contains(indexPath),
              let cell = cell as? CareerSportTypeCell else {
            return
        }

        cell.animateValuesFromZero(duration: 0.9)
        animatedIndexPaths.insert(indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let totalSpacing = Layout.itemSpacing * (Layout.columnCount - 1)
        let width = floor((collectionView.bounds.width - totalSpacing) / Layout.columnCount)
        return CGSize(width: max(width, 0), height: Layout.itemHeight)
    }
}

private final class CareerSportTypeCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerSportTypeCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let distanceLabel = AnimatedMetricLabel()
    private let durationLabel = AnimatedMetricLabel()
    private var iconWidthConstraint: Constraint?
    private var iconHeightConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(with row: SportsCareerStatistics.SportRow) {
        iconView.image = UIImage(
            systemName: row.symbolName,
            withConfiguration: row.iconStyle.symbolConfiguration
        )?.withRenderingMode(.alwaysTemplate)
        iconWidthConstraint?.update(offset: row.iconStyle.canvasSize)
        iconHeightConstraint?.update(offset: row.iconStyle.canvasSize)
        titleLabel.text = row.title
        distanceLabel.configure(
            finalValue: row.distanceMeters,
            attributedFormatter: careerDistanceAttributedText
        )
        durationLabel.configure(
            finalValue: row.durationSeconds,
            attributedFormatter: careerDurationAttributedText
        )
    }

    func animateValuesFromZero(duration: TimeInterval) {
        distanceLabel.animateFromZero(duration: duration)
        durationLabel.animateFromZero(duration: duration)
    }

    func setFinalValues() {
        distanceLabel.setFinalValueWithoutAnimation()
        durationLabel.setFinalValueWithoutAnimation()
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        iconView.tintColor = .black
        iconView.contentMode = .scaleAspectFit

        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textAlignment = .right
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.62

        distanceLabel.textColor = AppColors.movinnGreen
        distanceLabel.font = .systemFont(ofSize: 22, weight: .bold)
        distanceLabel.textAlignment = .left
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.46

        durationLabel.textColor = .black
        durationLabel.font = .systemFont(ofSize: 18, weight: .bold)
        durationLabel.textAlignment = .left
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.46

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(distanceLabel)
        contentView.addSubview(durationLabel)

        iconView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(12)
            iconWidthConstraint = make.width.equalTo(32).constraint
            iconHeightConstraint = make.height.equalTo(32).constraint
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.greaterThanOrEqualTo(iconView.snp.trailing).offset(6)
            make.trailing.equalToSuperview().inset(10)
        }

        distanceLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalTo(durationLabel.snp.top).offset(-3)
        }

        durationLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.bottom.equalToSuperview().inset(12)
        }
    }
}

private final class CareerMetricCardView: UIView {
    let valueLabel = AnimatedMetricLabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(title: String, value: Double, formatter: @escaping (Double) -> String) {
        titleLabel.text = title
        valueLabel.configure(finalValue: value, formatter: formatter)
    }

    private func configureViews() {
        backgroundColor = UIColor(white: 0.945, alpha: 1)
        layer.cornerRadius = 8
        layer.masksToBounds = true

        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.textColor = AppColors.movinnGreen
        valueLabel.font = .systemFont(ofSize: 30, weight: .bold)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        addSubview(titleLabel)
        addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }

        valueLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(16)
        }
    }
}

private final class AnimatedMetricLabel: UILabel {
    private var finalValue: Double = 0
    private var formatter: (Double) -> String = { "\($0)" }
    private var attributedFormatter: ((Double) -> NSAttributedString)?
    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var animationDuration: TimeInterval = 0

    deinit {
        displayLink?.invalidate()
    }

    func configure(finalValue: Double, formatter: @escaping (Double) -> String) {
        displayLink?.invalidate()
        self.finalValue = finalValue
        self.formatter = formatter
        attributedFormatter = nil
        updateDisplayedValue(finalValue)
    }

    func configure(finalValue: Double, attributedFormatter: @escaping (Double) -> NSAttributedString) {
        displayLink?.invalidate()
        self.finalValue = finalValue
        self.attributedFormatter = attributedFormatter
        formatter = { attributedFormatter($0).string }
        updateDisplayedValue(finalValue)
    }

    func setFinalValueWithoutAnimation() {
        displayLink?.invalidate()
        updateDisplayedValue(finalValue)
    }

    func animateFromZero(duration: TimeInterval) {
        displayLink?.invalidate()
        animationDuration = duration
        animationStartTime = CACurrentMediaTime()
        updateDisplayedValue(0)

        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        let elapsedTime = displayLink.timestamp - animationStartTime
        let progress = min(max(elapsedTime / animationDuration, 0), 1)
        let easedProgress = 1 - pow(1 - progress, 3)
        updateDisplayedValue(finalValue * easedProgress)

        guard progress >= 1 else {
            return
        }

        self.displayLink?.invalidate()
        self.displayLink = nil
        updateDisplayedValue(finalValue)
    }

    private func updateDisplayedValue(_ value: Double) {
        if let attributedFormatter {
            attributedText = attributedFormatter(value)
        } else {
            attributedText = nil
            text = formatter(value)
        }
    }
}
