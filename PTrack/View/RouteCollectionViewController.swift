//
//  RouteCollectionViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import SnapKit
import UIKit
import UniformTypeIdentifiers

final class RouteCollectionViewController: UIViewController {
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let navigationBackgroundHeight: CGFloat = 124
    private let store = RouteCollectionStore()
    private let emptyLabel = UILabel()
    private let routeGridView = WorkoutRouteGridView()
    private var collectionView: UICollectionView!
    private var routes: [TrackedWorkout] = []
    private var loadingIDs: [UUID] = []

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureEmptyLabel()
        configureNavigationBackgroundView()
        registerObservers()
        reloadRoutes(importsPendingSharedRoutes: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
        reloadRoutes(importsPendingSharedRoutes: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func configureNavigationItem() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = [.top, .bottom]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(presentGPXPicker)
        )
        updateLocalizedText()
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

    private func configureCollectionView() {
        routeGridView.configureLayout(
            columns: 3,
            itemSpacing: 12,
            lineSpacing: 2,
            sectionInset: UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12),
            minimumColumns: 2,
            maximumColumns: 6
        )
        routeGridView.numberOfItemsProvider = { [weak self] in
            guard let self else {
                return 0
            }

            return self.loadingIDs.count + self.routes.count
        }
        routeGridView.itemProvider = { [weak self] index in
            self?.gridItem(at: index)
        }
        routeGridView.onSelectRoute = { [weak self] workout, _, _ in
            self?.showRouteDetail(workout)
        }

        collectionView = routeGridView.collectionView
        collectionView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 28,
            right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset

        view.addSubview(routeGridView)

        routeGridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureEmptyLabel() {
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        view.addSubview(emptyLabel)

        emptyLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-24)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
        }
    }

    private func configureNavigationBackgroundView() {
        navigationBackgroundView.isUserInteractionEnabled = false
        navigationBackgroundView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        navigationBackgroundMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        navigationBackgroundMask.locations = [0, 0.58, 1]
        navigationBackgroundView.layer.mask = navigationBackgroundMask

        view.addSubview(navigationBackgroundView)

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
        }
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteCollectionDidChange),
            name: RouteCollectionStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
    }

    @objc private func handleRouteCollectionDidChange() {
        reloadRoutes(importsPendingSharedRoutes: false)
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.routeCollection)
        emptyLabel.text = AppLocalization.text(.routeCollectionEmptyMessage)
        collectionView?.reloadData()
    }

    private func reloadRoutes(importsPendingSharedRoutes: Bool) {
        if importsPendingSharedRoutes {
            SharedRouteImportInbox.importPendingRoutes(store: store)
        }
        routes = store.load()
        collectionView?.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !routes.isEmpty || !loadingIDs.isEmpty
    }

    private func gridItem(at index: Int) -> WorkoutRouteGridItem? {
        guard index >= 0 else {
            return nil
        }

        if index < loadingIDs.count {
            return WorkoutRouteGridItem.loading(
                id: loadingIDs[index],
                title: AppLocalization.text(.routeCollectionImporting)
            )
        }

        let routeIndex = index - loadingIDs.count
        guard routeIndex < routes.count else {
            return nil
        }

        return WorkoutRouteGridItem.route(
            routes[routeIndex],
            showsMap: false,
            showsNewBadge: false
        )
    }

    private func showRouteDetail(_ workout: TrackedWorkout) {
        let detailViewController = WorkoutRouteDetailViewController(
            workout: workout,
            presentationMode: .routeCollection
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    @objc private func presentGPXPicker() {
        let gpxType = UTType(filenameExtension: "gpx") ?? UTType(importedAs: "com.topografix.gpx")
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [gpxType])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true)
    }

    private func importGPXFiles(at urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        let loadingID = UUID()
        loadingIDs.insert(loadingID, at: 0)
        collectionView.reloadData()
        updateEmptyState()

        Task { @MainActor in
            var importedRoutes: [TrackedWorkout] = []
            var lastError: Error?

            for url in urls {
                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    importedRoutes.append(try SharedRouteImportInbox.makeRoute(fromGPXAt: url))
                } catch {
                    lastError = error
                }
            }

            if !importedRoutes.isEmpty {
                store.append(importedRoutes)
                routes = store.load()
            }

            removeLoadingCell(id: loadingID)
            updateEmptyState()

            if !importedRoutes.isEmpty {
                Toast.show(AppLocalization.text(.routeCollectionImportSuccess), in: view)
            } else if let lastError {
                Toast.show(lastError.localizedDescription, in: view)
            }
        }
    }

    private func removeLoadingCell(id: UUID) {
        guard let index = loadingIDs.firstIndex(of: id) else {
            return
        }

        loadingIDs.remove(at: index)
        collectionView.reloadData()
    }
}

extension RouteCollectionViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importGPXFiles(at: urls.filter { $0.pathExtension.lowercased() == "gpx" })
    }
}
