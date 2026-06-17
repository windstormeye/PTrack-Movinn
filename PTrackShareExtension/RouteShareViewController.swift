//
//  RouteShareViewController.swift
//  PTrackShareExtension
//
//  Created by Codex on 2026/6/18.
//

import UIKit
import UniformTypeIdentifiers

final class RouteShareViewController: UIViewController {
    private enum Constants {
        static let appGroupIdentifier = "group.studio.pj.app.PTrack"
        static let pendingDirectoryName = "PendingRoutes"
        static let unseenRouteKey = "studio.pj.PTrack.routeCollection.hasUnseenSharedRoute"
        static let routeCollectionOpenRequestKey = "studio.pj.PTrack.routeCollection.openRequestPending"
        static let gpxTypeIdentifier = "com.topografix.gpx"
        static let appleGPXTypeIdentifier = "com.apple.dt.document.gpx"
        static let movinnGreen = UIColor(red: 141 / 255, green: 189 / 255, blue: 0, alpha: 1)
    }

    private let cardView = UIView()
    private let iconContainerView = UIView()
    private let iconView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .overFullScreen
        configureViews()
        showLoadingState()
        importSharedGPXFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clearPresentationBackground()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        clearPresentationBackground()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.clearPresentationBackground()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        clearPresentationBackground()
    }

    private func configureViews() {
        view.isOpaque = false
        view.backgroundColor = .clear
        preferredContentSize = CGSize(width: 320, height: 220)

        cardView.backgroundColor = .systemBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.18
        cardView.layer.shadowRadius = 22
        cardView.layer.shadowOffset = CGSize(width: 0, height: 10)
        cardView.translatesAutoresizingMaskIntoConstraints = false

        iconContainerView.backgroundColor = Constants.movinnGreen.withAlphaComponent(0.16)
        iconContainerView.layer.cornerRadius = 23
        iconContainerView.layer.cornerCurve = .continuous
        iconContainerView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Constants.movinnGreen
        iconView.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        var doneConfiguration = UIButton.Configuration.filled()
        doneConfiguration.baseBackgroundColor = Constants.movinnGreen
        doneConfiguration.baseForegroundColor = UIColor.black.withAlphaComponent(0.86)
        doneConfiguration.cornerStyle = .capsule
        doneConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22)
        doneButton.configuration = doneConfiguration
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(handleDoneButtonTap), for: .touchUpInside)

        view.addSubview(cardView)
        cardView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        iconContainerView.addSubview(activityIndicator)
        cardView.addSubview(titleLabel)
        cardView.addSubview(messageLabel)
        cardView.addSubview(doneButton)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 292),

            iconContainerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            iconContainerView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 46),
            iconContainerView.heightAnchor.constraint(equalToConstant: 46),

            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            activityIndicator.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconContainerView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            doneButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            doneButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22)
        ])
    }

    private func clearPresentationBackground() {
        view.isOpaque = false
        view.backgroundColor = .clear
        view.window?.isOpaque = false
        view.window?.backgroundColor = .clear
        presentationController?.containerView?.isOpaque = false
        presentationController?.containerView?.backgroundColor = .clear

        var containerView = view.superview
        while let currentView = containerView {
            currentView.isOpaque = false
            currentView.backgroundColor = .clear
            containerView = currentView.superview
        }
    }

    private func showLoadingState() {
        iconView.isHidden = true
        activityIndicator.startAnimating()
        titleLabel.text = ShareExtensionLocalization.text(.importingTitle)
        messageLabel.text = ShareExtensionLocalization.text(.importingMessage)
        doneButton.isHidden = true
    }

    private func showSuccessState() {
        iconView.image = UIImage(systemName: "checkmark")
        iconView.isHidden = false
        activityIndicator.stopAnimating()
        titleLabel.text = ShareExtensionLocalization.text(.importSuccessTitle)
        messageLabel.text = ShareExtensionLocalization.text(.importSuccessMessage)
        doneButton.configuration?.title = ShareExtensionLocalization.text(.done)
        doneButton.isHidden = false
    }

    private func showFailureState(title: String, message: String) {
        iconView.image = UIImage(systemName: "exclamationmark")
        iconView.isHidden = false
        iconView.tintColor = .systemOrange
        iconContainerView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.14)
        activityIndicator.stopAnimating()
        titleLabel.text = title
        messageLabel.text = message
        doneButton.configuration?.title = ShareExtensionLocalization.text(.close)
        doneButton.isHidden = false
    }

    private func importSharedGPXFiles() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        let gpxProviders = providers.filter(canLoadGPX)

        guard !gpxProviders.isEmpty else {
            showFailureState(
                title: ShareExtensionLocalization.text(.noGPXTitle),
                message: ShareExtensionLocalization.text(.noGPXMessage)
            )
            return
        }

        let group = DispatchGroup()
        let importCounterQueue = DispatchQueue(label: "studio.pj.PTrack.share-extension.import-count")
        var importedCount = 0

        for provider in gpxProviders {
            guard let typeIdentifier = preferredTypeIdentifier(for: provider) else {
                continue
            }

            group.enter()
            importGPXProvider(provider, typeIdentifier: typeIdentifier) { imported in
                if imported {
                    importCounterQueue.sync {
                        importedCount += 1
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }

            let finalImportedCount = importCounterQueue.sync { importedCount }
            guard finalImportedCount > 0 else {
                self.showFailureState(
                    title: ShareExtensionLocalization.text(.importFailedTitle),
                    message: ShareExtensionLocalization.text(.importFailedMessage)
                )
                return
            }

            self.markImportReadyForContainingApp()
            self.showSuccessState()
        }
    }

    private func canLoadGPX(_ provider: NSItemProvider) -> Bool {
        preferredTypeIdentifier(for: provider) != nil
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        let gpxTypeIdentifiers = [
            UTType(filenameExtension: "gpx")?.identifier,
            Constants.gpxTypeIdentifier,
            Constants.appleGPXTypeIdentifier
        ].compactMap { $0 }

        for identifier in gpxTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            return identifier
        }

        if let gpxIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            identifier.lowercased().contains("gpx")
        }) {
            return gpxIdentifier
        }

        if provider.suggestedName?.lowercased().hasSuffix(".gpx") == true {
            let genericIdentifiers = [
                UTType.xml.identifier,
                UTType.data.identifier,
                "public.file-url"
            ]

            for identifier in genericIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
                return identifier
            }

            return provider.registeredTypeIdentifiers.first
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.xml.identifier) {
            return UTType.xml.identifier
        }

        return nil
    }

    private func importGPXProvider(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        completion: @escaping (Bool) -> Void
    ) {
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] temporaryURL, _ in
            guard let self else {
                completion(false)
                return
            }

            if let temporaryURL,
               self.copyGPXFileIntoInbox(from: temporaryURL) {
                completion(true)
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                guard let self, let data else {
                    completion(false)
                    return
                }

                completion(self.writeGPXDataIntoInbox(data))
            }
        }
    }

    private func copyGPXFileIntoInbox(from sourceURL: URL) -> Bool {
        guard let directoryURL = pendingDirectoryURL() else {
            return false
        }

        do {
            guard sourceURL.pathExtension.lowercased() == "gpx" || isLikelyGPXFile(at: sourceURL) else {
                return false
            }

            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let destinationURL = directoryURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("gpx")
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    private func writeGPXDataIntoInbox(_ data: Data) -> Bool {
        guard isLikelyGPXData(data),
              let directoryURL = pendingDirectoryURL() else {
            return false
        }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let destinationURL = directoryURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("gpx")
            try data.write(to: destinationURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func isLikelyGPXFile(at url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return false
        }

        let data = (try? fileHandle.read(upToCount: 16_384)) ?? Data()
        try? fileHandle.close()
        return isLikelyGPXData(data)
    }

    private func isLikelyGPXData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let text = String(data: data.prefix(16_384), encoding: .utf8) else {
            return false
        }

        return text.range(of: "<gpx", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func pendingDirectoryURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?
            .appendingPathComponent(Constants.pendingDirectoryName, isDirectory: true)
    }

    private func markImportReadyForContainingApp() {
        let defaults = UserDefaults(suiteName: Constants.appGroupIdentifier)
        defaults?.set(true, forKey: Constants.unseenRouteKey)
        defaults?.set(false, forKey: Constants.routeCollectionOpenRequestKey)
        defaults?.synchronize()
    }

    @objc private func handleDoneButtonTap() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private enum ShareExtensionLocalization {
    enum Key {
        case importingTitle
        case importingMessage
        case importSuccessTitle
        case importSuccessMessage
        case done
        case close
        case noGPXTitle
        case noGPXMessage
        case importFailedTitle
        case importFailedMessage
    }

    private enum Language {
        case chinese
        case japanese
        case korean
        case english
    }

    static func text(_ key: Key) -> String {
        texts[language, default: texts[.english] ?? [:]][key] ?? texts[.english]?[key] ?? ""
    }

    private static var language: Language {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? ""
        if identifier.hasPrefix("zh") {
            return .chinese
        }
        if identifier.hasPrefix("ja") {
            return .japanese
        }
        if identifier.hasPrefix("ko") {
            return .korean
        }
        return .english
    }

    private static let texts: [Language: [Key: String]] = [
        .chinese: [
            .importingTitle: "正在导入 GPX",
            .importingMessage: "马上就好",
            .importSuccessTitle: "GPX 文件导入成功",
            .importSuccessMessage: "回到 Movinn 中查看即可",
            .done: "完成",
            .close: "关闭",
            .noGPXTitle: "没有找到 GPX",
            .noGPXMessage: "请选择 GPX 文件后再分享给 Movinn",
            .importFailedTitle: "导入失败",
            .importFailedMessage: "无法导入这个 GPX 文件"
        ],
        .japanese: [
            .importingTitle: "GPX を読み込み中",
            .importingMessage: "もう少しで完了します",
            .importSuccessTitle: "GPX ファイルを読み込みました",
            .importSuccessMessage: "Movinn に戻ると確認できます",
            .done: "完了",
            .close: "閉じる",
            .noGPXTitle: "GPX が見つかりません",
            .noGPXMessage: "GPX ファイルを選んでから Movinn に共有してください",
            .importFailedTitle: "読み込み失敗",
            .importFailedMessage: "この GPX ファイルを読み込めませんでした"
        ],
        .korean: [
            .importingTitle: "GPX 가져오는 중",
            .importingMessage: "곧 완료됩니다",
            .importSuccessTitle: "GPX 파일을 가져왔습니다",
            .importSuccessMessage: "Movinn으로 돌아가 확인하세요",
            .done: "완료",
            .close: "닫기",
            .noGPXTitle: "GPX를 찾을 수 없음",
            .noGPXMessage: "GPX 파일을 선택한 뒤 Movinn으로 공유해 주세요",
            .importFailedTitle: "가져오기 실패",
            .importFailedMessage: "이 GPX 파일을 가져올 수 없습니다"
        ],
        .english: [
            .importingTitle: "Importing GPX",
            .importingMessage: "Almost there",
            .importSuccessTitle: "GPX File Imported",
            .importSuccessMessage: "Return to Movinn to view it.",
            .done: "Done",
            .close: "Close",
            .noGPXTitle: "No GPX Found",
            .noGPXMessage: "Choose a GPX file, then share it to Movinn.",
            .importFailedTitle: "Import Failed",
            .importFailedMessage: "This GPX file could not be imported."
        ]
    ]
}
