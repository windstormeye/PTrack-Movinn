//
//  SportsCareerViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/16.
//

import Charts
import SnapKit
import SwiftUI
import UIKit

final class SportsCareerViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case summary
        case annual
        case monthly
        case weekly
        case overview

        var titleKey: AppTextKey {
            switch self {
            case .summary:
                return .sportsCareerSummary
            case .annual:
                return .sportsCareerAnnualData
            case .monthly:
                return .sportsCareerMonthlyData
            case .weekly:
                return .sportsCareerWeeklyData
            case .overview:
                return .sportsCareerOverview
            }
        }
    }

    private let workouts: [TrackedWorkout]
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private var collectionView: UICollectionView!
    private var statistics: SportsCareerStatistics
    private var hasPlayedAppearanceAnimation = false

    private let navigationBackgroundHeight: CGFloat = 124

    init(workouts: [TrackedWorkout]) {
        self.workouts = workouts
        statistics = SportsCareerStatistics(workouts: workouts)
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
        collectionView.collectionViewLayout.invalidateLayout()
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

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        layout.sectionHeadersPinToVisibleBounds = false

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight + 18,
            left: 0,
            bottom: 28,
            right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.alpha = 0
        collectionView.transform = CGAffineTransform(translationX: 0, y: 28)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CareerSummaryCell.self, forCellWithReuseIdentifier: CareerSummaryCell.reuseIdentifier)
        collectionView.register(CareerAnnualCurveCell.self, forCellWithReuseIdentifier: CareerAnnualCurveCell.reuseIdentifier)
        collectionView.register(CareerMonthCalendarCell.self, forCellWithReuseIdentifier: CareerMonthCalendarCell.reuseIdentifier)
        collectionView.register(CareerWeeklyChartCell.self, forCellWithReuseIdentifier: CareerWeeklyChartCell.reuseIdentifier)
        collectionView.register(CareerSportOverviewCell.self, forCellWithReuseIdentifier: CareerSportOverviewCell.reuseIdentifier)
        collectionView.register(
            CareerSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: CareerSectionHeaderView.reuseIdentifier
        )

        navigationBackgroundView.isUserInteractionEnabled = false
        navigationBackgroundView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        navigationBackgroundMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        navigationBackgroundMask.locations = [0, 0.58, 1]
        navigationBackgroundView.layer.mask = navigationBackgroundMask

        view.addSubview(collectionView)
        view.addSubview(navigationBackgroundView)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
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
        statistics = SportsCareerStatistics(workouts: workouts)
        collectionView.reloadData()
    }

    private func playAppearanceAnimationIfNeeded() {
        guard !hasPlayedAppearanceAnimation else {
            return
        }

        hasPlayedAppearanceAnimation = true
        collectionView.layoutIfNeeded()
        animateVisibleMetricCells()

        UIView.animate(
            withDuration: 0.42,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.collectionView.alpha = 1
            self.collectionView.transform = .identity
        }
    }

    private func animateVisibleMetricCells() {
        for cell in collectionView.visibleCells {
            switch cell {
            case let cell as CareerSummaryCell:
                cell.animateValuesFromZero(duration: 0.9)
            case let cell as CareerSportOverviewCell:
                cell.animateValuesFromZero(duration: 0.9)
            default:
                break
            }
        }
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func height(for section: Section, width: CGFloat) -> CGFloat {
        switch section {
        case .summary:
            return 64
        case .annual:
            return max(210, CGFloat(statistics.annualDurationSeries.count) * 72 + 28)
        case .monthly:
            return 344
        case .weekly:
            return 218
        case .overview:
            return 238 + sportGridHeight(width: width)
        }
    }

    private func sportGridHeight(width: CGFloat) -> CGFloat {
        guard !statistics.sportRows.isEmpty else {
            return 0
        }

        let columnCount: CGFloat = 3
        let itemHeight: CGFloat = 142
        let spacing: CGFloat = 10
        let rowCount = ceil(CGFloat(statistics.sportRows.count) / columnCount)
        return rowCount * itemHeight + max(rowCount - 1, 0) * spacing
    }
}

