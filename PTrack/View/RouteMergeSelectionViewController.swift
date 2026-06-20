//
//  RouteMergeSelectionViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/20.
//

import SnapKit
import UIKit

final class RouteMergeSelectionViewController: UIViewController {
    var onMergeCompleted: ((TrackedWorkout) -> Void)?

    private let store = RouteCollectionStore()
    private let mergeQueue = DispatchQueue(label: "studio.pj.PTrack.route-merge", qos: .userInitiated)
    private let routeGridView = WorkoutRouteGridView()
    private let emptyLabel = UILabel()
    private let loadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let currentWorkout: TrackedWorkout
    private let currentWorkoutID: String
    private var mergeButton: UIBarButtonItem?
    private var workouts: [TrackedWorkout]
    private var selectedWorkoutIDs = Set<String>()
    private var selectedWorkoutOrder: [String] = []
    private var isMerging = false

    init(workouts: [TrackedWorkout], currentWorkout: TrackedWorkout) {
        self.currentWorkout = currentWorkout
        currentWorkoutID = currentWorkout.id
        self.workouts = workouts.filter { !$0.routeDetailCoordinates.isEmpty }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureNavigationBar()
        configureGridView()
        configureEmptyLabel()
        configureLoadingView()
        updateMergeButtonState()
        updateEmptyState()
    }

    private func configureNavigationItem() {
        title = AppLocalization.text(.routeMerge)
        edgesForExtendedLayout = []
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(dismissSelf)
        )

        let mergeImage = UIImage(systemName: "arrow.trianglehead.merge") ?? UIImage(systemName: "arrow.merge")
        let mergeButton = UIBarButtonItem(
            image: mergeImage,
            style: .plain,
            target: self,
            action: #selector(mergeSelectedRoutes)
        )
        navigationItem.rightBarButtonItem = mergeButton
        self.mergeButton = mergeButton
    }

    private func configureNavigationBar() {
        view.backgroundColor = .systemBackground
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .label
    }

    private func configureGridView() {
        routeGridView.configureLayout(
            columns: 3,
            itemSpacing: 12,
            lineSpacing: 2,
            sectionInset: UIEdgeInsets(top: 14, left: 12, bottom: 28, right: 12),
            minimumColumns: 3,
            maximumColumns: 3
        )
        routeGridView.numberOfItemsProvider = { [weak self] in
            self?.workouts.count ?? 0
        }
        routeGridView.itemProvider = { [weak self] index in
            guard let self, index >= 0, index < workouts.count else {
                return nil
            }

            let workout = workouts[index]
            let isCurrentWorkout = workout.id == currentWorkoutID
            return WorkoutRouteGridItem.route(
                workout,
                showsMap: false,
                timeTagText: workout.navigationDateText,
                isSelected: selectedWorkoutIDs.contains(workout.id),
                isEnabled: !isCurrentWorkout
            )
        }
        routeGridView.onSelectRoute = { [weak self] workout, indexPath, cell in
            self?.toggleSelection(for: workout, at: indexPath, cell: cell)
        }

        view.addSubview(routeGridView)
        routeGridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureEmptyLabel() {
        emptyLabel.text = AppLocalization.text(.homeNoWorkoutDataMessage)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true

        view.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview().inset(24)
        }
    }

    private func configureLoadingView() {
        loadingView.isHidden = true
        loadingView.alpha = 0
        loadingView.layer.cornerRadius = 16
        loadingView.layer.cornerCurve = .continuous
        loadingView.layer.masksToBounds = true
        loadingView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.16)

        loadingIndicator.hidesWhenStopped = true

        loadingLabel.text = AppLocalization.text(.routeMergeLoading)
        loadingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        loadingLabel.textColor = UIColor.black.withAlphaComponent(0.72)
        loadingLabel.textAlignment = .center

        view.addSubview(loadingView)
        loadingView.contentView.addSubview(loadingIndicator)
        loadingView.contentView.addSubview(loadingLabel)

        loadingView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.width.greaterThanOrEqualTo(132)
            make.height.equalTo(72)
        }

        loadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(13)
        }

        loadingLabel.snp.makeConstraints { make in
            make.top.equalTo(loadingIndicator.snp.bottom).offset(7)
            make.leading.trailing.equalToSuperview().inset(14)
        }
    }

    private func toggleSelection(for workout: TrackedWorkout, at indexPath: IndexPath, cell: WorkoutRouteCell?) {
        guard !isMerging, workout.id != currentWorkoutID else {
            return
        }

        let isSelected: Bool
        if selectedWorkoutIDs.contains(workout.id) {
            selectedWorkoutIDs.remove(workout.id)
            selectedWorkoutOrder.removeAll { $0 == workout.id }
            isSelected = false
        } else {
            selectedWorkoutIDs.insert(workout.id)
            selectedWorkoutOrder.append(workout.id)
            isSelected = true
        }

        updateMergeButtonState()
        routeGridView.collectionView.deselectItem(at: indexPath, animated: false)
        cell?.setShowsSelectionCheckmark(isSelected, animated: false)
    }

    private func updateMergeButtonState() {
        mergeButton?.isEnabled = !selectedWorkoutIDs.isEmpty && !isMerging
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !workouts.isEmpty
    }

    private func selectedWorkouts() -> [TrackedWorkout] {
        var workoutsByID: [String: TrackedWorkout] = [:]
        for workout in workouts {
            workoutsByID[workout.id] = workout
        }

        var selectedWorkouts = [currentWorkout]
        selectedWorkouts.append(contentsOf: selectedWorkoutOrder.compactMap { workoutsByID[$0] })
        return selectedWorkouts
    }

    private func setLoadingVisible(_ isVisible: Bool) {
        loadingView.layer.removeAllAnimations()
        routeGridView.collectionView.isUserInteractionEnabled = !isVisible
        navigationItem.leftBarButtonItem?.isEnabled = !isVisible

        if isVisible {
            view.bringSubviewToFront(loadingView)
            loadingView.isHidden = false
            loadingIndicator.startAnimating()
            UIView.animate(withDuration: 0.18) {
                self.loadingView.alpha = 1
            }
        } else {
            UIView.animate(
                withDuration: 0.18,
                animations: {
                    self.loadingView.alpha = 0
                },
                completion: { _ in
                    self.loadingIndicator.stopAnimating()
                    self.loadingView.isHidden = true
                }
            )
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func mergeSelectedRoutes() {
        guard !isMerging else {
            return
        }

        let selectedWorkouts = selectedWorkouts()
        guard !selectedWorkouts.isEmpty else {
            return
        }

        isMerging = true
        updateMergeButtonState()
        setLoadingVisible(true)

        mergeQueue.async { [weak self] in
            let result: Result<TrackedWorkout, Error>
            do {
                let mergedRoute = try RouteCollectionMerger.mergedRoute(from: selectedWorkouts)
                result = .success(mergedRoute)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if case .success(let mergedRoute) = result {
                    self.store.append(mergedRoute)
                }
                self.handleMergeResult(result)
            }
        }
    }

    private func handleMergeResult(_ result: Result<TrackedWorkout, Error>) {
        isMerging = false
        setLoadingVisible(false)
        updateMergeButtonState()

        switch result {
        case .success(let mergedRoute):
            onMergeCompleted?(mergedRoute)
        case .failure(let error):
            let alertController = UIAlertController(
                title: AppLocalization.text(.routeMergeFailed),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
            present(alertController, animated: true)
        }
    }
}
