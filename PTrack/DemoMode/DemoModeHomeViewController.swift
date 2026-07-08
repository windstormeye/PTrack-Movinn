//
//  DemoModeHomeViewController.swift
//  PTrack
//
//  Created by Codex on 2026/7/8.
//

import SnapKit
import UIKit

final class DemoModeHomeViewController: UIViewController {
    private let workouts: [TrackedWorkout]
    private let routeGridView = WorkoutRouteGridView()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let titleAccentLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let defaultColumnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 22, right: 12)

    init(workouts: [TrackedWorkout]) {
        self.workouts = workouts
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureGridView()
        configureHeaderView()
        registerTraitChangeHandler()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        updateFullScreenInsets(force: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFullScreenInsets()
    }

    private func configureNavigationItem() {
        title = AppLocalization.text(.demoModeTitle)
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureGridView() {
        view.backgroundColor = .systemBackground
        routeGridView.configureLayout(
            columns: defaultColumnCount,
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            sectionInset: sectionInset
        )
        routeGridView.isPrefetchingEnabled = false
        routeGridView.numberOfItemsProvider = { [weak self] in
            self?.workouts.count ?? 0
        }
        routeGridView.itemProvider = { [weak self] index in
            guard let self,
                  workouts.indices.contains(index) else {
                return nil
            }

            return WorkoutRouteGridItem.route(
                workouts[index],
                showsMap: false,
                showsNewBadge: false
            )
        }
        routeGridView.onSelectRoute = { [weak self] workout, _, _ in
            self?.showWorkoutDetail(workout)
        }

        view.addSubview(routeGridView)
        routeGridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureHeaderView() {
        headerView.backgroundColor = AppColors.solidBackground

        let titleFont = UIFont.systemFont(ofSize: 40, weight: .bold)
        titleLabel.text = "Movin"
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        titleAccentLabel.text = "n"
        titleAccentLabel.font = titleFont
        titleAccentLabel.textColor = AppColors.movinnGreen
        titleAccentLabel.adjustsFontForContentSizeCategory = true

        totalDistanceLabel.textColor = .secondaryLabel
        totalDistanceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        totalDistanceLabel.adjustsFontForContentSizeCategory = true
        totalDistanceLabel.text = totalDistanceText()

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.image = UIImage(
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        moreButton.configuration = buttonConfiguration
        moreButton.tintColor = .label
        moreButton.menu = makeMoreMenu()
        moreButton.showsMenuAsPrimaryAction = true

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(titleAccentLabel)
        headerView.addSubview(totalDistanceLabel)
        headerView.addSubview(moreButton)

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(122)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
        }
        titleAccentLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(-1)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline)
        }
        totalDistanceLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleAccentLabel.snp.trailing).offset(10)
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-10)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline).offset(-3)
        }
        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(36)
        }
    }

    private func makeMoreMenu() -> UIMenu {
        let heatmapAction = UIAction(
            title: AppLocalization.text(.routeHeatmap),
            image: UIImage(systemName: "map")
        ) { [weak self] _ in
            self?.showHeatmap()
        }

        return UIMenu(children: [heatmapAction])
    }

    private func showWorkoutDetail(_ workout: TrackedWorkout) {
        let detailViewController = WorkoutRouteDetailViewController(
            workout: workout,
            mergeSourceWorkouts: workouts,
            isDemoMode: true
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func showHeatmap() {
        let heatmapViewController = WorkoutRouteHeatmapViewController(
            workouts: workouts,
            isDemoMode: true
        )
        navigationController?.pushViewController(heatmapViewController, animated: true)
    }

    private func totalDistanceText() -> String {
        let totalKilometers = workouts.reduce(0) { $0 + $1.distanceMeters } / 1_000
        let distanceText = AppLocalization.format(.totalDistanceFormat, Int(totalKilometers.rounded()))
        let activityCountText = AppLocalization.format(.totalActivityCountFormat, workouts.count)
        return "\(distanceText)/\(activityCountText)"
    }

    private func updateFullScreenInsets(force: Bool = false) {
        view.layoutIfNeeded()
        let headerMaxY = headerView.convert(headerView.bounds, to: view).maxY
        let contentInset = UIEdgeInsets(
            top: headerMaxY + headerBottomPadding,
            left: 0,
            bottom: 0,
            right: 0
        )
        let collectionView = routeGridView.collectionView
        guard force || collectionView.contentInset != contentInset else {
            return
        }

        let oldTopInset = collectionView.contentInset.top
        let oldContentOffsetY = collectionView.contentOffset.y
        let wasAtTop = oldContentOffsetY <= -oldTopInset + 2
        collectionView.contentInset = contentInset
        collectionView.scrollIndicatorInsets = contentInset
        if wasAtTop {
            collectionView.contentOffset.y = -contentInset.top
        }
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.headerView.backgroundColor = AppColors.solidBackground
        }
    }
}