extension SportsCareerViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Section(rawValue: section) == nil ? 0 : 1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UICollectionViewCell()
        }

        switch section {
        case .summary:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerSummaryCell.reuseIdentifier,
                for: indexPath
            ) as? CareerSummaryCell else {
                return UICollectionViewCell()
            }

            cell.configure(statistics: statistics)
            return cell
        case .annual:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerAnnualCurveCell.reuseIdentifier,
                for: indexPath
            ) as? CareerAnnualCurveCell else {
                return UICollectionViewCell()
            }

            cell.configure(series: statistics.annualDurationSeries)
            return cell
        case .monthly:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerMonthCalendarCell.reuseIdentifier,
                for: indexPath
            ) as? CareerMonthCalendarCell else {
                return UICollectionViewCell()
            }

            cell.configure(days: statistics.monthActivityDays, monthDate: statistics.currentMonthDate)
            return cell
        case .weekly:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerWeeklyChartCell.reuseIdentifier,
                for: indexPath
            ) as? CareerWeeklyChartCell else {
                return UICollectionViewCell()
            }

            cell.configure(rows: statistics.weeklyDistanceRows)
            return cell
        case .overview:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerSportOverviewCell.reuseIdentifier,
                for: indexPath
            ) as? CareerSportOverviewCell else {
                return UICollectionViewCell()
            }

            cell.configure(rows: statistics.sportRows, slices: statistics.sportDistributionSlices)
            return cell
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let section = Section(rawValue: indexPath.section),
              let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: CareerSectionHeaderView.reuseIdentifier,
                for: indexPath
              ) as? CareerSectionHeaderView else {
            return UICollectionReusableView()
        }

        headerView.configure(
            title: AppLocalization.text(section.titleKey)
        )
        return headerView
    }
}

