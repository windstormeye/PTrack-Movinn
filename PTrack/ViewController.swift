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
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var columnCount: CGFloat = 2
    private var pinchStartColumnCount: CGFloat = 2
    private let itemSpacing: CGFloat = 12
    private let sectionInset = UIEdgeInsets(top: 44, left: 12, bottom: 16, right: 12)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCollectionView()
        configureLoadingIndicator()
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        loadCachedWorkouts()
        loadHealthWorkouts()
    }

    private func configureCollectionView() {
        view.backgroundColor = .systemBackground
        title = "运动轨迹"

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = itemSpacing
        layout.sectionInset = sectionInset

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(WorkoutRouteCell.self, forCellWithReuseIdentifier: WorkoutRouteCell.reuseIdentifier)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        view.addSubview(collectionView)

        collectionView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true

        view.addSubview(loadingIndicator)

        loadingIndicator.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.equalToSuperview().offset(16)
        }
    }

    private func loadCachedWorkouts() {
        workouts = cacheStore.load()
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
            let newColumnCount = min(max(round(scaledColumns), 1), 6)
            guard newColumnCount != columnCount else { return }
            columnCount = newColumnCount
            collectionView.performBatchUpdates {
                collectionView.collectionViewLayout.invalidateLayout()
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
            cell.configure(with: workouts[indexPath.item])
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
        let columns = max(columnCount, 1)
        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let totalSpacing = itemSpacing * (columns - 1)
        let width = floor((availableWidth - totalSpacing) / columns)
        let height = max(88, floor(width * 0.92))
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
        itemSpacing
    }
}
