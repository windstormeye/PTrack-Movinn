//
//  SportsCareerViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/16.
//

import Charts
import CoreLocation
import SnapKit
import SwiftUI
import UIKit

private func sportsCareerWeekCalendar(from calendar: Calendar) -> Calendar {
    var weekCalendar = calendar
    weekCalendar.firstWeekday = 2
    weekCalendar.minimumDaysInFirstWeek = 4
    return weekCalendar
}

final class SportsCareerViewController: UIViewController {
    enum PresentationStyle {
        case pushed
        case heatmapSheet
    }

    private enum Section: Int, CaseIterable {
        case summary
        case weekly
        case monthly
        case annual
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

    static let heatmapSheetCollapsedHeight: CGFloat = 90

    private var workouts: [TrackedWorkout]
    private let presentationStyle: PresentationStyle
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private var collectionView: UICollectionView!
    private var statistics: SportsCareerStatistics?
    private var statisticsLoadToken = UUID()
    private var hasPlayedAppearanceAnimation = false
    private var monthlyWorkoutSelectionIndexesByDateKey: [String: Int] = [:]
    var onSelectWorkout: ((TrackedWorkout) -> Void)?

    private let navigationBackgroundHeight: CGFloat = 124
    private let sheetContentTopInset: CGFloat = 30

    init(workouts: [TrackedWorkout], presentationStyle: PresentationStyle = .pushed) {
        self.workouts = workouts
        self.presentationStyle = presentationStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        statisticsLoadToken = UUID()
        onSelectWorkout = nil
        if isViewLoaded {
            collectionView.dataSource = nil
            collectionView.delegate = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureNavigationBar()
        configureViews()
        registerLanguageObserver()
        reloadStatisticsAsync()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if presentationStyle == .pushed {
            navigationController?.setNavigationBarHidden(false, animated: animated)
            configureNavigationBar()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playAppearanceAnimationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if presentationStyle == .pushed {
            updateNavigationBackgroundMask()
        }
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func configureNavigationItem() {
        title = presentationStyle == .pushed ? AppLocalization.text(.sportsCareer) : nil
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
        view.backgroundColor = presentationStyle == .pushed ? .systemBackground : .clear
        view.isOpaque = presentationStyle == .pushed

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 6
        layout.minimumInteritemSpacing = 10
        layout.sectionHeadersPinToVisibleBounds = false

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = presentationStyle == .pushed ? .systemBackground : .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(
            top: presentationStyle == .pushed ? navigationBackgroundHeight + 18 : sheetContentTopInset,
            left: 0,
            bottom: 28,
            right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.alpha = 0
        collectionView.transform = CGAffineTransform(translationX: 0, y: 28)
        collectionView.isUserInteractionEnabled = true
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
        if presentationStyle == .pushed {
            view.addSubview(navigationBackgroundView)
        }

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        if presentationStyle == .pushed {
            navigationBackgroundView.snp.makeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
                make.height.equalTo(navigationBackgroundHeight)
            }
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
        title = presentationStyle == .pushed ? AppLocalization.text(.sportsCareer) : nil
        reloadStatisticsAsync()
    }

    func resetHeatmapSheetContentOffset() {
        guard presentationStyle == .heatmapSheet,
              isViewLoaded else {
            return
        }

        let topOffset = -collectionView.adjustedContentInset.top
        collectionView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: false)
    }

    func setHeatmapSheetContentVisible(_ isVisible: Bool, animated: Bool) {
        guard presentationStyle == .heatmapSheet else {
            return
        }

        guard isViewLoaded else {
            return
        }

        if !isVisible {
            resetHeatmapSheetContentOffset()
        }

        let changes = {
            self.collectionView.alpha = 1
            self.collectionView.transform = .identity
        }
        collectionView.isUserInteractionEnabled = true

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
            animations: changes
        )
    }

    func updateWorkouts(_ workouts: [TrackedWorkout], animated: Bool) {
        let incomingIDs = Set(workouts.map(\.id))
        guard incomingIDs != Set(self.workouts.map(\.id)) else {
            return
        }

        self.workouts = workouts
        reloadStatisticsAsync(animatedFromPrevious: animated)
    }

    private func reloadStatisticsAsync(animatedFromPrevious: Bool = false) {
        let loadToken = UUID()
        let workouts = workouts
        let language = AppLanguageStore.shared.language
        let previousStatistics = statistics
        let shouldShowLoading = !animatedFromPrevious || previousStatistics == nil
        statisticsLoadToken = loadToken
        if shouldShowLoading {
            statistics = nil
            collectionView?.reloadData()
            collectionView?.collectionViewLayout.invalidateLayout()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let statistics = SportsCareerStatistics(
                workouts: workouts,
                language: language
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.statisticsLoadToken == loadToken else {
                    return
                }

                self.statistics = statistics
                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.reloadData()

                if animatedFromPrevious,
                   let previousStatistics,
                   self.hasPlayedAppearanceAnimation {
                    self.animateVisibleMetricCells(from: previousStatistics, to: statistics)
                } else if self.hasPlayedAppearanceAnimation {
                    self.animateVisibleMetricCells()
                }
            }
        }
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

    private func animateVisibleMetricCells(
        from previousStatistics: SportsCareerStatistics,
        to statistics: SportsCareerStatistics
    ) {
        for cell in collectionView.visibleCells {
            switch cell {
            case let cell as CareerSummaryCell:
                cell.animateValues(from: previousStatistics, to: statistics, duration: 0.55)
            case let cell as CareerSportOverviewCell:
                cell.animateValuesFromZero(duration: 0.55)
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
            return max(210, CGFloat(statistics?.annualDurationSeries.count ?? 0) * 72 + 28)
        case .monthly:
            return 292
        case .weekly:
            return 244
        case .overview:
            let locationHeight = locationOverviewHeight(width: width)
            return 238
                + (locationHeight > 0 ? locationHeight + 16 : 0)
                + sportGridHeight(width: width)
        }
    }

    private func locationOverviewHeight(width: CGFloat) -> CGFloat {
        guard let statistics,
              !statistics.locationSummary.isEmpty else {
            return 0
        }

        return CareerLocationOverviewView.height(
            for: statistics.locationSummary,
            width: width
        )
    }

    private func sportGridHeight(width: CGFloat) -> CGFloat {
        guard let statistics,
              !statistics.sportRows.isEmpty else {
            return 0
        }

        let columnCount: CGFloat = 3
        let itemHeight: CGFloat = 142
        let spacing: CGFloat = 10
        let rowCount = ceil(CGFloat(statistics.sportRows.count) / columnCount)
        return rowCount * itemHeight + max(rowCount - 1, 0) * spacing
    }

    private func showNextMonthlyWorkout(on date: Date, workouts: [TrackedWorkout]) {
        guard !workouts.isEmpty else {
            return
        }

        let key = Self.dateKey(for: date)
        let currentIndex = monthlyWorkoutSelectionIndexesByDateKey[key, default: 0]
        let selectedWorkout = workouts[currentIndex % workouts.count]
        monthlyWorkoutSelectionIndexesByDateKey[key] = (currentIndex + 1) % workouts.count

        if let onSelectWorkout {
            onSelectWorkout(selectedWorkout)
            return
        }

        let detailViewController = WorkoutRouteDetailViewController(workout: selectedWorkout)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }

        return "\(year)-\(month)-\(day)"
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

            if let statistics {
                cell.configure(statistics: statistics)
            } else {
                cell.configureLoading()
            }
            return cell
        case .annual:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerAnnualCurveCell.reuseIdentifier,
                for: indexPath
            ) as? CareerAnnualCurveCell else {
                return UICollectionViewCell()
            }

            if let statistics {
                cell.configure(series: statistics.annualDurationSeries)
            } else {
                cell.configureLoading()
            }
            return cell
        case .monthly:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerMonthCalendarCell.reuseIdentifier,
                for: indexPath
            ) as? CareerMonthCalendarCell else {
                return UICollectionViewCell()
            }

            cell.onSelectDayWorkouts = { [weak self] date, workouts in
                self?.showNextMonthlyWorkout(on: date, workouts: workouts)
            }
            if let statistics {
                cell.configure(days: statistics.monthActivityDays, monthDate: statistics.currentMonthDate)
            } else {
                cell.configureLoading()
            }
            return cell
        case .weekly: 
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerWeeklyChartCell.reuseIdentifier,
                for: indexPath
            ) as? CareerWeeklyChartCell else {
                return UICollectionViewCell()
            }

            if let statistics {
                cell.configure(rows: statistics.weeklyDistanceRows)
            } else {
                cell.configureLoading()
            }
            return cell
        case .overview:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CareerSportOverviewCell.reuseIdentifier,
                for: indexPath
            ) as? CareerSportOverviewCell else {
                return UICollectionViewCell()
            }