extension SportsCareerViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let section = Section(rawValue: indexPath.section) else {
            return .zero
        }

        let width = collectionView.bounds.width - 32
        return CGSize(width: width, height: height(for: section, width: width))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        guard let section = Section(rawValue: section) else {
            return UIEdgeInsets(top: 0, left: 16, bottom: 10, right: 16)
        }

        if section == .summary {
            return UIEdgeInsets(top: 0, left: 16, bottom: 6, right: 16)
        }

        return UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        guard let section = Section(rawValue: section),
              section != .summary else {
            return .zero
        }

        return CGSize(width: collectionView.bounds.width, height: 30)
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

    struct AnnualDurationSeries {
        let year: Int
        let weeklyDurationSeconds: [TimeInterval]
        let weeklyDistanceMeters: [Double]
        let visibleWeekCount: Int
    }

    struct MonthActivityDay {
        let date: Date
        let day: Int
        let symbolNames: [String]
    }

    struct WeeklyDistanceRow: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let distanceMeters: Double

        var distanceKilometers: Double {
            distanceMeters / 1_000
        }
    }

    struct SportDistributionSlice: Identifiable {
        let id = UUID()
        let title: String
        let value: Double
        let color: Color
    }

    let totalDistanceMeters: Double
    let totalCount: Int
    let totalDurationSeconds: TimeInterval
    let sportRows: [SportRow]
    let annualDurationSeries: [AnnualDurationSeries]
    let monthActivityDays: [MonthActivityDay]
    let weeklyDistanceRows: [WeeklyDistanceRow]
    let sportDistributionSlices: [SportDistributionSlice]
    let currentMonthDate: Date

    init(workouts: [TrackedWorkout], calendar: Calendar = .current, now: Date = Date()) {
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        totalCount = workouts.count
        totalDurationSeconds = workouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }

        sportRows = Dictionary(grouping: workouts, by: \.title)
            .map { title, workouts in
                let symbolName = workouts.first?.symbolName ?? "figure.walk"
                return SportRow(
                    title: title,
                    symbolName: symbolName,
                    iconStyle: CareerSportIconStyle(symbolName: symbolName),
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

        annualDurationSeries = Self.makeAnnualDurationSeries(
            workouts: workouts,
            calendar: calendar,
            now: now
        )
        currentMonthDate = now
        monthActivityDays = Self.makeMonthActivityDays(
            workouts: workouts,
            calendar: calendar
        )
        weeklyDistanceRows = Self.makeWeeklyDistanceRows(
            workouts: workouts,
            calendar: calendar,
            now: now
        )
        sportDistributionSlices = Self.makeSportDistributionSlices(from: sportRows)
    }

    private static func makeAnnualDurationSeries(
        workouts: [TrackedWorkout],
        calendar: Calendar,
        now: Date
    ) -> [AnnualDurationSeries] {
        let currentYear = calendar.component(.year, from: now)
        var yearlyDurations: [Int: [Int: TimeInterval]] = [:]
        var yearlyDistances: [Int: [Int: Double]] = [:]

        for workout in workouts {
            let year = calendar.component(.year, from: workout.startDate)
            let weekOfYear = min(max(calendar.component(.weekOfYear, from: workout.startDate), 1), 53)
            yearlyDurations[year, default: [:]][weekOfYear, default: 0] += workout.durationSeconds ?? 0
            yearlyDistances[year, default: [:]][weekOfYear, default: 0] += workout.distanceMeters
        }

        if yearlyDurations.isEmpty {
            yearlyDurations[currentYear] = [:]
            yearlyDistances[currentYear] = [:]
        }

        return yearlyDurations.keys.sorted(by: >).map { year in
            let durations = yearlyDurations[year] ?? [:]
            let distances = yearlyDistances[year] ?? [:]
            let durationValues = (1...53).map { weekOfYear in
                durations[weekOfYear] ?? 0
            }
            let distanceValues = (1...53).map { weekOfYear in
                distances[weekOfYear] ?? 0
            }
            let visibleWeekCount = year == currentYear
                ? min(max(calendar.component(.weekOfYear, from: now), 1), durationValues.count)
                : durationValues.count
            return AnnualDurationSeries(
                year: year,
                weeklyDurationSeconds: durationValues,
                weeklyDistanceMeters: distanceValues,
                visibleWeekCount: visibleWeekCount
            )
        }
    }

    private static func makeMonthActivityDays(
        workouts: [TrackedWorkout],
        calendar: Calendar
    ) -> [MonthActivityDay] {
        Dictionary(grouping: workouts) { workout in
            calendar.startOfDay(for: workout.startDate)
        }
        .map { date, workouts in
            let day = calendar.component(.day, from: date)
            let symbolNames = workouts
                .map(\.symbolName)
                .reduce(into: [String]()) { result, symbolName in
                    guard !result.contains(symbolName) else {
                        return
                    }

                    result.append(symbolName)
                }

            return MonthActivityDay(date: date, day: day, symbolNames: Array(symbolNames.prefix(4)))
        }
        .sorted { $0.date < $1.date }
    }

    private static func makeWeeklyDistanceRows(
        workouts: [TrackedWorkout],
        calendar: Calendar,
        now: Date
    ) -> [WeeklyDistanceRow] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.dateFormat = "E"

        return (0..<7).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                return nil
            }

            let distance = workouts.reduce(0) { partialResult, workout in
                guard calendar.isDate(workout.startDate, inSameDayAs: date) else {
                    return partialResult
                }

                return partialResult + workout.distanceMeters
            }

            return WeeklyDistanceRow(
                date: date,
                title: formatter.string(from: date),
                distanceMeters: distance
            )
        }
    }

    private static func makeSportDistributionSlices(from rows: [SportRow]) -> [SportDistributionSlice] {
        let colors: [Color] = [
            Color(uiColor: AppColors.movinnGreen),
            .black,
            .orange,
            .blue,
            .purple,
            .pink,
            .teal,
            .gray
        ]
        let positiveRows = rows.filter { $0.distanceMeters > 0 }
        let sourceRows = positiveRows.isEmpty ? rows.filter { $0.count > 0 } : positiveRows

        return sourceRows.enumerated().map { index, row in
            SportDistributionSlice(
                title: row.title,
                value: positiveRows.isEmpty ? Double(row.count) : row.distanceMeters,
                color: colors[index % colors.count]
            )
        }
    }
}

private func careerSummaryDistanceText(_ value: Double) -> String {
    "\(Int((value / 1_000).rounded())) km"
}

