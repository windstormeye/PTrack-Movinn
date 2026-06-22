//
//  RouteMediaBrowserViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import SnapKit
import UIKit

final class RouteMediaBrowserViewController: UIViewController {
    let mediaItems: [RouteMediaItem]
    private let initialIndex: Int
    private var collectionView: UICollectionView!
    private var didScrollToInitialIndex = false

    init(mediaItems: [RouteMediaItem], initialIndex: Int) {
        self.mediaItems = mediaItems
        self.initialIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prepareForPermanentDismissal()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationBar()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isPermanentlyLeaving {
            prepareForPermanentDismissal()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didScrollToInitialIndex, initialIndex < mediaItems.count else {
            return
        }

        didScrollToInitialIndex = true
        collectionView.scrollToItem(
            at: IndexPath(item: initialIndex, section: 0),
            at: .centeredHorizontally,
            animated: false
        )
        updateTitle(for: initialIndex)
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    private var isPermanentlyLeaving: Bool {
        isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
    }

    private func prepareForPermanentDismissal() {
        guard isViewLoaded else {
            return
        }

        collectionView.visibleCells
            .compactMap { $0 as? RouteMediaBrowserCell }
            .forEach { $0.prepareForDismissal() }
        collectionView.dataSource = nil
        collectionView.delegate = nil
    }

    private func configureNavigationItem() {
        view.backgroundColor = .black
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.navigationBar.tintColor = .white
    }

    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.tintColor = .white
    }

    private func configureCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(RouteMediaBrowserCell.self, forCellWithReuseIdentifier: RouteMediaBrowserCell.reuseIdentifier)

        view.addSubview(collectionView)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func updateTitle(for index: Int) {
        guard !mediaItems.isEmpty else {
            title = nil
            return
        }

        title = "\(index + 1) / \(mediaItems.count)"
    }

    func closeBrowser() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

extension RouteMediaBrowserViewController: RouteMediaBrowserCellDelegate {
    func routeMediaBrowserCellDidRequestDismiss(_ cell: RouteMediaBrowserCell) {
        closeBrowser()
    }
}
