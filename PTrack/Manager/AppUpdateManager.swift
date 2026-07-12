//
//  AppUpdateManager.swift
//  PTrack
//
//  Created by Codex on 2026/7/10.
//

import StoreKit
import UIKit

@MainActor
final class AppUpdateManager {
    static let shared = AppUpdateManager()

    private enum Constants {
        static let appStoreID = "6782782334"
        static let appStoreURL = URL(string: "https://apps.apple.com/app/movinn-visualize-workouts/id6782782334")!
        static let lookupURL = URL(string: "https://itunes.apple.com/lookup")!
        static let fallbackStorefrontCountry = "cn"
        static let presentationRetryDelaysInMilliseconds = [400, 800, 1_600, 3_200]
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let version: String
        let releaseNotes: String?
    }

    private struct AppStoreRelease {
        let version: String
        let releaseNotes: String?
    }

    private enum UpdateCheckResult {
        case updateAvailable(AppStoreRelease)
        case upToDate
    }

    private enum UpdateCheckError: Error {
        case appNotFound
        case invalidVersion
        case missingCurrentVersion
        case missingReleaseNotes
    }

    private var checkTask: Task<Void, Never>?
    private weak var preferredPresenter: UIViewController?
    private var shouldReportManualResult = false
    private weak var presentedUpdateAlert: UIAlertController?
    private var pendingRelease: AppStoreRelease?
    private weak var pendingPresentationPresenter: UIViewController?
    private var presentationRetryTask: Task<Void, Never>?
    private var presentationRetryAttempt = 0

    private init() {}

    var isHandlingUpdatePresentation: Bool {
        checkTask != nil
            || pendingRelease != nil
            || presentationRetryTask != nil
            || presentedUpdateAlert?.presentingViewController != nil
    }

    func checkAutomatically(in window: UIWindow?) {
        enqueueCheck(from: window?.rootViewController, reportsResult: false)
    }

    func resumePendingPresentation(in window: UIWindow?) {
        resetPresentationRetryCycle()
        if pendingPresentationPresenter == nil {
            pendingPresentationPresenter = window?.rootViewController
        }
        attemptPendingPresentation()
    }

    func checkManually(from presenter: UIViewController) {
        Toast.show(AppLocalization.text(.checkingForUpdates), in: presenter.view)
        enqueueCheck(from: presenter, reportsResult: true)
    }

    private func enqueueCheck(from presenter: UIViewController?, reportsResult: Bool) {
        if let presenter {
            preferredPresenter = presenter
        }
        shouldReportManualResult = shouldReportManualResult || reportsResult

        guard checkTask == nil else {
            return
        }

        checkTask = Task { [weak self] in
            guard let self else {
                return
            }

            let result: Result<UpdateCheckResult, Error>
            do {
                result = .success(try await performCheck())
            } catch {
                result = .failure(error)
            }

            finishCheck(with: result)
        }
    }

    private func finishCheck(with result: Result<UpdateCheckResult, Error>) {
        let presenter = preferredPresenter
        let reportsResult = shouldReportManualResult
        preferredPresenter = nil
        shouldReportManualResult = false
        checkTask = nil

        switch result {
        case .success(.updateAvailable(let release)):
            presentUpdateAlert(for: release, from: presenter)
        case .success(.upToDate):
            guard reportsResult else {
                return
            }
            Toast.show(
                AppLocalization.text(.appIsUpToDate),
                in: toastContainerView(for: presenter)
            )
        case .failure:
            guard reportsResult else {
                return
            }
            Toast.show(
                AppLocalization.text(.updateCheckFailed),
                in: toastContainerView(for: presenter)
            )
        }
    }

    private func performCheck() async throws -> UpdateCheckResult {
        guard let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            throw UpdateCheckError.missingCurrentVersion
        }