private func careerSummaryDurationText(_ value: Double) -> String {
    AppLocalization.format(.durationHoursFormat, max(Int(value / 3_600), 0))
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

private final class CareerSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "CareerSectionHeaderView"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
    }

    func configure(title: String) {
        titleLabel.text = title
    }

    private func configureViews() {
        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.74

        addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(16)
        }
    }
}

private final class CareerSummaryCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerSummaryCell"

    private let stackView = UIStackView()
    private let totalDistanceView = CareerSummaryMetricView()
    private let totalCountView = CareerSummaryMetricView()
    private let totalDurationView = CareerSummaryMetricView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(statistics: SportsCareerStatistics) {
        totalDistanceView.configure(
            title: AppLocalization.text(.totalWorkoutDistance),
            value: statistics.totalDistanceMeters,
            formatter: careerSummaryDistanceText
        )
        totalCountView.configure(
            title: AppLocalization.text(.totalWorkoutCount),
            value: Double(statistics.totalCount),
            formatter: { AppLocalization.format(.totalActivityCountFormat, Int($0.rounded())) }
        )
        totalDurationView.configure(
            title: AppLocalization.text(.totalWorkoutTime),
            value: statistics.totalDurationSeconds,
            formatter: careerSummaryDurationText
        )
    }

    func animateValuesFromZero(duration: TimeInterval) {
        totalDistanceView.animateValueFromZero(duration: duration)
        totalCountView.animateValueFromZero(duration: duration)
        totalDurationView.animateValueFromZero(duration: duration)
    }

    private func configureViews() {
        contentView.backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.distribution = .equalCentering
        stackView.alignment = .fill
        stackView.spacing = 10

        [totalDistanceView, totalCountView, totalDurationView].forEach {
            stackView.addArrangedSubview($0)
        }

        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

private final class CareerSummaryMetricView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = AnimatedMetricLabel()
    private var cachedIntrinsicWidth: CGFloat = UIView.noIntrinsicMetric

    func configure(title: String, value: Double, formatter: @escaping (Double) -> String) {
        titleLabel.text = title
        let valueText = formatter(value)
        cachedIntrinsicWidth = ceil(max(
            title.size(withAttributes: [.font: titleLabel.font as Any]).width,
            valueText.size(withAttributes: [.font: valueLabel.font as Any]).width
        ))
        invalidateIntrinsicContentSize()
        valueLabel.configure(finalValue: value, formatter: formatter)
    }

    func animateValueFromZero(duration: TimeInterval) {
        valueLabel.animateFromZero(duration: duration)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: cachedIntrinsicWidth, height: UIView.noIntrinsicMetric)
    }

    private func configureViews() {
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textAlignment = .left
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.68

        valueLabel.textColor = AppColors.movinnGreen
        valueLabel.font = .systemFont(ofSize: 21, weight: .bold)
        valueLabel.textAlignment = .left
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.54
        valueLabel.numberOfLines = 1

        addSubview(titleLabel)
        addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(18)
        }

        valueLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(32)
        }
    }
}

private final class CareerAnnualCurveCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerAnnualCurveCell"

    private let curveView = CareerAnnualCurveView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(series: [SportsCareerStatistics.AnnualDurationSeries]) {
        curveView.configure(series: series)
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        contentView.addSubview(curveView)
        curveView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
    }
}

private final class CareerAnnualCurveView: UIView, UIGestureRecognizerDelegate {
    private struct CurveSelection: Equatable {
        let seriesIndex: Int
        let weekIndex: Int
    }

    private struct CurveLayout {
        let chartRect: CGRect
        let rowHeight: CGFloat
        let maxValue: TimeInterval
    }

