//
//  MoreSettingsViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/15.
//

import UIKit
import SafariServices
import SnapKit

final class MoreSettingsViewController: UIViewController {
    private enum SettingsSection: Int, CaseIterable {
        case uiSettings
        case dataIntegration
        case other

        var titleKey: AppTextKey {
            switch self {
            case .uiSettings:
                return .uiSettings
            case .dataIntegration:
                return .dataIntegration
            case .other:
                return .other
            }
        }

        var items: [SettingsItem] {
            switch self {
            case .uiSettings:
                return [.appLanguage]
            case .dataIntegration:
                return [.appleHealth, .strava]
            case .other:
                return [.developerWebsite]
            }
        }
    }

    private enum SettingsItem {
        case appLanguage
        case appleHealth
        case strava
        case developerWebsite

        var titleKey: AppTextKey {
            switch self {
            case .appLanguage:
                return .appLanguage
            case .appleHealth:
                return .appleHealth
            case .strava:
                return .strava
            case .developerWebsite:
                return .developerWebsite
            }
        }

        var iconName: String {
            switch self {
            case .appLanguage:
                return "globe"
            case .appleHealth:
                return "heart.fill"
            case .strava:
                return "figure.run"
            case .developerWebsite:
                return "safari"
            }
        }
    }

    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let navigationBackgroundHeight: CGFloat = 124
    private let healthWorkoutStore = HealthWorkoutStore()
    private var collectionView: UICollectionView!

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureNavigationBackgroundView()
        registerLanguageObserver()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
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

    private func configureCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MoreSettingsCell.self, forCellWithReuseIdentifier: MoreSettingsCell.reuseIdentifier)
        collectionView.register(
            MoreSettingsSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: MoreSettingsSectionHeaderView.reuseIdentifier
        )
        collectionView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 28,
            right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset

        view.addSubview(collectionView)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
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
        updateLocalizedText()
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.more)
        collectionView?.reloadData()
    }

    private func item(at indexPath: IndexPath) -> SettingsItem {
        SettingsSection.allCases[indexPath.section].items[indexPath.item]
    }

    private func presentLanguagePicker(from sourceView: UIView?) {
        let alertController = UIAlertController(
            title: AppLocalization.text(.appLanguage),
            message: nil,
            preferredStyle: .actionSheet
        )
        let currentLanguage = AppLanguageStore.shared.language

        for language in AppLanguage.allCases {
            let actionTitle = language == currentLanguage ? "✓ \(language.nativeName)" : language.nativeName
            alertController.addAction(UIAlertAction(title: actionTitle, style: .default) { _ in
                AppLanguageStore.shared.language = language
            })
        }

        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.cancel),
            style: .cancel
        ))

        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = sourceView ?? view
            popoverPresentationController.sourceRect = sourceView?.bounds ?? CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
        }

        present(alertController, animated: true)
    }

    private func requestHealthAuthorization() {
        healthWorkoutStore.requestAuthorization { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if case .failure(let error) = result {
                    self.presentErrorAlert(error)
                }
            }
        }
    }

    private func openStravaAuthorization() {
        let stravaDefine = StravaDefine()
        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: stravaDefine.ClientID),
            URLQueryItem(name: "redirect_uri", value: "https://pj.studio"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:read_all")
        ]

        guard let url = components?.url else {
            return
        }

        presentInternalBrowser(url: url)
    }

    private func openDeveloperWebsite() {
        guard let url = URL(string: "https://pj.studio") else {
            return
        }

        presentInternalBrowser(url: url)
    }

    private func presentInternalBrowser(url: URL) {
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.preferredControlTintColor = .label
        present(safariViewController, animated: true)
    }

    private func presentErrorAlert(_ error: Error) {
        let alertController = UIAlertController(
            title: AppLocalization.text(.healthAuthorizationFailed),
            message: localizedHealthErrorMessage(for: error),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func localizedHealthErrorMessage(for error: Error) -> String {
        guard let storeError = error as? HealthWorkoutStoreError else {
            return error.localizedDescription
        }

        switch storeError {
        case .healthDataUnavailable:
            return AppLocalization.text(.healthDataUnavailable)
        case .authorizationDenied:
            return AppLocalization.text(.healthAuthorizationDenied)
        }
    }
}

extension MoreSettingsViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        SettingsSection.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        SettingsSection.allCases[section].items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MoreSettingsCell.reuseIdentifier,
            for: indexPath
        ) as? MoreSettingsCell else {
            return UICollectionViewCell()
        }

        let item = item(at: indexPath)
        cell.configure(
            iconName: item.iconName,
            title: AppLocalization.text(item.titleKey)
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let headerView = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: MoreSettingsSectionHeaderView.reuseIdentifier,
                for: indexPath
              ) as? MoreSettingsSectionHeaderView else {
            return UICollectionReusableView()
        }

        let section = SettingsSection.allCases[indexPath.section]
        headerView.configure(title: AppLocalization.text(section.titleKey))
        return headerView
    }
}

extension MoreSettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        switch item(at: indexPath) {
        case .appLanguage:
            presentLanguagePicker(from: collectionView.cellForItem(at: indexPath))
        case .appleHealth:
            requestHealthAuthorization()
        case .strava:
            openStravaAuthorization()
        case .developerWebsite:
            openDeveloperWebsite()
        }
    }
}

extension MoreSettingsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let sectionInset = self.collectionView(
            collectionView,
            layout: collectionViewLayout,
            insetForSectionAt: indexPath.section
        )
        let spacing = self.collectionView(
            collectionView,
            layout: collectionViewLayout,
            minimumInteritemSpacingForSectionAt: indexPath.section
        )
        let width = floor((collectionView.bounds.width - sectionInset.left - sectionInset.right - spacing) / 2)
        return CGSize(width: max(width, 1), height: 58)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        UIEdgeInsets(top: section == 0 ? 4 : 18, left: 16, bottom: 0, right: 16)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        10
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        10
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 34)
    }
}

private final class MoreSettingsCell: UICollectionViewCell {
    static let reuseIdentifier = "MoreSettingsCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14) {
                self.contentView.alpha = self.isHighlighted ? 0.68 : 1
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }

    func configure(iconName: String, title: String) {
        iconView.image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        titleLabel.text = title
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = UIColor(white: 0.945, alpha: 1)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        iconView.tintColor = .black
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.74
        titleLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
    }
}

private final class MoreSettingsSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "MoreSettingsSectionHeaderView"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(title: String) {
        titleLabel.text = title
    }

    private func configureViews() {
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true

        addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(7)
        }
    }
}
