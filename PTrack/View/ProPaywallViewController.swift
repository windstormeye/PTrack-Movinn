//
//  ProPaywallViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import SafariServices
import SnapKit
import StoreKit
import UIKit

final class ProPaywallViewController: UIViewController {
    private enum LegalURL {
        static let privacyPolicy = "https://my.feishu.cn/wiki/DJMww5y8biIWrckzlmOcKigznEh"
        static let termsOfUse = "https://my.feishu.cn/wiki/VidDwr1DGiTPeyk2Hegcl5V9nog"
    }

    private let onPurchaseCompleted: (() -> Void)?
    private let backgroundView = AnimatedProGradientView()
    private let codeRedemptionButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let featuresStackView = UIStackView()
    private let bottomContainerView = UIView()
    private let purchaseButton = UIButton(type: .system)
    private let purchasePromoBadgeView = PromoBadgeView()
    private let linksStackView = UIStackView()
    private let privacyButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let termsButton = UIButton(type: .system)

    private var productLoadTask: Task<Void, Never>?
    private var purchaseTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var isPurchasing = false
    private var isRestoring = false

    init(onPurchaseCompleted: (() -> Void)? = nil) {
        self.onPurchaseCompleted = onPurchaseCompleted
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        onPurchaseCompleted = nil
        super.init(coder: coder)
        modalPresentationStyle = .fullScreen
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        productLoadTask?.cancel()
        purchaseTask?.cancel()
        restoreTask?.cancel()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        configureActions()
        registerObservers()
        updateLocalizedText()
        prepareSubscription()
    }

    private func configureViews() {
        view.backgroundColor = .black
        backgroundView.apply(style: .paywallBackground)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 40, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78

        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        subtitleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        featuresStackView.axis = .vertical
        featuresStackView.spacing = 18
        featuresStackView.alignment = .fill
        featuresStackView.distribution = .fill

        configureCodeRedemptionButton()
        configureCloseButton()
        configurePurchaseButton()
        configureLinks()

        view.addSubview(backgroundView)
        view.addSubview(scrollView)
        view.addSubview(codeRedemptionButton)
        view.addSubview(closeButton)
        view.addSubview(bottomContainerView)
        scrollView.addSubview(contentView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(featuresStackView)
        bottomContainerView.addSubview(purchaseButton)
        bottomContainerView.addSubview(purchasePromoBadgeView)
        bottomContainerView.addSubview(linksStackView)

        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        codeRedemptionButton.snp.makeConstraints { make in
            make.centerY.equalTo(closeButton)
            make.leading.equalToSuperview().inset(20)
            make.height.equalTo(28)
        }

        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(10)
            make.trailing.equalToSuperview().inset(20)
            make.size.equalTo(34)
        }

        bottomContainerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(18)
        }