    private var series: [SportsCareerStatistics.AnnualDurationSeries] = []
    private var selection: CurveSelection?
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    private let yearLabelWidth: CGFloat = 48
    private weak var disabledInteractivePopGestureRecognizer: UIGestureRecognizer?
    private var disabledInteractivePopGestureWasEnabled: Bool?
    private var hasConfiguredInteractivePopGestureFailureRequirement = false
    private lazy var selectionPanGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionPan(_:)))
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        addGestureRecognizer(selectionPanGestureRecognizer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        addGestureRecognizer(selectionPanGestureRecognizer)
    }

    func configure(series: [SportsCareerStatistics.AnnualDurationSeries]) {
        self.series = series
        selection = nil
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureInteractivePopGestureFailureRequirementIfNeeded()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              let layout = makeLayout(in: rect) else {
            return
        }

        let yearAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.black
        ]

        for (seriesIndex, item) in series.enumerated() {
            let rowMinY = layout.chartRect.minY + CGFloat(seriesIndex) * layout.rowHeight
            let baselineY = rowMinY + layout.rowHeight * 0.78
            let amplitude = layout.rowHeight * 0.66
            let values = Array(item.weeklyDurationSeconds.prefix(item.visibleWeekCount))
            let xDenominator = CGFloat(max(item.weeklyDurationSeconds.count - 1, 1))

            let yearText = "\(item.year)" as NSString
            let yearSize = yearText.size(withAttributes: yearAttributes)
            yearText.draw(
                at: CGPoint(
                    x: rect.minX,
                    y: baselineY - yearSize.height / 2
                ),
                withAttributes: yearAttributes
            )

            let baselinePath = UIBezierPath()
            baselinePath.move(to: CGPoint(x: layout.chartRect.minX, y: baselineY))
            baselinePath.addLine(to: CGPoint(x: layout.chartRect.maxX, y: baselineY))
            UIColor.black.withAlphaComponent(0.08).setStroke()
            baselinePath.lineWidth = 1
            baselinePath.stroke()

            guard values.count > 1 else {
                continue
            }

            let chartPoints = values.enumerated().map { index, value in
                let x = layout.chartRect.minX + CGFloat(index) / xDenominator * layout.chartRect.width
                let y = baselineY - CGFloat(value / layout.maxValue) * amplitude
                return CGPoint(x: x, y: y)
            }

            let path = UIBezierPath()
            path.move(to: chartPoints[0])
            for index in 1..<chartPoints.count {
                let previous = chartPoints[index - 1]
                let current = chartPoints[index]
                let deltaX = current.x - previous.x
                let controlPoint1 = CGPoint(x: previous.x + deltaX * 0.42, y: previous.y)
                let controlPoint2 = CGPoint(x: current.x - deltaX * 0.42, y: current.y)
                path.addCurve(to: current, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }

            context.saveGState()
            UIColor.white.setStroke()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            context.restoreGState()

            AppColors.movinnGreen.setStroke()
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        drawSelection(in: rect, layout: layout)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        disableInteractivePopGestureIfNeeded()
        selectionFeedbackGenerator.prepare()
        updateSelection(with: touches.first)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        updateSelection(with: touches.first)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        restoreInteractivePopGestureIfNeeded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        selection = nil
        restoreInteractivePopGestureIfNeeded()
        setNeedsDisplay()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === selectionPanGestureRecognizer else {
            return true
        }

        let velocity = selectionPanGestureRecognizer.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handleSelectionPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            disableInteractivePopGestureIfNeeded()
            selectionFeedbackGenerator.prepare()
            updateSelection(at: gestureRecognizer.location(in: self))
        case .changed:
            updateSelection(at: gestureRecognizer.location(in: self))
        case .ended, .cancelled, .failed:
            restoreInteractivePopGestureIfNeeded()
        default:
            break
        }
    }

    private func makeLayout(in rect: CGRect) -> CurveLayout? {
        guard !series.isEmpty else {
            return nil
        }

        let chartRect = CGRect(
            x: rect.minX + yearLabelWidth,
            y: rect.minY,
            width: max(rect.width - yearLabelWidth, 1),
            height: rect.height
        )
        let visibleValues = series.flatMap { item in
            Array(item.weeklyDurationSeconds.prefix(item.visibleWeekCount))
        }
        return CurveLayout(
            chartRect: chartRect,
            rowHeight: chartRect.height / CGFloat(series.count),
            maxValue: max(visibleValues.max() ?? 0, 1)
        )
    }

    private func updateSelection(with touch: UITouch?) {
        guard let touch else {
            return
        }

        updateSelection(at: touch.location(in: self))
    }

    private func updateSelection(at point: CGPoint) {
        guard let newSelection = selection(at: point, in: bounds),
              newSelection != selection else {
            return
        }

        selection = newSelection
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
        setNeedsDisplay()
    }

    private func selection(at point: CGPoint, in rect: CGRect) -> CurveSelection? {
        guard let layout = makeLayout(in: rect),
              !series.isEmpty else {
            return nil
        }

        let rawSeriesIndex = Int(((point.y - layout.chartRect.minY) / layout.rowHeight).rounded(.down))
        let seriesIndex = min(max(rawSeriesIndex, 0), series.count - 1)
        let item = series[seriesIndex]
        let maxWeekIndex = max(item.visibleWeekCount - 1, 0)
        let denominator = CGFloat(max(item.weeklyDurationSeconds.count - 1, 1))
        let weekOffset = ((point.x - layout.chartRect.minX) / layout.chartRect.width) * denominator
        let weekIndex = min(max(Int(weekOffset.rounded()), 0), maxWeekIndex)

        return CurveSelection(seriesIndex: seriesIndex, weekIndex: weekIndex)
    }

    private func xPosition(
        for weekIndex: Int,
        item: SportsCareerStatistics.AnnualDurationSeries,
        layout: CurveLayout
    ) -> CGFloat {
        let denominator = CGFloat(max(item.weeklyDurationSeconds.count - 1, 1))
        return layout.chartRect.minX + CGFloat(weekIndex) / denominator * layout.chartRect.width
    }

    private func drawSelection(in rect: CGRect, layout: CurveLayout) {
        guard let selection,
              series.indices.contains(selection.seriesIndex),
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let item = series[selection.seriesIndex]
        let weekIndex = min(selection.weekIndex, max(item.visibleWeekCount - 1, 0))
        let rowMinY = layout.chartRect.minY + CGFloat(selection.seriesIndex) * layout.rowHeight
        let rowMaxY = rowMinY + layout.rowHeight
        let indicatorX = xPosition(for: weekIndex, item: item, layout: layout)
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: indicatorX, y: rowMinY + 6))
        linePath.addLine(to: CGPoint(x: indicatorX, y: rowMaxY - 6))
        UIColor.black.withAlphaComponent(0.22).setStroke()
        linePath.lineWidth = 1
        linePath.stroke()

        let distanceMeters = item.weeklyDistanceMeters.indices.contains(weekIndex)
            ? item.weeklyDistanceMeters[weekIndex]
            : 0
        let tooltipText = AppLocalization.format(
            .sportsCareerWeekDistanceFormat,
            weekIndex + 1,
            distanceMeters / 1_000
        )
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let textRect = (tooltipText as NSString).boundingRect(
            with: CGSize(width: 86, height: 60),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )
        let padding = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        let tooltipSize = CGSize(
            width: ceil(textRect.width + padding.left + padding.right),
            height: ceil(textRect.height + padding.top + padding.bottom)
        )
        var tooltipX = indicatorX + 24
        if tooltipX + tooltipSize.width > rect.maxX {
            tooltipX = indicatorX - tooltipSize.width - 14
        }
        tooltipX = min(max(tooltipX, rect.minX), rect.maxX - tooltipSize.width)

        let baselineY = rowMinY + layout.rowHeight * 0.78
        var tooltipY = baselineY - tooltipSize.height - 42
        tooltipY = min(max(tooltipY, rect.minY + 4), rowMaxY - tooltipSize.height - 4)

        let tooltipRect = CGRect(origin: CGPoint(x: tooltipX, y: tooltipY), size: tooltipSize)
        let tooltipPath = UIBezierPath(roundedRect: tooltipRect, cornerRadius: 8)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 2),
            blur: 8,
            color: UIColor.black.withAlphaComponent(0.12).cgColor
        )
        UIColor.white.setFill()
        tooltipPath.fill()
        context.restoreGState()

        UIColor.black.withAlphaComponent(0.08).setStroke()
        tooltipPath.lineWidth = 1
        tooltipPath.stroke()

        let insetTextRect = tooltipRect.inset(by: padding)
        (tooltipText as NSString).draw(
            with: insetTextRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )
    }

    private func disableInteractivePopGestureIfNeeded() {
        configureInteractivePopGestureFailureRequirementIfNeeded()

        guard disabledInteractivePopGestureRecognizer == nil,
              let gestureRecognizer = nearestNavigationController()?.interactivePopGestureRecognizer else {
            return
        }

        disabledInteractivePopGestureRecognizer = gestureRecognizer
        disabledInteractivePopGestureWasEnabled = gestureRecognizer.isEnabled
        gestureRecognizer.isEnabled = false
    }

    private func restoreInteractivePopGestureIfNeeded() {
        guard let gestureRecognizer = disabledInteractivePopGestureRecognizer,
              let wasEnabled = disabledInteractivePopGestureWasEnabled else {
            return
        }

        gestureRecognizer.isEnabled = wasEnabled
        disabledInteractivePopGestureRecognizer = nil
        disabledInteractivePopGestureWasEnabled = nil
    }

    private func configureInteractivePopGestureFailureRequirementIfNeeded() {
        guard !hasConfiguredInteractivePopGestureFailureRequirement,
              let gestureRecognizer = nearestNavigationController()?.interactivePopGestureRecognizer else {
            return
        }

        gestureRecognizer.require(toFail: selectionPanGestureRecognizer)
        hasConfiguredInteractivePopGestureFailureRequirement = true
    }

    private func nearestNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController.navigationController
            }

            responder = currentResponder.next
        }

        return nil
    }
}

