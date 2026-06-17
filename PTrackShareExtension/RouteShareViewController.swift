//
//  RouteShareViewController.swift
//  PTrackShareExtension
//
//  Created by Codex on 2026/6/17.
//

import UIKit
import UniformTypeIdentifiers

final class RouteShareViewController: UIViewController {
    private enum Constants {
        static let appGroupIdentifier = "group.studio.pj.app.PTrack"
        static let pendingDirectoryName = "PendingRoutes"
        static let unseenRouteKey = "studio.pj.PTrack.routeCollection.hasUnseenSharedRoute"
        static let appOpenURL = URL(string: "ptrack://pj.studio/routes/import")!
        static let movinnGreen = UIColor(red: 141 / 255, green: 189 / 255, blue: 0, alpha: 1)
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let openAppButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        importSharedGPXFiles()
    }

    private func configureViews() {
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 360, height: 320)

        iconView.image = UIImage(systemName: "point.topleft.down.curvedto.point.bottomright.up")
        iconView.tintColor = Constants.movinnGreen
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = ShareExtensionLocalization.text(.importRoute)
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = ShareExtensionLocalization.text(.processingGPX)
        statusLabel.textColor = .label
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        var openConfiguration = UIButton.Configuration.filled()
        openConfiguration.title = ShareExtensionLocalization.text(.openMovinn)
        openConfiguration.baseBackgroundColor = Constants.movinnGreen
        openConfiguration.baseForegroundColor = .black.withAlphaComponent(0.86)
        openConfiguration.cornerStyle = .capsule
        openConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        openAppButton.configuration = openConfiguration
        openAppButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        openAppButton.isHidden = true
        openAppButton.translatesAutoresizingMaskIntoConstraints = false
        openAppButton.addTarget(self, action: #selector(handleOpenAppButtonTap), for: .touchUpInside)

        var doneConfiguration = UIButton.Configuration.plain()
        doneConfiguration.title = ShareExtensionLocalization.text(.later)
        doneConfiguration.baseForegroundColor = .secondaryLabel
        doneConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        doneButton.configuration = doneConfiguration
        doneButton.isHidden = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(handleDoneButtonTap), for: .touchUpInside)

        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(activityIndicator)
        view.addSubview(statusLabel)
        view.addSubview(openAppButton)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 46),
            iconView.heightAnchor.constraint(equalToConstant: 46),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            openAppButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 28),
            openAppButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openAppButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            openAppButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),

            doneButton.topAnchor.constraint(equalTo: openAppButton.bottomAnchor, constant: 8),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func importSharedGPXFiles() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        let gpxProviders = providers.filter(canLoadGPX)

        guard !gpxProviders.isEmpty else {
            showResult(
                title: ShareExtensionLocalization.text(.noGPXTitle),
                message: ShareExtensionLocalization.text(.noGPXMessage),
                opensApp: false
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
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] temporaryURL, error in
                defer { group.leave() }
                guard let self, let temporaryURL, error == nil else {
                    return
                }

                if self.copyGPXFileIntoInbox(from: temporaryURL) {
                    importCounterQueue.sync {
                        importedCount += 1
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }

            let finalImportedCount = importCounterQueue.sync { importedCount }
            guard finalImportedCount > 0 else {
                self.showResult(
                    title: ShareExtensionLocalization.text(.importFailedTitle),
                    message: ShareExtensionLocalization.text(.importFailedMessage),
                    opensApp: false
                )
                return
            }

            UserDefaults(suiteName: Constants.appGroupIdentifier)?.set(true, forKey: Constants.unseenRouteKey)
            self.showResult(
                title: ShareExtensionLocalization.text(.routeSavedTitle),
                message: ShareExtensionLocalization.text(.routeSavedMessage),
                opensApp: true
            )
        }
    }

    private func canLoadGPX(_ provider: NSItemProvider) -> Bool {
        preferredTypeIdentifier(for: provider) != nil
    }

    private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        let gpxTypeIdentifier = UTType(filenameExtension: "gpx")?.identifier ?? "com.topografix.gpx"

        if provider.hasItemConformingToTypeIdentifier(gpxTypeIdentifier) {
            return gpxTypeIdentifier
        }

        return provider.registeredTypeIdentifiers.first { identifier in
            identifier.lowercased().contains("gpx")
        }
    }

    private func copyGPXFileIntoInbox(from sourceURL: URL) -> Bool {
        guard let directoryURL = pendingDirectoryURL() else {
            return false
        }

        do {
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

    private func pendingDirectoryURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier)?
            .appendingPathComponent(Constants.pendingDirectoryName, isDirectory: true)
    }

    private func showResult(title: String, message: String, opensApp: Bool) {
        titleLabel.text = title
        statusLabel.text = message
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        openAppButton.isHidden = !opensApp
        doneButton.isHidden = false

        if !opensApp {
            doneButton.configuration?.title = ShareExtensionLocalization.text(.close)
        }
    }

    @objc private func handleOpenAppButtonTap() {
        openAppButton.isEnabled = false
        extensionContext?.open(Constants.appOpenURL) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @objc private func handleDoneButtonTap() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private enum ShareExtensionLocalization {
    enum Key {
        case importRoute
        case processingGPX
        case openMovinn
        case later
        case close
        case noGPXTitle
        case noGPXMessage
        case importFailedTitle
        case importFailedMessage
        case routeSavedTitle
        case routeSavedMessage
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
            .importRoute: "导入路线",
            .processingGPX: "正在处理 GPX 文件...",
            .openMovinn: "打开 Movinn 查看",
            .later: "稍后再看",
            .close: "关闭",
            .noGPXTitle: "没有找到 GPX",
            .noGPXMessage: "请选择 GPX 文件后再分享给 Movinn",
            .importFailedTitle: "导入失败",
            .importFailedMessage: "无法导入这个 GPX 文件",
            .routeSavedTitle: "路线已收好",
            .routeSavedMessage: "打开 Movinn 后可以在路线收藏里查看"
        ],
        .japanese: [
            .importRoute: "ルートを読み込む",
            .processingGPX: "GPX ファイルを処理中...",
            .openMovinn: "Movinn で見る",
            .later: "あとで見る",
            .close: "閉じる",
            .noGPXTitle: "GPX が見つかりません",
            .noGPXMessage: "GPX ファイルを選んでから Movinn に共有してください",
            .importFailedTitle: "読み込み失敗",
            .importFailedMessage: "この GPX ファイルを読み込めませんでした",
            .routeSavedTitle: "ルートを保存しました",
            .routeSavedMessage: "Movinn を開くと、ルート保存で確認できます"
        ],
        .korean: [
            .importRoute: "경로 가져오기",
            .processingGPX: "GPX 파일 처리 중...",
            .openMovinn: "Movinn에서 보기",
            .later: "나중에 보기",
            .close: "닫기",
            .noGPXTitle: "GPX를 찾을 수 없음",
            .noGPXMessage: "GPX 파일을 선택한 뒤 Movinn으로 공유해 주세요",
            .importFailedTitle: "가져오기 실패",
            .importFailedMessage: "이 GPX 파일을 가져올 수 없습니다",
            .routeSavedTitle: "경로를 저장했습니다",
            .routeSavedMessage: "Movinn을 열면 경로 보관함에서 확인할 수 있습니다"
        ],
        .english: [
            .importRoute: "Import Route",
            .processingGPX: "Processing GPX file...",
            .openMovinn: "Open in Movinn",
            .later: "View Later",
            .close: "Close",
            .noGPXTitle: "No GPX Found",
            .noGPXMessage: "Choose a GPX file, then share it to Movinn.",
            .importFailedTitle: "Import Failed",
            .importFailedMessage: "This GPX file could not be imported.",
            .routeSavedTitle: "Route Saved",
            .routeSavedMessage: "Open Movinn to view it in Route Collection."
        ]
    ]
}