            if let statistics {
                let contentWidth = collectionView.bounds.width - 32
                cell.configure(
                    rows: statistics.sportRows,
                    slices: statistics.sportDistributionSlices,
                    locationSummary: statistics.locationSummary,
                    locationHeight: locationOverviewHeight(width: contentWidth)
                )
            } else {
                cell.configureLoading()
            }
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
            return UIEdgeInsets(top: 0, left: 16, bottom: 26, right: 16)
        }

        if section == .annual || section == .monthly || section == .weekly {
            return UIEdgeInsets(top: 18, left: 16, bottom: 38, right: 16)
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

        return CGSize(width: collectionView.bounds.width, height: 26)
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
        let totalDistanceMeters: Double
        let totalDurationSeconds: TimeInterval
    }

    struct MonthActivityDay {
        let date: Date
        let day: Int
        let symbolNames: [String]
        let workouts: [TrackedWorkout]
    }

    struct WeeklyDistanceRow: Identifiable {
        var id: Int { index }
        let index: Int
        let date: Date
        let title: String
        let distanceMeters: Double
        let durationSeconds: TimeInterval

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

    struct LocationSummary {
        let countryNames: [String]
        let chinaCityNames: [String]
        let worldHighlightedIdentifiers: Set<String>
        let chinaHighlightedIdentifiers: Set<String>

        var isEmpty: Bool {
            countryNames.isEmpty
        }

        var hasChinaMap: Bool {
            !chinaHighlightedIdentifiers.isEmpty
        }
    }

    let totalDistanceMeters: Double
    let totalCount: Int
    let totalDurationSeconds: TimeInterval
    let sportRows: [SportRow]
    let annualDurationSeries: [AnnualDurationSeries]
    let monthActivityDays: [MonthActivityDay]
    let weeklyDistanceRows: [WeeklyDistanceRow]
    let sportDistributionSlices: [SportDistributionSlice]
    let locationSummary: LocationSummary
    let currentMonthDate: Date

    init(
        workouts: [TrackedWorkout],
        calendar: Calendar = .current,
        now: Date = Date(),
        language: AppLanguage = AppLanguageStore.shared.language
    ) {
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        totalCount = workouts.count
        totalDurationSeconds = workouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }

        sportRows = Dictionary(grouping: workouts, by: \.sportKind)
            .map { sportKind, workouts in
                let symbolName = sportKind.symbolName
                return SportRow(
                    title: Self.sportTitle(for: sportKind, language: language),
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
            now: now,
            language: language
        )
        sportDistributionSlices = Self.makeSportDistributionSlices(from: sportRows)
        locationSummary = Self.makeLocationSummary(
            from: workouts,
            language: language
        )
    }

    private static func makeAnnualDurationSeries(
        workouts: [TrackedWorkout],
        calendar: Calendar,
        now: Date
    ) -> [AnnualDurationSeries] {
        let weekCalendar = sportsCareerWeekCalendar(from: calendar)
        let currentYear = weekCalendar.component(.yearForWeekOfYear, from: now)
        let currentWeekOfYear = min(max(weekCalendar.component(.weekOfYear, from: now), 1), 53)
        var yearlyDurations: [Int: [Int: TimeInterval]] = [:]
        var yearlyDistances: [Int: [Int: Double]] = [:]

        for workout in workouts {
            let year = weekCalendar.component(.yearForWeekOfYear, from: workout.startDate)
            let weekOfYear = min(max(weekCalendar.component(.weekOfYear, from: workout.startDate), 1), 53)
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
            let weekCount = weeksInYear(year, calendar: weekCalendar)
            let durationValues = (1...weekCount).map { weekOfYear in
                durations[weekOfYear] ?? 0
            }
            let distanceValues = (1...weekCount).map { weekOfYear in
                distances[weekOfYear] ?? 0
            }
            let visibleWeekCount = year == currentYear
                ? min(currentWeekOfYear, durationValues.count)
                : durationValues.count
            return AnnualDurationSeries(
                year: year,
                weeklyDurationSeconds: durationValues,
                weeklyDistanceMeters: distanceValues,
                visibleWeekCount: visibleWeekCount,
                totalDistanceMeters: distanceValues.reduce(0, +),
                totalDurationSeconds: durationValues.reduce(0, +)
            )
        }
    }

    private static func weeksInYear(_ year: Int, calendar: Calendar) -> Int {
        let components = DateComponents(calendar: calendar, year: year, month: 12, day: 28)
        guard let date = calendar.date(from: components) else {
            return 52
        }

        return min(max(calendar.component(.weekOfYear, from: date), 52), 53)
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
            let sortedWorkouts = workouts.sorted { $0.startDate < $1.startDate }
            let symbolNames = sortedWorkouts
                .map(\.symbolName)
                .reduce(into: [String]()) { result, symbolName in
                    guard !result.contains(symbolName) else {
                        return
                    }

                    result.append(symbolName)
                }

            return MonthActivityDay(
                date: date,
                day: day,
                symbolNames: Array(symbolNames.prefix(4)),
                workouts: sortedWorkouts
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func makeWeeklyDistanceRows(
        workouts: [TrackedWorkout],
        calendar: Calendar,
        now: Date,
        language: AppLanguage
    ) -> [WeeklyDistanceRow] {
        let weekCalendar = sportsCareerWeekCalendar(from: calendar)

        guard let weekInterval = weekCalendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = "E"

        return (0..<7).compactMap { dayOffset in
            guard let date = weekCalendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start) else {
                return nil
            }

            let dayWorkouts = workouts.filter { workout in
                weekCalendar.isDate(workout.startDate, inSameDayAs: date)
            }

            return WeeklyDistanceRow(
                index: dayOffset,
                date: date,
                title: formatter.string(from: date),
                distanceMeters: dayWorkouts.reduce(0) { $0 + $1.distanceMeters },
                durationSeconds: dayWorkouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
            )
        }
    }

    private static func makeSportDistributionSlices(from rows: [SportRow]) -> [SportDistributionSlice] {
        let positiveRows = rows.filter { $0.distanceMeters > 0 }
        let sourceRows = positiveRows.isEmpty ? rows.filter { $0.count > 0 } : positiveRows

        return sourceRows.enumerated().map { index, row in
            SportDistributionSlice(
                title: row.title,
                value: positiveRows.isEmpty ? Double(row.count) : row.distanceMeters,
                color: Self.sportDistributionColor(at: index)
            )
        }
    }

    private static func sportDistributionColor(at index: Int) -> Color {
        let colors: [UIColor] = [
            AppColors.movinnGreen,
            UIColor(red: 42 / 255, green: 157 / 255, blue: 143 / 255, alpha: 1),
            UIColor(red: 69 / 255, green: 123 / 255, blue: 157 / 255, alpha: 1),
            UIColor(red: 233 / 255, green: 196 / 255, blue: 106 / 255, alpha: 1),
            UIColor(red: 231 / 255, green: 111 / 255, blue: 81 / 255, alpha: 1),
            UIColor(red: 128 / 255, green: 106 / 255, blue: 187 / 255, alpha: 1),
            UIColor(red: 244 / 255, green: 162 / 255, blue: 97 / 255, alpha: 1),
            UIColor(red: 38 / 255, green: 70 / 255, blue: 83 / 255, alpha: 1)
        ]
        return Color(uiColor: colors[index % colors.count])
    }

    private static func sportTitle(
        for sportKind: TrackedWorkoutSportKind,
        language: AppLanguage
    ) -> String {
        let textKey: AppTextKey
        switch sportKind {
        case .cycling:
            textKey = .cycling
        case .hiking:
            textKey = .hiking
        case .outdoorSwimming:
            textKey = .outdoorSwimming
        case .outdoorWorkout:
            textKey = .outdoorWorkout
        case .running:
            textKey = .running
        case .trailRunning:
            textKey = .trailRunning
        case .virtualCycling:
            textKey = .virtualCycling
        case .virtualRunning:
            textKey = .virtualRunning
        case .walking:
            textKey = .walking
        }

        return AppLocalization.text(textKey, language: language)
    }

    private static func makeLocationSummary(
        from workouts: [TrackedWorkout],
        language: AppLanguage
    ) -> LocationSummary {
        var countryNamesByIdentifier: [String: String] = [:]
        var chinaCityNamesByIdentifier: [String: String] = [:]
        var worldHighlightedIdentifiers = Set<String>()
        var chinaHighlightedIdentifiers = Set<String>()
        let regionManager = CoordinateRegionManager.shared

        for workout in workouts where !isVirtualWorkout(workout) {
            for coordinate in routeEndpointCoordinates(for: workout) {
                guard let region = regionManager.region(for: coordinate, language: language) else {
                    continue
                }

                addLocationIdentifiers(
                    [
                        region.countryCode,
                        region.countryName,
                        region.countryCode == "CN" ? "China" : nil
                    ],
                    to: &worldHighlightedIdentifiers
                )

                if let countryName = normalizedDisplayName(region.countryName),
                   let key = normalizedIdentifier(region.countryCode ?? countryName) {
                    countryNamesByIdentifier[key] = countryName
                }

                guard region.isChina else {
                    continue
                }

                let chinaRegion = regionManager.region(for: coordinate, language: .chinese) ?? region
                let chinaCityName = normalizedDisplayName(chinaRegion.cityName)
                    ?? normalizedDisplayName(chinaRegion.provinceName)
                guard let chinaCityName else {
                    continue
                }

                addLocationIdentifiers(
                    [
                        chinaRegion.cityName,
                        chinaRegion.provinceName,
                        chinaRegion.adcode.map { String($0) }
                    ],
                    to: &chinaHighlightedIdentifiers
                )

                if let key = normalizedIdentifier(chinaCityName) {
                    chinaCityNamesByIdentifier[key] = chinaCityName
                }
            }
        }

        return LocationSummary(
            countryNames: countryNamesByIdentifier.values.sorted(),
            chinaCityNames: chinaCityNamesByIdentifier.values.sorted(),
            worldHighlightedIdentifiers: worldHighlightedIdentifiers,
            chinaHighlightedIdentifiers: chinaHighlightedIdentifiers
        )
    }

    private static func routeEndpointCoordinates(for workout: TrackedWorkout) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []

        if let startCoordinate = workout.coordinates.first?.coordinate,
           CLLocationCoordinate2DIsValid(startCoordinate) {
            coordinates.append(startCoordinate)
        }

        if let endCoordinate = workout.coordinates.last?.coordinate,
           CLLocationCoordinate2DIsValid(endCoordinate),
           !coordinates.contains(where: { isSameCoordinate($0, endCoordinate) }) {
            coordinates.append(endCoordinate)
        }

        return coordinates
    }