private final class CareerMonthCalendarCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerMonthCalendarCell"

    private static let calendarScale: CGFloat = 0.84
    private let calendarWrapperView = UIView()
    private let calendarView = UICalendarView()
    private var activitySymbolsByDateKey: [String: [String]] = [:]
    private var decoratedDateComponents: [DateComponents] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(days: [SportsCareerStatistics.MonthActivityDay], monthDate: Date) {
        activitySymbolsByDateKey = Dictionary(uniqueKeysWithValues: days.map { day in
            (Self.dateKey(for: day.date), day.symbolNames)
        })
        decoratedDateComponents = days.map { day in
            Calendar.current.dateComponents([.year, .month, .day], from: day.date)
        }

        var visibleDateComponents = Calendar.current.dateComponents([.year, .month], from: monthDate)
        visibleDateComponents.day = 1
        calendarView.calendar = .current
        calendarView.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        calendarView.visibleDateComponents = visibleDateComponents
        calendarView.reloadDecorations(forDateComponents: decoratedDateComponents, animated: false)
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        calendarWrapperView.clipsToBounds = true

        calendarView.backgroundColor = .clear
        calendarView.tintColor = AppColors.movinnGreen
        calendarView.delegate = self
        calendarView.selectionBehavior = nil
        calendarView.transform = CGAffineTransform(
            scaleX: Self.calendarScale,
            y: Self.calendarScale
        )
        calendarView.layer.allowsEdgeAntialiasing = true

        contentView.addSubview(calendarWrapperView)
        calendarWrapperView.addSubview(calendarView)

        calendarWrapperView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }

        calendarView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(calendarWrapperView.snp.width).multipliedBy(1 / Self.calendarScale)
            make.height.equalTo(calendarWrapperView.snp.height).multipliedBy(1 / Self.calendarScale)
        }
    }

    private static func dateKey(for date: Date) -> String {
        dateKey(for: Calendar.current.dateComponents([.year, .month, .day], from: date))
    }

    private static func dateKey(for dateComponents: DateComponents) -> String {
        guard let year = dateComponents.year,
              let month = dateComponents.month,
              let day = dateComponents.day else {
            return ""
        }
        return "\(year)-\(month)-\(day)"
    }
}

