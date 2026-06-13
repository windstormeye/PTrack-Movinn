//
//  ViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import SnapKit
import UIKit

class ViewController: UIViewController {
    private let store = HealthWorkoutStore()
    private let cacheStore = WorkoutCacheStore()
    private var workouts: [TrackedWorkout] = []
    private var collectionView: UICollectionView!
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var columnCount: CGFloat = 3
    private var pinchStartColumnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 16, right: 12)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureHeaderView()
        configureLoadingIndicator()
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        loadCachedWorkouts()
        loadHealthWorkouts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFullScreenInsets()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        updateFullScreenInsets(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullScreenInsets(force: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateFullScreenInsets(force: true)
        }
    }

    private func configureNavigationItem() {
        title = "Movinn"
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureCollectionView() {
        view.backgroundColor = .systemBackground

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = lineSpacing
        layout.sectionInset = sectionInset

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(WorkoutRouteCell.self, forCellWithReuseIdentifier: WorkoutRouteCell.reuseIdentifier)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        view.addSubview(collectionView)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureHeaderView() {
        headerView.isUserInteractionEnabled = false
        headerView.backgroundColor = .white

        titleLabel.text = "Movinn"
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 40, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true

        totalDistanceLabel.textColor = .secondaryLabel
        totalDistanceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        totalDistanceLabel.adjustsFontForContentSizeCategory = true
        totalDistanceLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalDistanceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        totalDistanceLabel.lineBreakMode = .byTruncatingTail

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(totalDistanceLabel)
        headerView.addSubview(loadingIndicator)

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(122)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
        }

        totalDistanceLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(10)
            make.trailing.lessThanOrEqualTo(loadingIndicator.snp.leading).offset(-8)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline).offset(-3)
        }

        loadingIndicator.snp.makeConstraints { make in
            make.leading.equalTo(totalDistanceLabel.snp.trailing).offset(8)
            make.centerY.equalTo(totalDistanceLabel)
            make.trailing.lessThanOrEqualToSuperview().offset(-16)
        }

        updateTotalDistanceText()
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
    }

    private func updateFullScreenInsets(force: Bool = false) {
        guard let collectionView else {
            return
        }

        view.layoutIfNeeded()
        let headerMaxY = headerView.convert(headerView.bounds, to: view).maxY

        let contentInset = UIEdgeInsets(top: headerMaxY + headerBottomPadding, left: 0, bottom: 0, right: 0)
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

    private func updateTotalDistanceText() {
        let totalKilometers = workouts.reduce(0) { $0 + $1.distanceMeters } / 1000
        totalDistanceLabel.text = "总距离：\(Int(totalKilometers.rounded()))KM"
    }

    private func loadCachedWorkouts() {
        workouts = cacheStore.load()
        updateTotalDistanceText()
        collectionView.reloadData()
    }

    private func loadHealthWorkouts() {
        loadingIndicator.startAnimating()
        store.requestAuthorization { [weak self] authorizationResult in
            guard let self else { return }
            switch authorizationResult {
            case .success:
                Task { @MainActor in
                    self.loadIncrementalHealthWorkouts()
                }
            case .failure(let error):
                print("PTrack HealthKit: authorization failed: \(error)")
                Task { @MainActor in
                    self.loadingIndicator.stopAnimating()
                }
            }
        }
    }

    private func loadIncrementalHealthWorkouts() {
        let newestCachedDate = workouts.map(\.startDate).max()
        let cachedIDs = Set(workouts.map(\.id))

        store.loadTrackedWorkouts(
            after: newestCachedDate,
            excludingIDs: cachedIDs,
            onTrackedWorkout: { [weak self] trackedWorkout in
                Task { @MainActor in
                    self?.appendTrackedWorkout(trackedWorkout)
                }
            },
            completion: { [weak self] loadResult in
                Task { @MainActor in
                    self?.handleLoadResult(loadResult)
                }
            }
        )
    }

    private func appendTrackedWorkout(_ workout: TrackedWorkout) {
        guard !workouts.contains(where: { $0.id == workout.id }) else {
            return
        }

        workouts.append(workout)
        workouts.sort { $0.startDate > $1.startDate }
        cacheStore.save(workouts)
        updateTotalDistanceText()

        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else {
            collectionView.reloadData()
            return
        }

        collectionView.performBatchUpdates {
            collectionView.insertItems(at: [IndexPath(item: index, section: 0)])
        }
    }

    private func handleLoadResult(_ result: Result<Int, Error>) {
        loadingIndicator.stopAnimating()
        switch result {
        case .success(let count):
            print("PTrack HealthKit: incremental route query completed, new routes: \(count)")
        case .failure(let error):
            print("PTrack HealthKit: route query failed: \(error)")
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchStartColumnCount = columnCount
        case .changed:
            let scaledColumns = pinchStartColumnCount / recognizer.scale
            let newColumnCount = min(max(round(scaledColumns), 2), 6)
            guard newColumnCount != columnCount else { return }
            columnCount = newColumnCount
            collectionView.performBatchUpdates {
                collectionView.collectionViewLayout.invalidateLayout()
            }
            collectionView.visibleCells.compactMap { $0 as? WorkoutRouteCell }.forEach { cell in
                if let indexPath = collectionView.indexPath(for: cell) {
                    cell.configure(with: workouts[indexPath.item], columnCount: columnCount, showsMap: false)
                }
            }
        default:
            break
        }
    }
}

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        workouts.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WorkoutRouteCell.reuseIdentifier,
            for: indexPath
        )

        if let cell = cell as? WorkoutRouteCell {
            cell.configure(with: workouts[indexPath.item], columnCount: columnCount, showsMap: false)
        }

        return cell
    }
}

extension ViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let itemSize = self.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        for indexPath in indexPaths where indexPath.item < workouts.count {
            WorkoutRouteSnapshotRenderer.cachedSnapshot(
                for: workouts[indexPath.item],
                size: itemSize,
                showsMap: false,
                traitCollection: traitCollection
            ) { _ in }
        }
    }
}

extension ViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let columns = min(max(columnCount, 2), 6)
        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let totalSpacing = itemSpacing * (columns - 1)
        let width = floor((availableWidth - totalSpacing) / columns)
        let height = max(72, floor(width * 0.74))
        return CGSize(width: width, height: height)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        sectionInset
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        itemSpacing
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        lineSpacing
    }
}

extension ViewController {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < workouts.count else {
            return
        }

        let detailViewController = WorkoutRouteDetailViewController(workout: workouts[indexPath.item])
        navigationController?.pushViewController(detailViewController, animated: true)
    }
}