        let release = try await fetchLatestRelease()
        guard let versionComparison = Self.compareVersions(release.version, currentVersion) else {
            throw UpdateCheckError.invalidVersion
        }
        guard versionComparison == .orderedDescending else {
            return .upToDate
        }
        guard release.releaseNotes != nil else {
            throw UpdateCheckError.missingReleaseNotes
        }
        return .updateAvailable(release)
    }

    private func fetchLatestRelease() async throws -> AppStoreRelease {
        let storefront = await Storefront.current
        let storefrontCountry = storefront.flatMap {
            Self.lookupCountryCode(from: $0.countryCode)
        }
        let currentCountry = Locale.current.region?.identifier.lowercased()
        var countries = [
            storefrontCountry,
            currentCountry,
            Constants.fallbackStorefrontCountry
        ]
            .compactMap { $0 }

        var visitedCountries = Set<String>()
        countries = countries.filter { visitedCountries.insert($0).inserted }
        var releaseWithoutNotes: AppStoreRelease?
        var lastHTTPError: Error?

        for country in countries {
            let response: LookupResponse
            do {
                response = try await NetworkManager.shared.request(
                    NetworkEndpoint(
                        url: Constants.lookupURL,
                        method: .get,
                        parameters: [
                            "id": .string(Constants.appStoreID),
                            "country": .string(country)
                        ],
                        headers: [
                            "Accept": "application/json",
                            "Cache-Control": "no-cache"
                        ],
                        timeoutInterval: 15
                    )
                )
            } catch let error as NetworkError where error.statusCode != nil {
                lastHTTPError = error
                continue
            }

            guard let result = response.results.first else {
                continue
            }

            let releaseNotes = result.releaseNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let release = AppStoreRelease(
                version: result.version,
                releaseNotes: releaseNotes?.isEmpty == false ? releaseNotes : nil
            )

            if releaseWithoutNotes == nil {
                guard release.releaseNotes == nil else {
                    return release
                }
                releaseWithoutNotes = release
                continue
            }

            if let releaseWithoutNotes,
               release.releaseNotes != nil,
               Self.compareVersions(release.version, releaseWithoutNotes.version) == .orderedSame {
                return release
            }
        }

        if let releaseWithoutNotes {
            return releaseWithoutNotes
        }
        if let lastHTTPError {
            throw lastHTTPError
        }
        throw UpdateCheckError.appNotFound
    }

    private static func lookupCountryCode(from storefrontCountryCode: String) -> String? {
        guard let identifier = Locale(
            identifier: "und_\(storefrontCountryCode)"
        ).region?.identifier,
              identifier.count == 2 else {
            return nil
        }
        return identifier.lowercased()
    }

    private static func compareVersions(_ firstVersion: String, _ secondVersion: String) -> ComparisonResult? {
        guard let firstComponents = versionComponents(firstVersion),
              let secondComponents = versionComponents(secondVersion) else {
            return nil
        }

        let componentCount = max(firstComponents.count, secondComponents.count)
        for index in 0..<componentCount {
            let firstComponent = index < firstComponents.count
                ? firstComponents[index]
                : 0
            let secondComponent = index < secondComponents.count
                ? secondComponents[index]
                : 0

            if firstComponent != secondComponent {
                return firstComponent > secondComponent ? .orderedDescending : .orderedAscending
            }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let rawComponents = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !rawComponents.isEmpty else {
            return nil
        }

        var components: [Int] = []
        components.reserveCapacity(rawComponents.count)
        for rawComponent in rawComponents {
            guard let component = Int(rawComponent) else {
                return nil
            }
            components.append(component)
        }
        return components
    }

    private func presentUpdateAlert(
        for release: AppStoreRelease,
        from preferredPresenter: UIViewController?
    ) {
        resetPresentationRetryCycle()
        pendingRelease = release
        if let preferredPresenter,
           preferredPresenter.viewIfLoaded?.window != nil {
            pendingPresentationPresenter = preferredPresenter
        }
        attemptPendingPresentation()
    }

    private func attemptPendingPresentation() {
        guard let release = pendingRelease else {
            resetPresentationRetryCycle()
            return
        }

        if let presentedUpdateAlert,
           presentedUpdateAlert.presentingViewController != nil {
            pendingRelease = nil
            pendingPresentationPresenter = nil
            resetPresentationRetryCycle()
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            return
        }

        guard let presenter = availablePresenter(),
              !(presenter is UIAlertController),
              !presenter.isBeingDismissed,
              presenter.transitionCoordinator == nil else {
            schedulePresentationRetry()
            return
        }

        let alertController = UIAlertController(
            title: AppLocalization.text(.updateAvailableTitle),
            message: release.releaseNotes,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.updateDismiss),
            style: .cancel
        ))

        let updateAction = UIAlertAction(
            title: AppLocalization.text(.updateNow),
            style: .default
        ) { _ in
            UIApplication.shared.open(Constants.appStoreURL)
        }
        alertController.addAction(updateAction)
        alertController.preferredAction = updateAction

        presentedUpdateAlert = alertController
        presenter.present(alertController, animated: true)

        guard alertController.presentingViewController != nil else {
            presentedUpdateAlert = nil
            schedulePresentationRetry()
            return
        }

        pendingRelease = nil
        pendingPresentationPresenter = nil
        resetPresentationRetryCycle()
    }

    private func schedulePresentationRetry() {
        guard presentationRetryTask == nil,
              presentationRetryAttempt < Constants.presentationRetryDelaysInMilliseconds.count else {
            return
        }

        let delay = Constants.presentationRetryDelaysInMilliseconds[presentationRetryAttempt]
        presentationRetryAttempt += 1
        presentationRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else {
                return
            }

            presentationRetryTask = nil
            attemptPendingPresentation()
        }
    }

    private func resetPresentationRetryCycle() {
        presentationRetryTask?.cancel()
        presentationRetryTask = nil
        presentationRetryAttempt = 0
    }

    private func availablePresenter() -> UIViewController? {
        if let pendingPresentationPresenter,
           pendingPresentationPresenter.viewIfLoaded?.window != nil,
           let presenter = topViewController(from: pendingPresentationPresenter),
           presenter.viewIfLoaded?.window != nil {
            return presenter
        }

        guard let presenter = topViewController(from: activeRootViewController),
              presenter.viewIfLoaded?.window != nil else {
            return nil
        }
        return presenter
    }

    private func toastContainerView(for preferredPresenter: UIViewController?) -> UIView? {
        guard let preferredPresenter,
              preferredPresenter.viewIfLoaded?.window != nil else {
            return nil
        }
        return preferredPresenter.view
    }

    private var activeRootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private func topViewController(from viewController: UIViewController?) -> UIViewController? {
        if let presentedViewController = viewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        if let navigationController = viewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        return viewController
    }
}