extension CareerMonthCalendarCell: UICalendarViewDelegate {
    func calendarView(
        _ calendarView: UICalendarView,
        decorationFor dateComponents: DateComponents
    ) -> UICalendarView.Decoration? {
        let key = Self.dateKey(for: dateComponents)
        guard let symbolNames = activitySymbolsByDateKey[key],
              !symbolNames.isEmpty else {
            return nil
        }

        return .customView {
            CareerCalendarDecorationView(symbolNames: symbolNames)
        }
    }
}

private final class CareerCalendarDecorationView: UIView {
    private var iconViews: [UIImageView] = []

    init(symbolNames: [String]) {
        super.init(frame: .zero)
        configureViews()
        configure(symbolNames: symbolNames)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 42, height: 18)
    }

    private func configure(symbolNames: [String]) {
        let limitedSymbolNames = Array(symbolNames.prefix(4))
        let pointSize: CGFloat = limitedSymbolNames.count == 1 ? 12 : 9

        iconViews = limitedSymbolNames.map { symbolName in
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            let imageView = UIImageView(
                image: UIImage(
                    systemName: symbolName,
                    withConfiguration: configuration
                ) ?? UIImage(systemName: "figure.walk", withConfiguration: configuration)
            )
            imageView.tintColor = .black
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
            return imageView
        }

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconArea = bounds.insetBy(dx: 4, dy: 3)
        let count = iconViews.count

        for (index, imageView) in iconViews.enumerated() {
            switch count {
            case 1:
                let side = min(iconArea.width, iconArea.height)
                imageView.frame = CGRect(
                    x: iconArea.midX - side / 2,
                    y: iconArea.midY - side / 2,
                    width: side,
                    height: side
                )
            case 2:
                let width = iconArea.width / 2
                imageView.frame = CGRect(
                    x: iconArea.minX + CGFloat(index) * width,
                    y: iconArea.minY,
                    width: width,
                    height: iconArea.height
                )
            default:
                let width = iconArea.width / 2
                let height = iconArea.height / 2
                imageView.frame = CGRect(
                    x: iconArea.minX + CGFloat(index % 2) * width,
                    y: iconArea.minY + CGFloat(index / 2) * height,
                    width: width,
                    height: height
                )
            }
        }
    }

    private func configureViews() {
        backgroundColor = UIColor.white.withAlphaComponent(0.9)
        layer.cornerRadius = 6
        layer.borderColor = UIColor.black.withAlphaComponent(0.06).cgColor
        layer.borderWidth = 0.5
        layer.masksToBounds = true
    }
}