    private static func isSameCoordinate(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    private static func isVirtualWorkout(_ workout: TrackedWorkout) -> Bool {
        workout.sportKind == .virtualCycling || workout.sportKind == .virtualRunning
    }

    private static func addLocationIdentifiers(
        _ values: [String?],
        to identifiers: inout Set<String>
    ) {
        values.forEach { value in
            guard let identifier = normalizedIdentifier(value) else {
                return
            }

            identifiers.insert(identifier)
        }
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty,
              normalizedIdentifier(trimmedValue) != nil else {
            return nil
        }

        return trimmedValue
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedValue,
              !normalizedValue.isEmpty,
              normalizedValue != "-99" else {
            return nil
        }

        return normalizedValue
    }
}

private func careerSummaryDistanceText(_ value: Double) -> String {
    "\(Int((value / 1_000).rounded())) km"
}

private func careerSummaryDurationText(_ value: Double) -> String {
    AppLocalization.format(.durationHoursFormat, max(Int(value / 3_600), 0))
}

private func careerDurationText(_ value: Double) -> String {
    AppLocalization.format(.durationHoursFormat, max(Int(value / 3_600), 0))
}

private func careerTotalKilometerText(_ value: Double) -> String {
    String(format: "%.1f km", max(value, 0) / 1_000)
}

private func careerOverviewDistanceText(_ value: Double) -> String {
    if value >= 1_000 {
        return "\(Int((value / 1_000).rounded())) km"
    }

    if value > 0 {
        return AppLocalization.format(.distanceMetersFormat, value)
    }

    return AppLocalization.text(.unknownDistance)
}

private func careerOverviewDistanceAttributedText(_ value: Double) -> NSAttributedString {
    careerEmphasizedNumberText(
        careerOverviewDistanceText(value),
        numberFont: .systemFont(ofSize: 16, weight: .bold),
        unitFont: .systemFont(ofSize: 11, weight: .semibold),
        color: .black
    )
}

private func careerOverviewDurationAttributedText(_ value: Double) -> NSAttributedString {
    careerEmphasizedNumberText(
        careerDurationText(value),
        numberFont: .systemFont(ofSize: 15, weight: .bold),
        unitFont: .systemFont(ofSize: 11, weight: .semibold),
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

private final class CareerLoadingView: UIView {
    private let activityIndicatorView = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func show() {
        isHidden = false
        activityIndicatorView.startAnimating()
    }

    func hide() {
        isHidden = true
        activityIndicatorView.stopAnimating()
    }

    private func configureViews() {
        backgroundColor = .clear
        isHidden = true
        activityIndicatorView.color = UIColor.black.withAlphaComponent(0.38)

        addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
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
    private let loadingView = CareerLoadingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(statistics: SportsCareerStatistics) {
        stackView.isHidden = false
        loadingView.hide()
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

    func configureLoading() {
        stackView.isHidden = true
        loadingView.show()
    }

    func animateValuesFromZero(duration: TimeInterval) {
        guard !stackView.isHidden else {
            return
        }

        totalDistanceView.animateValueFromZero(duration: duration)
        totalCountView.animateValueFromZero(duration: duration)
        totalDurationView.animateValueFromZero(duration: duration)
    }

    func animateValues(
        from previousStatistics: SportsCareerStatistics,
        to statistics: SportsCareerStatistics,
        duration: TimeInterval
    ) {
        guard !stackView.isHidden else {
            return
        }

        totalDistanceView.animateValue(
            from: previousStatistics.totalDistanceMeters,
            to: statistics.totalDistanceMeters,
            duration: duration
        )
        totalCountView.animateValue(
            from: Double(previousStatistics.totalCount),
            to: Double(statistics.totalCount),
            duration: duration
        )
        totalDurationView.animateValue(
            from: previousStatistics.totalDurationSeconds,
            to: statistics.totalDurationSeconds,
            duration: duration
        )
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
        contentView.addSubview(loadingView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        loadingView.snp.makeConstraints { make in
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

    func animateValue(from startValue: Double, to endValue: Double, duration: TimeInterval) {
        valueLabel.animate(from: startValue, to: endValue, duration: duration)
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
            make.top.equalToSuperview().offset(16)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(32)
        }
    }
}

private final class CareerAnnualCurveCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerAnnualCurveCell"

    private let curveView = CareerAnnualCurveView()
    private let loadingView = CareerLoadingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(series: [SportsCareerStatistics.AnnualDurationSeries]) {
        curveView.isHidden = false
        loadingView.hide()
        curveView.configure(series: series)
    }

    func configureLoading() {
        curveView.isHidden = true
        curveView.configure(series: [])
        loadingView.show()
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        contentView.addSubview(curveView)
        contentView.addSubview(loadingView)
        curveView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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
        let maxValue: Double
    }

    private var series: [SportsCareerStatistics.AnnualDurationSeries] = []
    private var selection: CurveSelection?
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    private let yearLabelWidth: CGFloat = 74
    private var lastRenderedSize: CGSize = .zero
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
        contentMode = .redraw
        addGestureRecognizer(selectionPanGestureRecognizer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        contentMode = .redraw
        addGestureRecognizer(selectionPanGestureRecognizer)
    }

    func configure(series: [SportsCareerStatistics.AnnualDurationSeries]) {
        self.series = series
        selection = nil
        lastRenderedSize = .zero
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard lastRenderedSize != bounds.size else {
            return
        }

        lastRenderedSize = bounds.size
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
        let yearMetricParagraphStyle = NSMutableParagraphStyle()
        yearMetricParagraphStyle.lineSpacing = 1
        let yearMetricAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.black.withAlphaComponent(0.38),
            .paragraphStyle: yearMetricParagraphStyle
        ]

        for (seriesIndex, item) in series.enumerated() {
            let rowMinY = layout.chartRect.minY + CGFloat(seriesIndex) * layout.rowHeight
            let baselineY = rowMinY + layout.rowHeight * 0.78
            let amplitude = layout.rowHeight * 0.66
            let values = Array(item.weeklyDistanceMeters.prefix(item.visibleWeekCount))
            let xDenominator = CGFloat(max(item.weeklyDistanceMeters.count - 1, 1))

            let yearText = "\(item.year)" as NSString
            let yearSize = yearText.size(withAttributes: yearAttributes)
            yearText.draw(
                at: CGPoint(
                    x: rect.minX,
                    y: rowMinY + 8
                ),
                withAttributes: yearAttributes
            )
            let metricText = "\(careerSummaryDistanceText(item.totalDistanceMeters))\n\(careerSummaryDurationText(item.totalDurationSeconds))" as NSString
            metricText.draw(
                with: CGRect(
                    x: rect.minX,
                    y: rowMinY + yearSize.height + 10,
                    width: yearLabelWidth - 6,
                    height: 34
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: yearMetricAttributes,
                context: nil
            )

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
            Array(item.weeklyDistanceMeters.prefix(item.visibleWeekCount))
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
        let denominator = CGFloat(max(item.weeklyDistanceMeters.count - 1, 1))
        let weekOffset = ((point.x - layout.chartRect.minX) / layout.chartRect.width) * denominator
        let weekIndex = min(max(Int(weekOffset.rounded()), 0), maxWeekIndex)

        return CurveSelection(seriesIndex: seriesIndex, weekIndex: weekIndex)
    }

    private func xPosition(
        for weekIndex: Int,
        item: SportsCareerStatistics.AnnualDurationSeries,
        layout: CurveLayout
    ) -> CGFloat {
        let denominator = CGFloat(max(item.weeklyDistanceMeters.count - 1, 1))
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

private final class CareerMonthCalendarCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "CareerMonthCalendarCell"

    private struct DayItem {
        let date: Date
        let day: Int
        let isCurrentMonth: Bool
        let symbolNames: [String]
        let workouts: [TrackedWorkout]
    }

    var onSelectDayWorkouts: ((Date, [TrackedWorkout]) -> Void)?

    private let pageContainerView = UIView()
    private let loadingView = CareerLoadingView()
    private var pageContentView: UIView?
    private var interactiveTargetContentView: UIView?
    private var interactiveTargetMonthDate: Date?
    private var interactiveTargetOffset: Int?
    private var activitySymbolsByDateKey: [String: [String]] = [:]
    private var activityWorkoutsByDateKey: [String: [TrackedWorkout]] = [:]
    private var displayedMonthDate = Date()
    private var calendar = Calendar.current
    private var hasConfiguredMonth = false
    private lazy var monthPanGestureRecognizer: UIPanGestureRecognizer = {
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleMonthPan(_:)))
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

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
        onSelectDayWorkouts = nil
    }

    func configure(days: [SportsCareerStatistics.MonthActivityDay], monthDate: Date) {
        pageContainerView.isHidden = false
        monthPanGestureRecognizer.isEnabled = true
        loadingView.hide()

        calendar = sportsCareerWeekCalendar(from: .current)
        calendar.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)

        activitySymbolsByDateKey = Dictionary(uniqueKeysWithValues: days.map { day in
            (dateKey(for: day.date), day.symbolNames)
        })
        activityWorkoutsByDateKey = Dictionary(uniqueKeysWithValues: days.map { day in
            (dateKey(for: day.date), day.workouts)
        })

        if !hasConfiguredMonth {
            displayedMonthDate = Self.startOfMonth(for: monthDate, calendar: calendar)
            hasConfiguredMonth = true
        }

        reloadMonth()
    }

    func configureLoading() {
        onSelectDayWorkouts = nil
        pageContainerView.isHidden = true
        monthPanGestureRecognizer.isEnabled = false
        loadingView.show()
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        pageContainerView.clipsToBounds = true

        contentView.addSubview(pageContainerView)
        contentView.addSubview(loadingView)
        contentView.addGestureRecognizer(monthPanGestureRecognizer)

        pageContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func makeMonthPageView(for monthDate: Date) -> UIView {
        let pageView = UIView()
        let monthLabel = UILabel()
        let summaryLabel = UILabel()
        let weekdayStackView = makeWeekdayStackView()
        let gridStackView = makeDayGridStackView(for: monthDate)
        let metrics = monthMetrics(for: monthDate)

        monthLabel.text = monthTitle(for: monthDate)
        monthLabel.textColor = .black
        monthLabel.font = .systemFont(ofSize: 18, weight: .bold)
        monthLabel.adjustsFontSizeToFitWidth = true
        monthLabel.minimumScaleFactor = 0.7

        summaryLabel.text = "\(careerTotalKilometerText(metrics.distanceMeters))\n\(careerDurationText(metrics.durationSeconds))"
        summaryLabel.textColor = .black
        summaryLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        summaryLabel.numberOfLines = 2
        summaryLabel.textAlignment = .right
        summaryLabel.adjustsFontSizeToFitWidth = true
        summaryLabel.minimumScaleFactor = 0.72

        pageView.addSubview(monthLabel)
        pageView.addSubview(summaryLabel)
        pageView.addSubview(weekdayStackView)
        pageView.addSubview(gridStackView)

        monthLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(summaryLabel.snp.leading).offset(-10)
            make.height.equalTo(24)
        }

        summaryLabel.snp.makeConstraints { make in
            make.centerY.equalTo(monthLabel)
            make.trailing.equalToSuperview().inset(16)
            make.width.equalTo(116)
        }

        weekdayStackView.snp.makeConstraints { make in
            make.top.equalTo(monthLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(18)
        }

        gridStackView.snp.makeConstraints { make in
            make.top.equalTo(weekdayStackView.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(12)
        }

        return pageView
    }

    private func monthMetrics(for monthDate: Date) -> (distanceMeters: Double, durationSeconds: TimeInterval) {
        let monthStartDate = Self.startOfMonth(for: monthDate, calendar: calendar)
        guard let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: monthStartDate) else {
            return (0, 0)
        }

        let workouts = activityWorkoutsByDateKey.values
            .flatMap { $0 }
            .filter { workout in
                workout.startDate >= monthStartDate && workout.startDate < nextMonthDate
            }

        return (
            workouts.reduce(0) { $0 + $1.distanceMeters },
            workouts.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        )
    }

    private func makeWeekdayStackView() -> UIStackView {
        let weekdayStackView = UIStackView()
        weekdayStackView.axis = .horizontal
        weekdayStackView.distribution = .fillEqually
        weekdayStackView.alignment = .fill
        weekdayStackView.spacing = 4

        let weekdaySymbols = reorderedWeekdaySymbols()
        for text in weekdaySymbols {
            let label = UILabel()
            label.text = text
            label.textColor = UIColor.black.withAlphaComponent(0.42)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textAlignment = .center
            weekdayStackView.addArrangedSubview(label)
        }

        return weekdayStackView
    }

    private func makeDayGridStackView(for monthDate: Date) -> UIStackView {
        let gridStackView = UIStackView()
        gridStackView.axis = .vertical
        gridStackView.distribution = .fillEqually
        gridStackView.alignment = .fill
        gridStackView.spacing = 2

        let items = makeDayItems(for: monthDate)
        var itemIndex = 0

        for _ in 0..<6 {
            let rowStackView = UIStackView()
            rowStackView.axis = .horizontal
            rowStackView.distribution = .fillEqually
            rowStackView.alignment = .fill
            rowStackView.spacing = 4
            gridStackView.addArrangedSubview(rowStackView)

            for _ in 0..<7 {
                let dayView = CareerCalendarDayView()
                if items.indices.contains(itemIndex) {
                    configure(dayView, with: items[itemIndex])
                }
                itemIndex += 1
                rowStackView.addArrangedSubview(dayView)
            }
        }

        return gridStackView
    }

    private func reloadMonth() {
        let pageView = makeMonthPageView(for: displayedMonthDate)
        installPageView(pageView)
    }

    private func installPageView(_ pageView: UIView) {
        pageContentView?.removeFromSuperview()
        pageContentView = pageView
        pageContainerView.addSubview(pageView)
        pageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configure(_ dayView: CareerCalendarDayView, with item: DayItem) {
        let startOfToday = calendar.startOfDay(for: Date())
        dayView.configure(
            day: item.day,
            isCurrentMonth: item.isCurrentMonth,
            isToday: calendar.isDateInToday(item.date),
            isPast: item.date < startOfToday,
            symbolNames: item.symbolNames
        )
        dayView.onTap = { [weak self] in
            guard !item.workouts.isEmpty else {
                return
            }

            self?.onSelectDayWorkouts?(item.date, item.workouts)
        }
    }

    private func makeDayItems(for monthDate: Date) -> [DayItem] {
        let monthStartDate = Self.startOfMonth(for: monthDate, calendar: calendar)
        let dayRange = calendar.range(of: .day, in: .month, for: monthStartDate) ?? 1..<1
        let weekday = calendar.component(.weekday, from: monthStartDate)
        let leadingEmptyCount = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = dayRange.count

        return (0..<42).map { index in
            let dayOffset = index - leadingEmptyCount
            let date = calendar.date(byAdding: .day, value: dayOffset, to: monthStartDate) ?? monthStartDate
            let isCurrentMonth = dayOffset >= 0 && dayOffset < dayCount

            let symbolNames = activitySymbolsByDateKey[dateKey(for: date)] ?? []
            let workouts = activityWorkoutsByDateKey[dateKey(for: date)] ?? []
            return DayItem(
                date: date,
                day: calendar.component(.day, from: date),
                isCurrentMonth: isCurrentMonth,
                symbolNames: symbolNames,
                workouts: workouts
            )
        }
    }

    private func reorderedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.calendar = calendar
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else {
            return ["日", "一", "二", "三", "四", "五", "六"]
        }

        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return formatter.string(from: date)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === monthPanGestureRecognizer else {
            return true
        }

        let velocity = monthPanGestureRecognizer.velocity(in: contentView)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handleMonthPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            pageContainerView.layoutIfNeeded()
        case .changed:
            updateInteractiveMonthTransition(translationX: gestureRecognizer.translation(in: contentView).x)
        case .ended:
            finishInteractiveMonthTransition(
                translationX: gestureRecognizer.translation(in: contentView).x,
                velocityX: gestureRecognizer.velocity(in: contentView).x
            )
        case .cancelled, .failed:
            cancelInteractiveMonthTransition()
        default:
            break
        }
    }

    private func updateInteractiveMonthTransition(translationX: CGFloat) {
        let width = max(pageContainerView.bounds.width, 1)
        guard abs(translationX) > 1 else {
            pageContentView?.transform = .identity
            interactiveTargetContentView?.transform = .identity
            return
        }

        let offset = translationX < 0 ? 1 : -1
        prepareInteractiveMonthTransitionIfNeeded(offset: offset)

        let clampedTranslationX = min(max(translationX, -width), width)
        pageContentView?.transform = CGAffineTransform(translationX: clampedTranslationX, y: 0)
        let incomingStartX = offset > 0 ? width : -width
        interactiveTargetContentView?.transform = CGAffineTransform(
            translationX: incomingStartX + clampedTranslationX,
            y: 0
        )
    }

    private func prepareInteractiveMonthTransitionIfNeeded(offset: Int) {
        guard interactiveTargetOffset != offset else {
            return
        }

        interactiveTargetContentView?.removeFromSuperview()
        interactiveTargetContentView = nil
        interactiveTargetMonthDate = nil
        interactiveTargetOffset = nil

        guard let date = calendar.date(byAdding: .month, value: offset, to: displayedMonthDate) else {
            return
        }

        let targetMonthDate = Self.startOfMonth(for: date, calendar: calendar)
        let targetContentView = makeMonthPageView(for: targetMonthDate)
        pageContainerView.addSubview(targetContentView)
        targetContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        pageContainerView.layoutIfNeeded()

        let width = max(pageContainerView.bounds.width, 1)
        targetContentView.transform = CGAffineTransform(translationX: offset > 0 ? width : -width, y: 0)
        interactiveTargetContentView = targetContentView
        interactiveTargetMonthDate = targetMonthDate
        interactiveTargetOffset = offset
    }

    private func finishInteractiveMonthTransition(translationX: CGFloat, velocityX: CGFloat) {
        guard let targetContentView = interactiveTargetContentView,
              let targetMonthDate = interactiveTargetMonthDate,
              let targetOffset = interactiveTargetOffset else {
            return
        }

        let width = max(pageContainerView.bounds.width, 1)
        let progress = min(abs(translationX) / width, 1)
        let shouldFinish = progress > 0.32 || abs(velocityX) > 520

        if shouldFinish {
            let outgoingX = targetOffset > 0 ? -width : width
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.pageContentView?.transform = CGAffineTransform(translationX: outgoingX, y: 0)
                targetContentView.transform = .identity
            } completion: { _ in
                self.displayedMonthDate = targetMonthDate
                self.pageContentView?.removeFromSuperview()
                self.pageContentView = targetContentView
                self.clearInteractiveMonthTransition(keepingTarget: true)
            }
        } else {
            cancelInteractiveMonthTransition()
        }
    }

    private func cancelInteractiveMonthTransition() {
        guard let targetContentView = interactiveTargetContentView,
              let targetOffset = interactiveTargetOffset else {
            pageContentView?.transform = .identity
            return
        }

        let width = max(pageContainerView.bounds.width, 1)
        let targetX = targetOffset > 0 ? width : -width
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.pageContentView?.transform = .identity
            targetContentView.transform = CGAffineTransform(translationX: targetX, y: 0)
        } completion: { _ in
            self.clearInteractiveMonthTransition(keepingTarget: false)
        }
    }

    private func clearInteractiveMonthTransition(keepingTarget: Bool) {
        pageContentView?.transform = .identity
        if !keepingTarget {
            interactiveTargetContentView?.removeFromSuperview()
        }
        interactiveTargetContentView = nil
        interactiveTargetMonthDate = nil
        interactiveTargetOffset = nil
    }

    private func dateKey(for date: Date) -> String {
        Self.dateKey(for: calendar.dateComponents([.year, .month, .day], from: date))
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

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

private final class CareerCalendarDayView: UIView {
    private let circleView = UIView()
    private let dayLabel = UILabel()
    private let iconStackView = UIStackView()
    var onTap: (() -> Void)?
    private lazy var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(
        day: Int,
        isCurrentMonth: Bool,
        isToday: Bool,
        isPast: Bool,
        symbolNames: [String]
    ) {
        let hasWorkout = !symbolNames.isEmpty
        isUserInteractionEnabled = hasWorkout
        dayLabel.text = "\(day)"
        dayLabel.isHidden = hasWorkout
        iconStackView.isHidden = !hasWorkout

        if isToday {
            dayLabel.textColor = .black
        } else if !isCurrentMonth {
            dayLabel.textColor = UIColor.black.withAlphaComponent(0.24)
        } else if isPast {
            dayLabel.textColor = UIColor.black.withAlphaComponent(0.48)
        } else {
            dayLabel.textColor = .black
        }

        circleView.layer.borderColor = isToday ? UIColor.black.cgColor : UIColor.clear.cgColor
        configureIcons(
            symbolNames: symbolNames,
            tintColor: AppColors.movinnGreen
        )
    }

    @objc private func handleTap() {
        onTap?()
    }

    private func configureIcons(symbolNames: [String], tintColor: UIColor) {
        iconStackView.arrangedSubviews.forEach { view in
            iconStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let limitedSymbolNames = Array(symbolNames.prefix(4))
        let pointSize: CGFloat = limitedSymbolNames.count == 1 ? 15 : 12

        for symbolName in limitedSymbolNames {
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            let imageView = UIImageView(
                image: UIImage(systemName: symbolName, withConfiguration: configuration)
                    ?? UIImage(systemName: "figure.walk", withConfiguration: configuration)
            )
            imageView.tintColor = tintColor
            imageView.contentMode = .scaleAspectFit
            iconStackView.addArrangedSubview(imageView)
        }
    }

    private func configureViews() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        circleView.backgroundColor = .clear
        circleView.layer.borderWidth = 1.5
        circleView.layer.borderColor = UIColor.clear.cgColor

        dayLabel.textColor = .black
        dayLabel.font = .systemFont(ofSize: 16, weight: .medium)
        dayLabel.textAlignment = .center

        iconStackView.axis = .horizontal
        iconStackView.alignment = .fill
        iconStackView.distribution = .fillEqually
        iconStackView.spacing = 0

        addSubview(circleView)
        circleView.addSubview(dayLabel)
        circleView.addSubview(iconStackView)
        addGestureRecognizer(tapGestureRecognizer)

        circleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGSize(width: 32, height: 32))
        }

        dayLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleView.layer.cornerRadius = min(circleView.bounds.width, circleView.bounds.height) / 2
    }
}

private final class CareerWeeklyChartCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerWeeklyChartCell"

    private let hostingView = CareerChartHostingView()
    private let loadingView = CareerLoadingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(rows: [SportsCareerStatistics.WeeklyDistanceRow]) {
        hostingView.isHidden = false
        loadingView.hide()
        hostingView.setContent(CareerWeeklyDistanceChart(rows: rows))
    }

    func configureLoading() {
        hostingView.isHidden = true
        loadingView.show()
    }

    private func configureViews() {
        contentView.backgroundColor = UIColor(white: 0.965, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        contentView.addSubview(hostingView)
        contentView.addSubview(loadingView)
        hostingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

private final class CareerSportOverviewCell: UICollectionViewCell {
    static let reuseIdentifier = "CareerSportOverviewCell"

    private let hostingView = CareerChartHostingView()
    private let locationOverviewView = CareerLocationOverviewView()
    private let sportTypeGridView = CareerSportTypeGridView()
    private let loadingView = CareerLoadingView()
    private var locationHeightConstraint: Constraint?

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
        slices: [SportsCareerStatistics.SportDistributionSlice],
        locationSummary: SportsCareerStatistics.LocationSummary,
        locationHeight: CGFloat
    ) {
        hostingView.isHidden = false
        sportTypeGridView.isHidden = false
        loadingView.hide()
        hostingView.setContent(CareerSportDistributionChart(slices: slices))
        locationOverviewView.isHidden = locationSummary.isEmpty
        if !locationSummary.isEmpty {
            locationOverviewView.configure(summary: locationSummary)
        }
        locationHeightConstraint?.update(offset: locationHeight)
        sportTypeGridView.configure(rows: rows)
        remakeSportGridConstraints(hasLocation: !locationSummary.isEmpty)
    }

    func configureLoading() {
        hostingView.isHidden = true
        locationOverviewView.isHidden = true
        sportTypeGridView.isHidden = true
        locationHeightConstraint?.update(offset: 0)
        remakeSportGridConstraints(hasLocation: false)
        loadingView.show()
    }

    func animateValuesFromZero(duration: TimeInterval) {
        guard !sportTypeGridView.isHidden else {
            return
        }

        sportTypeGridView.animateValuesFromZero(duration: duration)
    }

    private func configureViews() {
        contentView.backgroundColor = .clear

        contentView.addSubview(hostingView)
        contentView.addSubview(locationOverviewView)
        contentView.addSubview(sportTypeGridView)
        contentView.addSubview(loadingView)

        hostingView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(222)
        }

        locationOverviewView.snp.makeConstraints { make in
            make.top.equalTo(hostingView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            locationHeightConstraint = make.height.equalTo(0).constraint
        }

        remakeSportGridConstraints(hasLocation: false)

        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func remakeSportGridConstraints(hasLocation: Bool) {
        sportTypeGridView.snp.remakeConstraints { make in
            if hasLocation {
                make.top.equalTo(locationOverviewView.snp.bottom).offset(16)
            } else {
                make.top.equalTo(hostingView.snp.bottom).offset(16)
            }
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

private final class CareerLocationOverviewView: UIView {
    private static let cardSpacing: CGFloat = 14

    private let mapStackView = UIStackView()
    private let worldMapCardView = CareerLocationMapCardView()
    private let chinaMapCardView = CareerLocationMapCardView()
    private var summary: SportsCareerStatistics.LocationSummary?
    private var worldMapCardHeightConstraint: Constraint?
    private var chinaMapCardHeightConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    static func height(
        for summary: SportsCareerStatistics.LocationSummary,
        width: CGFloat
    ) -> CGFloat {
        guard !summary.isEmpty else {
            return 0
        }

        let worldHeight = CareerLocationMapCardView.height(
            detail: summary.countryNames.joined(separator: "、"),
            width: width,
            mapHeight: CareerLocationMapCardView.worldMapHeight
        )
        guard summary.hasChinaMap else {
            return worldHeight
        }

        let chinaHeight = CareerLocationMapCardView.height(
            detail: summary.chinaCityNames.joined(separator: "、"),
            width: width,
            mapHeight: CareerLocationMapCardView.chinaMapHeight
        )
        return worldHeight + cardSpacing + chinaHeight
    }

    func configure(summary: SportsCareerStatistics.LocationSummary) {
        self.summary = summary
        worldMapCardView.configure(
            detail: summary.countryNames.joined(separator: "、"),
            mapHeight: CareerLocationMapCardView.worldMapHeight,
            scope: .world,
            highlightedIdentifiers: summary.worldHighlightedIdentifiers
        )
        chinaMapCardView.configure(
            detail: summary.chinaCityNames.joined(separator: "、"),
            mapHeight: CareerLocationMapCardView.chinaMapHeight,
            scope: .china,
            highlightedIdentifiers: summary.chinaHighlightedIdentifiers
        )
        chinaMapCardView.isHidden = !summary.hasChinaMap
        updateCardHeights()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCardHeights()
    }

    private func configureViews() {
        mapStackView.axis = .vertical
        mapStackView.alignment = .fill
        mapStackView.distribution = .fill
        mapStackView.spacing = Self.cardSpacing

        addSubview(mapStackView)

        mapStackView.addArrangedSubview(worldMapCardView)
        worldMapCardView.snp.makeConstraints { make in
            worldMapCardHeightConstraint = make.height.equalTo(0).constraint
        }

        mapStackView.addArrangedSubview(chinaMapCardView)
        chinaMapCardView.snp.makeConstraints { make in
            chinaMapCardHeightConstraint = make.height.equalTo(0).constraint
        }

        mapStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func updateCardHeights() {
        guard let summary,
              bounds.width > 0 else {
            return
        }

        let worldHeight = CareerLocationMapCardView.height(
            detail: summary.countryNames.joined(separator: "、"),
            width: bounds.width,
            mapHeight: CareerLocationMapCardView.worldMapHeight
        )
        worldMapCardHeightConstraint?.update(offset: worldHeight)

        let chinaHeight = summary.hasChinaMap
            ? CareerLocationMapCardView.height(
                detail: summary.chinaCityNames.joined(separator: "、"),
                width: bounds.width,
                mapHeight: CareerLocationMapCardView.chinaMapHeight
            )
            : 0
        chinaMapCardHeightConstraint?.update(offset: chinaHeight)
    }
}

private final class CareerLocationMapCardView: UIView {
    static let worldMapHeight: CGFloat = 168
    static let chinaMapHeight: CGFloat = 260

    private static let horizontalInset: CGFloat = 12
    private static let topInset: CGFloat = 12
    private static let mapDetailSpacing: CGFloat = 10
    private static let bottomInset: CGFloat = 12
    private static let detailFont = UIFont.systemFont(ofSize: 10, weight: .semibold)

    private let detailLabel = UILabel()
    private let mapView = CareerRegionMapView()
    private var mapHeightConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(
        detail: String,
        mapHeight: CGFloat,
        scope: CoordinateRegionMapScope,
        highlightedIdentifiers: Set<String>
    ) {
        detailLabel.text = detail
        mapHeightConstraint?.update(offset: mapHeight)
        mapView.configure(scope: scope, highlightedIdentifiers: highlightedIdentifiers)
    }

    static func height(
        detail: String,
        width: CGFloat,
        mapHeight: CGFloat
    ) -> CGFloat {
        let detailWidth = max(width - horizontalInset * 2, 1)
        let detailHeight = max(
            ceil(
                (detail as NSString).boundingRect(
                    with: CGSize(width: detailWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: detailFont],
                    context: nil
                ).height
            ),
            detailFont.lineHeight
        )

        return topInset
            + mapHeight
            + mapDetailSpacing
            + detailHeight
            + bottomInset
    }

    private func configureViews() {
        backgroundColor = UIColor(white: 0.965, alpha: 1)
        layer.cornerRadius = 8
        layer.masksToBounds = true

        detailLabel.textColor = UIColor.black.withAlphaComponent(0.45)
        detailLabel.font = Self.detailFont
        detailLabel.textAlignment = .left
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.numberOfLines = 0

        addSubview(mapView)
        addSubview(detailLabel)

        mapView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Self.topInset)
            make.leading.trailing.equalToSuperview().inset(Self.horizontalInset)
            mapHeightConstraint = make.height.equalTo(Self.worldMapHeight).constraint
        }

        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(mapView.snp.bottom).offset(Self.mapDetailSpacing)
            make.leading.trailing.equalToSuperview().inset(Self.horizontalInset)
            make.bottom.equalToSuperview().inset(Self.bottomInset)
        }
    }
}

private final class CareerRegionMapView: UIView {
    private struct DrawingBounds {
        let minLongitude: Double
        let minLatitude: Double
        let maxLongitude: Double
        let maxLatitude: Double

        nonisolated var width: Double {
            max(maxLongitude - minLongitude, 0)
        }

        nonisolated var height: Double {
            max(maxLatitude - minLatitude, 0)
        }
    }

    private let imageView = UIImageView()
    private let loadingView = CareerLoadingView()
    private var highlightedIdentifiers = Set<String>()
    private var scope: CoordinateRegionMapScope = .world
    private var renderToken = UUID()
    private var requestedRenderSize: CGSize = .zero
    private var requestedRenderScope: CoordinateRegionMapScope?
    private var requestedHighlightedIdentifiers = Set<String>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(scope: CoordinateRegionMapScope, highlightedIdentifiers: Set<String>) {
        let needsNewRender = self.scope != scope || self.highlightedIdentifiers != highlightedIdentifiers
        self.scope = scope
        self.highlightedIdentifiers = highlightedIdentifiers

        if needsNewRender {
            imageView.image = nil
            requestedRenderSize = .zero
        }

        if imageView.image == nil {
            loadingView.show()
        } else {
            loadingView.hide()
        }
        setNeedsLayout()
    }

    private func configureViews() {
        backgroundColor = .clear
        isOpaque = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear

        addSubview(imageView)
        addSubview(loadingView)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderMapIfNeeded()
    }

    private func renderMapIfNeeded() {
        let renderSize = bounds.size
        guard renderSize.width > 2,
              renderSize.height > 2 else {
            return
        }

        guard requestedRenderSize != renderSize
                || requestedRenderScope != scope
                || requestedHighlightedIdentifiers != highlightedIdentifiers else {
            return
        }

        let token = UUID()
        let targetScope = scope
        let targetHighlightedIdentifiers = highlightedIdentifiers
        let displayScale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        renderToken = token
        requestedRenderSize = renderSize
        requestedRenderScope = targetScope
        requestedHighlightedIdentifiers = targetHighlightedIdentifiers
        imageView.image = nil
        loadingView.show()

        DispatchQueue.global(qos: .userInitiated).async {
            let features = CoordinateRegionManager.shared.mapFeatures(for: targetScope)
            let image = Self.renderMapImage(
                scope: targetScope,
                features: features,
                highlightedIdentifiers: targetHighlightedIdentifiers,
                size: renderSize,
                scale: displayScale
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.renderToken == token,
                      self.scope == targetScope,
                      self.highlightedIdentifiers == targetHighlightedIdentifiers else {
                    return
                }

                self.imageView.image = image
                self.loadingView.hide()
            }
        }
    }

    nonisolated private static func renderMapImage(
        scope: CoordinateRegionMapScope,
        features: [CoordinateRegionMapFeature],
        highlightedIdentifiers: Set<String>,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            guard !features.isEmpty,
                  let bounds = drawingBounds(for: features, scope: scope),
                  bounds.width > 0,
                  bounds.height > 0 else {
                drawPlaceholder(in: rect)
                return
            }

            let targetRect = fittedRect(
                for: bounds,
                scope: scope,
                in: rect.insetBy(dx: 2, dy: 2)
            )
            let baseFillColor = UIColor.black.withAlphaComponent(0.075)
            let baseStrokeColor = UIColor.white.withAlphaComponent(0.95)
            let highlightedFillColor = UIColor(red: 141 / 255, green: 189 / 255, blue: 0, alpha: 1)
            let highlightedStrokeColor = UIColor.black.withAlphaComponent(0.18)

            for feature in features {
                let path = path(for: feature, bounds: bounds, targetRect: targetRect)
                guard !path.isEmpty else {
                    continue
                }

                let isHighlighted = !feature.identifiers.isDisjoint(with: highlightedIdentifiers)
                (isHighlighted ? highlightedFillColor : baseFillColor).setFill()
                path.fill()
                (isHighlighted ? highlightedStrokeColor : baseStrokeColor).setStroke()
                path.lineWidth = isHighlighted ? 0.55 : 0.35
                path.stroke()
            }
        }
    }

    nonisolated private static func drawPlaceholder(in rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 18), cornerRadius: 8)
        UIColor.black.withAlphaComponent(0.045).setFill()
        path.fill()
    }

    nonisolated private static func drawingBounds(
        for features: [CoordinateRegionMapFeature],
        scope: CoordinateRegionMapScope
    ) -> DrawingBounds? {
        guard let firstBounds = features.first?.bounds,
              firstBounds.isValid else {
            return nil
        }

        let bounds = features.dropFirst().reduce(
            DrawingBounds(
                minLongitude: firstBounds.minLongitude,
                minLatitude: firstBounds.minLatitude,
                maxLongitude: firstBounds.maxLongitude,
                maxLatitude: firstBounds.maxLatitude
            )
        ) { result, feature in
            DrawingBounds(
                minLongitude: min(result.minLongitude, feature.bounds.minLongitude),
                minLatitude: min(result.minLatitude, feature.bounds.minLatitude),
                maxLongitude: max(result.maxLongitude, feature.bounds.maxLongitude),
                maxLatitude: max(result.maxLatitude, feature.bounds.maxLatitude)
            )
        }

        switch scope {
        case .world:
            return bounds
        case .china:
            return DrawingBounds(
                minLongitude: bounds.minLongitude,
                minLatitude: max(bounds.minLatitude, 17.5),
                maxLongitude: bounds.maxLongitude,
                maxLatitude: bounds.maxLatitude
            )
        }
    }

    nonisolated private static func fittedRect(
        for bounds: DrawingBounds,
        scope: CoordinateRegionMapScope,
        in rect: CGRect
    ) -> CGRect {
        let mapAspectRatio = CGFloat(bounds.width / bounds.height)
        let rectAspectRatio = rect.width / max(rect.height, 1)
        let fittedRect: CGRect
        if mapAspectRatio > rectAspectRatio {
            let height = rect.width / max(mapAspectRatio, 0.1)
            fittedRect = CGRect(
                x: rect.minX,
                y: rect.midY - height / 2,
                width: rect.width,
                height: height
            )
        } else {
            let width = rect.height * mapAspectRatio
            fittedRect = CGRect(
                x: rect.midX - width / 2,
                y: rect.minY,
                width: width,
                height: rect.height
            )
        }

        switch scope {
        case .world:
            return fittedRect
        case .china:
            let expandedHeight = min(rect.height, max(fittedRect.height, rect.height * 0.96))
            return CGRect(
                x: fittedRect.minX,
                y: rect.midY - expandedHeight / 2,
                width: fittedRect.width,
                height: expandedHeight
            )
        }
    }

    nonisolated private static func path(
        for feature: CoordinateRegionMapFeature,
        bounds: DrawingBounds,
        targetRect: CGRect
    ) -> UIBezierPath {
        let path = UIBezierPath()
        for ring in feature.rings {
            let points = simplifiedCoordinates(ring)
            guard let firstCoordinate = points.first else {
                continue
            }

            path.move(to: projectedPoint(firstCoordinate, bounds: bounds, targetRect: targetRect))
            for coordinate in points.dropFirst() {
                path.addLine(to: projectedPoint(coordinate, bounds: bounds, targetRect: targetRect))
            }
            path.close()
        }

        return path
    }

    nonisolated private static func simplifiedCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let maxPointCount = 520
        guard coordinates.count > maxPointCount else {
            return coordinates
        }

        let stride = Int(ceil(Double(coordinates.count) / Double(maxPointCount)))
        var result = coordinates.enumerated().compactMap { index, coordinate in
            index % stride == 0 ? coordinate : nil
        }
        if let lastCoordinate = coordinates.last {
            let currentLastCoordinate = result.last
            if currentLastCoordinate == nil
                || currentLastCoordinate?.latitude != lastCoordinate.latitude
                || currentLastCoordinate?.longitude != lastCoordinate.longitude {
                result.append(lastCoordinate)
            }
        }
        return result
    }

    nonisolated private static func projectedPoint(
        _ coordinate: CLLocationCoordinate2D,
        bounds: DrawingBounds,
        targetRect: CGRect
    ) -> CGPoint {
        let xRatio = (coordinate.longitude - bounds.minLongitude) / max(bounds.width, 0.000_001)
        let yRatio = (coordinate.latitude - bounds.minLatitude) / max(bounds.height, 0.000_001)
        return CGPoint(
            x: targetRect.minX + CGFloat(xRatio) * targetRect.width,
            y: targetRect.maxY - CGFloat(yRatio) * targetRect.height
        )
    }
}

private struct CareerWeeklyDistanceChart: View {
    let rows: [SportsCareerStatistics.WeeklyDistanceRow]
    @State private var selectedDayIndex: Int?

    private var totalDistanceMeters: Double {
        rows.reduce(0) { $0 + $1.distanceMeters }
    }

    private var totalDurationSeconds: TimeInterval {
        rows.reduce(0) { $0 + $1.durationSeconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                summaryMetric(
                    title: AppLocalization.text(.totalWorkoutDistance),
                    value: careerTotalKilometerText(totalDistanceMeters),
                    valueColor: .black
                )
                summaryMetric(
                    title: AppLocalization.text(.totalWorkoutTime),
                    value: careerDurationText(totalDurationSeconds),
                    valueColor: .black
                )
                Spacer(minLength: 0)
            }

            Chart(rows) { row in
                BarMark(
                    x: .value("Day", row.title),
                    y: .value("Distance", row.distanceKilometers)
                )
                .foregroundStyle(
                    row.index == selectedDayIndex
                    ? Color(uiColor: AppColors.movinnGreen)
                    : Color(uiColor: AppColors.movinnGreen).opacity(0.76)
                )
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if let tooltip = selectedTooltip(proxy: proxy, geometry: geometry) {
                            Text(tooltip.text)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                )
                                .position(x: tooltip.x, y: tooltip.y)
                        }

                        CareerChartTapOverlay { location in
                            updateSelection(
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .onChange(of: selectedDayIndex) { _, newValue in
            guard newValue != nil else {
                return
            }

            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func summaryMetric(title: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private func selectedTooltip(
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> (text: String, x: CGFloat, y: CGFloat)? {
        guard let selectedDayIndex,
              let row = rows.first(where: { $0.index == selectedDayIndex }),
              let rowPosition = rows.firstIndex(where: { $0.index == selectedDayIndex }),
              let plotFrame = proxy.plotFrame else {
            return nil
        }

        let plotRect = geometry[plotFrame]
        let slotWidth = plotRect.width / CGFloat(max(rows.count, 1))
        let rawX = plotRect.minX + slotWidth * (CGFloat(rowPosition) + 0.5)
        let x = min(max(rawX, plotRect.minX + 34), plotRect.maxX - 34)
        let y = max(plotRect.minY + 14, 14)

        return (
            text: careerTotalKilometerText(row.distanceMeters),
            x: x,
            y: y
        )
    }

    private func updateSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard !rows.isEmpty,
              let plotFrame = proxy.plotFrame else {
            return
        }

        let plotRect = geometry[plotFrame]
        let xPosition = location.x - plotRect.minX
        guard xPosition >= 0, xPosition <= plotRect.width else {
            return
        }

        if let title = proxy.value(atX: xPosition, as: String.self),
           let row = rows.first(where: { $0.title == title }) {
            selectedDayIndex = row.index
            return
        }

        let fallbackIndex = min(
            max(Int((xPosition / max(plotRect.width, 1)) * CGFloat(rows.count)), 0),
            rows.count - 1
        )
        selectedDayIndex = rows[fallbackIndex].index
    }
}

private struct CareerChartTapOverlay: UIViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(tapGestureRecognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended,
                  let view = gestureRecognizer.view else {
                return
            }

            onTap(gestureRecognizer.location(in: view))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct CareerSportDistributionChart: View {
    let slices: [SportsCareerStatistics.SportDistributionSlice]

    private var totalValue: Double {
        slices.reduce(0) { $0 + max($1.value, 0) }
    }

    var body: some View {
        HStack(spacing: 14) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Value", max(slice.value, 0.01)),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.6
                )
                .foregroundStyle(slice.color)
                .annotation(position: .overlay) {
                    if percentage(for: slice) >= 0.05 {
                        Text(percentageText(for: slice))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.82))
                            )
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(width: 150)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        Text("\(slice.title) \(percentageText(for: slice))")
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

    private func percentage(for slice: SportsCareerStatistics.SportDistributionSlice) -> Double {
        guard totalValue > 0 else {
            return 0
        }

        return max(slice.value, 0) / totalValue
    }

    private func percentageText(for slice: SportsCareerStatistics.SportDistributionSlice) -> String {
        "\(Int((percentage(for: slice) * 100).rounded()))%"
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
            attributedFormatter: careerOverviewDistanceAttributedText
        )
        durationLabel.configure(
            finalValue: row.durationSeconds,
            attributedFormatter: careerOverviewDurationAttributedText
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

        distanceLabel.textColor = .black
        distanceLabel.font = .systemFont(ofSize: 16, weight: .bold)
        distanceLabel.textAlignment = .left
        distanceLabel.adjustsFontSizeToFitWidth = false

        durationLabel.textColor = .black
        durationLabel.font = .systemFont(ofSize: 15, weight: .bold)
        durationLabel.textAlignment = .left
        durationLabel.adjustsFontSizeToFitWidth = false

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
    private var animationStartValue: Double = 0

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
        animate(from: 0, to: finalValue, duration: duration)
    }

    func animate(from startValue: Double, to endValue: Double, duration: TimeInterval) {
        displayLink?.invalidate()
        finalValue = endValue
        animationStartValue = startValue
        animationDuration = duration
        animationStartTime = CACurrentMediaTime()
        updateDisplayedValue(startValue)

        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        let elapsedTime = displayLink.timestamp - animationStartTime
        let progress = min(max(elapsedTime / animationDuration, 0), 1)
        let easedProgress = 1 - pow(1 - progress, 3)
        updateDisplayedValue(animationStartValue + (finalValue - animationStartValue) * easedProgress)

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