        purchaseButton.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(62)
        }

        purchasePromoBadgeView.snp.makeConstraints { make in
            make.top.equalTo(purchaseButton.snp.top).offset(-9)
            make.trailing.equalTo(purchaseButton.snp.trailing).offset(7)
            make.height.equalTo(24)
            make.width.greaterThanOrEqualTo(52)
        }

        linksStackView.snp.makeConstraints { make in
            make.top.equalTo(purchaseButton.snp.bottom).offset(17)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.greaterThanOrEqualTo(28)
        }

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(54)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomContainerView.snp.top).offset(-20)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(28)
        }

        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(28)
        }

        featuresStackView.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(42)
            make.leading.trailing.equalToSuperview().inset(30)
            make.bottom.equalToSuperview().inset(28)
        }
    }

    private func configureCodeRedemptionButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "giftcard",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        configuration.imagePadding = 4
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 10)
        configuration.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        configuration.background.cornerRadius = 14
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        codeRedemptionButton.configuration = configuration
        codeRedemptionButton.tintColor = .white
        codeRedemptionButton.titleLabel?.adjustsFontSizeToFitWidth = true
        codeRedemptionButton.titleLabel?.minimumScaleFactor = 0.78
    }

    private func configureCloseButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        configuration.background.cornerRadius = 17
        closeButton.configuration = configuration
        closeButton.tintColor = .white
    }

    private func configurePurchaseButton() {
        purchaseButton.layer.cornerRadius = 8
        purchaseButton.layer.cornerCurve = .continuous
        purchaseButton.layer.masksToBounds = true
        purchaseButton.titleLabel?.adjustsFontSizeToFitWidth = true
        purchaseButton.titleLabel?.minimumScaleFactor = 0.82
    }

    private func configureLinks() {
        linksStackView.axis = .horizontal
        linksStackView.alignment = .center
        linksStackView.distribution = .equalSpacing
        linksStackView.spacing = 8

        configureLinkButton(privacyButton, weight: .regular)
        configureLinkButton(restoreButton, weight: .bold)
        configureLinkButton(termsButton, weight: .regular)

        linksStackView.addArrangedSubview(privacyButton)
        linksStackView.addArrangedSubview(restoreButton)
        linksStackView.addArrangedSubview(termsButton)
    }

    private func configureLinkButton(_ button: UIButton, weight: UIFont.Weight) {
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: weight)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.78
        button.setTitleColor(UIColor.white.withAlphaComponent(weight == .bold ? 0.86 : 0.58), for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.35), for: .highlighted)
    }

    private func configureActions() {
        codeRedemptionButton.addTarget(self, action: #selector(handleCodeRedemption), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        purchaseButton.addTarget(self, action: #selector(handlePurchase), for: .touchUpInside)
        privacyButton.addTarget(self, action: #selector(openPrivacyPolicy), for: .touchUpInside)
        restoreButton.addTarget(self, action: #selector(handleRestorePurchases), for: .touchUpInside)
        termsButton.addTarget(self, action: #selector(openTerms), for: .touchUpInside)
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
            selector: #selector(handleProSubscriptionDidChange),
            name: ProSubscriptionManager.didChangeNotification,
            object: nil
        )
    }

    private func updateLocalizedText() {
        titleLabel.text = AppLocalization.text(.proPaywallTitle)
        subtitleLabel.text = AppLocalization.text(.proPaywallSubtitle)

        featuresStackView.arrangedSubviews.forEach { view in
            featuresStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        featuresStackView.addArrangedSubview(ProFeatureRowView(
            iconName: "map",
            title: AppLocalization.text(.proFeatureHeatmap)
        ))
        featuresStackView.addArrangedSubview(ProFeatureRowView(
            iconName: "arrow.trianglehead.merge",
            fallbackIconName: "arrow.merge",
            title: AppLocalization.text(.proFeatureRouteMerge)
        ))
        featuresStackView.addArrangedSubview(ProFeatureRowView(
            iconName: "livephoto",
            title: AppLocalization.text(.proFeatureMultiLivePhotoExport)
        ))
        featuresStackView.addArrangedSubview(ProFeatureRowView(
            iconName: "sparkles",
            title: AppLocalization.text(.proFeatureMoreComing)
        ))

        privacyButton.setTitle(AppLocalization.text(.privacyPolicy), for: .normal)
        codeRedemptionButton.configuration?.title = AppLocalization.text(.proCodeRedemption)
        restoreButton.setTitle(AppLocalization.text(.restorePurchases), for: .normal)
        termsButton.setTitle(AppLocalization.text(.termsOfUse), for: .normal)
        purchasePromoBadgeView.configure(text: AppLocalization.text(.promotionBadge))
        updatePurchaseButton()
    }

    private func updatePurchaseButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        configuration.background.cornerRadius = 8

        let title: String
        if isPurchasing {
            title = AppLocalization.text(.proPurchaseLoading)
            configuration.baseBackgroundColor = UIColor(white: 0.64, alpha: 1)
            configuration.baseForegroundColor = .black
            configuration.showsActivityIndicator = true
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 8
            configuration.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in
                .black
            }
        } else if let price = ProSubscriptionManager.shared.displayPrice {
            title = AppLocalization.format(.proPurchaseButtonPriceFormat, price)
            configuration.baseBackgroundColor = AppColors.movinnGreen
            configuration.baseForegroundColor = .black
        } else {
            title = AppLocalization.text(.proPurchaseButton)
            configuration.baseBackgroundColor = AppColors.movinnGreen
            configuration.baseForegroundColor = .black
        }

        var attributedTitle = AttributedString(title)
        attributedTitle.font = .systemFont(ofSize: 19, weight: .bold)
        configuration.attributedTitle = attributedTitle
        purchaseButton.configuration = configuration
        purchaseButton.isEnabled = true
        purchaseButton.isUserInteractionEnabled = !isPurchasing && !isRestoring
    }

    private func prepareSubscription() {
        productLoadTask?.cancel()
        productLoadTask = Task { @MainActor [weak self] in
            await ProSubscriptionManager.shared.prepare()
            self?.updatePurchaseButton()
        }
    }

    private func setPurchaseInProgress(_ isInProgress: Bool) {
        isPurchasing = isInProgress
        updatePurchaseButton()
        updateLinkButtonsEnabledState()
    }

    private func setRestoreInProgress(_ isInProgress: Bool) {
        isRestoring = isInProgress
        updatePurchaseButton()
        updateLinkButtonsEnabledState()
    }

    private func updateLinkButtonsEnabledState() {
        let isEnabled = !isPurchasing && !isRestoring
        codeRedemptionButton.isEnabled = isEnabled
        privacyButton.isEnabled = isEnabled
        restoreButton.isEnabled = isEnabled
        termsButton.isEnabled = isEnabled
        codeRedemptionButton.alpha = isEnabled ? 1 : 0.58
        linksStackView.alpha = isEnabled ? 1 : 0.58
    }

    private func completeProFlow(with message: String) {
        Toast.show(message, in: view)
        dismiss(animated: true) { [onPurchaseCompleted] in
            onPurchaseCompleted?()
        }
    }

    private func presentErrorAlert(_ error: Error) {
        let alertController = UIAlertController(
            title: AppLocalization.text(.movinnPro),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func openLegalPage(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        let safariViewController = SFSafariViewController(url: url)
        safariViewController.preferredControlTintColor = AppColors.movinnGreen
        present(safariViewController, animated: true)
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func handleCodeRedemption() {
        guard !isPurchasing, !isRestoring else {
            return
        }

        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }

    @objc private func handlePurchase() {
        guard !isPurchasing, !isRestoring else {
            return
        }

        setPurchaseInProgress(true)
        purchaseTask?.cancel()
        purchaseTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await ProSubscriptionManager.shared.purchase()
                setPurchaseInProgress(false)
                handlePurchaseResult(result)
            } catch {
                setPurchaseInProgress(false)
                presentErrorAlert(error)
            }
        }
    }

    @objc private func handleRestorePurchases() {
        guard !isPurchasing, !isRestoring else {
            return
        }

        setRestoreInProgress(true)
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await ProSubscriptionManager.shared.restore()
                setRestoreInProgress(false)
                switch result {
                case .restored:
                    completeProFlow(with: AppLocalization.text(.proRestoreSuccess))
                case .noActivePurchase:
                    Toast.show(AppLocalization.text(.proRestoreNoPurchase), in: view)
                }
            } catch {
                setRestoreInProgress(false)
                presentErrorAlert(error)
            }
        }
    }

    private func handlePurchaseResult(_ result: ProSubscriptionPurchaseResult) {
        switch result {
        case .purchased:
            completeProFlow(with: AppLocalization.text(.proPurchaseSuccess))
        case .alreadyActive:
            completeProFlow(with: AppLocalization.text(.proStatusActive))
        case .cancelled:
            break
        case .pending:
            Toast.show(AppLocalization.text(.proPurchasePending), in: view)
        }
    }

    @objc private func openPrivacyPolicy() {
        openLegalPage(urlString: LegalURL.privacyPolicy)
    }

    @objc private func openTerms() {
        openLegalPage(urlString: LegalURL.termsOfUse)
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
    }

    @objc private func handleProSubscriptionDidChange() {
        updatePurchaseButton()
    }
}

extension UIViewController {
    @MainActor
    func presentProPaywall(onPurchaseCompleted: (() -> Void)? = nil) {
        let viewController = ProPaywallViewController(onPurchaseCompleted: onPurchaseCompleted)
        viewController.modalPresentationStyle = .fullScreen
        present(viewController, animated: true)
    }
}

private final class ProFeatureRowView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(iconName: String, fallbackIconName: String? = nil, title: String) {
        super.init(frame: .zero)
        configureViews()
        let image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        ) ?? fallbackIconName.flatMap {
            UIImage(
                systemName: $0,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            )
        }
        iconView.image = image
        titleLabel.text = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        iconView.tintColor = AppColors.movinnGreen
        iconView.contentMode = .scaleAspectFit
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82

        addSubview(iconView)
        addSubview(titleLabel)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(28)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(18)
            make.trailing.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.height.greaterThanOrEqualTo(30)
        }
    }
}