private final class CareerWeeklyChartCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerWeeklyChartCell"

    private let hostingView = CareerChartHostingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(rows: [SportsCareerStatistics.WeeklyDistanceRow]) {
        hostingView.setContent(CareerWeeklyDistanceChart(rows: rows))
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        contentView.addSubview(hostingView)
        hostingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

private final class CareerSportOverviewCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerSportOverviewCell"

    private let hostingView = CareerChartHostingView()
    private let sportTypeGridView = CareerSportTypeGridView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(
        rows: [SportsCareerStatistics.SportRow],
        slices: [SportsCareerStatistics.SportDistributionSlice]
    ) {
        hostingView.setContent(CareerSportDistributionChart(slices: slices))
        sportTypeGridView.configure(rows: rows)
    }

    func animateValuesFromZero(duration: TimeInterval) {
        sportTypeGridView.animateValuesFromZero(duration: duration)
    }

    private func configureViews() {
        contentView.backgroundColor = .clear

        contentView.addSubview(hostingView)
        contentView.addSubview(sportTypeGridView)

        hostingView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(222)
        }

        sportTypeGridView.snp.makeConstraints { make in
            make.top.equalTo(hostingView.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }
}

private final class CareerChartHostingView: UIView {
    private var hostingController: UIHostingController<AnyView>?

    func setContent<Content: View>(_ content: Content) {
        if let hostingController {
            hostingController.rootView = AnyView(content)
            return
        }

        let hostingController = UIHostingController(rootView: AnyView(content))
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController

        addSubview(hostingController.view)
        hostingController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

private struct CareerWeeklyDistanceChart: View {
    let rows: [SportsCareerStatistics.WeeklyDistanceRow]

    var body: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Day", row.title),
                y: .value("Distance", row.distanceKilometers)
            )
            .foregroundStyle(Color(uiColor: AppColors.movinnGreen))
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: rows.map(\.title))
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.white.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
    }
}

private struct CareerSportDistributionChart: View {
    let slices: [SportsCareerStatistics.SportDistributionSlice]

    var body: some View {
        HStack(spacing: 14) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Value", max(slice.value, 0.01)),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.6
                )
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text(slice.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(uiColor: UIColor(white: 0.965, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
