//
//  AppReviewPromptManager.swift
//  PTrack
//
//  Created by Codex on 2026/7/10.
//

import StoreKit
import UIKit

@MainActor
final class AppReviewPromptManager {
    enum Trigger: Hashable {
        case detailPanelExpanded
        case routeShareVisited
    }

    static let shared = AppReviewPromptManager()

    private enum DefaultsKey {
        static let requestCount = "studio.pj.PTrack.appReview.requestCount"
        static let firstRequestDate = "studio.pj.PTrack.appReview.firstRequestDate"
        static let hasQualifiedTrigger = "studio.pj.PTrack.appReview.hasQualifiedTrigger"
    }

    private static let maximumRequestCount = 2
    private static let followUpDelay: TimeInterval = 3 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private var pendingTriggers = Set<Trigger>()
    private weak var homeViewController: UIViewController?
    private var retryTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    private var retryCount = 0
    private let maximumRetryDelay = 10

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
    }

    func record(_ trigger: Trigger) {
        guard requestCount == 0 else {
            return
        }
        pendingTriggers.insert(trigger)
        defaults.set(true, forKey: DefaultsKey.hasQualifiedTrigger)
    }

    func requestIfNeeded(from homeViewController: UIViewController) {
        self.homeViewController = homeViewController
        guard hasPendingRequest else {
            clearPendingState()
            return
        }

        retryCount = 0
        attemptRequest()
    }

    func resumePendingRequest() {
        guard hasPendingRequest else {
            clearPendingState()
            return
        }
        guard homeViewController != nil else {
            return
        }

        retryCount = 0
        attemptRequest()
    }

    private var hasPendingRequest: Bool {
        switch requestCount {
        case 0:
            return hasQualifiedTrigger || !pendingTriggers.isEmpty
        case 1:
            return firstRequestDate != nil
        default:
            return false
        }
    }

    private var requestCount: Int {
        min(max(defaults.integer(forKey: DefaultsKey.requestCount), 0), Self.maximumRequestCount)
    }

    private var firstRequestDate: Date? {
        defaults.object(forKey: DefaultsKey.firstRequestDate) as? Date
    }

    private var hasQualifiedTrigger: Bool {
        defaults.bool(forKey: DefaultsKey.hasQualifiedTrigger)
    }

    private var isEligibleToRequestNow: Bool {
        switch requestCount {
        case 0:
            return hasQualifiedTrigger || !pendingTriggers.isEmpty
        case 1:
            guard let firstRequestDate else {
                return false
            }
            return now().timeIntervalSince(firstRequestDate) >= Self.followUpDelay
        default:
            return false
        }
    }

    private func attemptRequest() {
        guard hasPendingRequest else {
            clearPendingState()
            return
        }

        guard isEligibleToRequestNow else {
            scheduleFollowUpIfNeeded()
            return
        }

        guard let homeViewController,
              let navigationController = homeViewController.navigationController,
              navigationController.topViewController === homeViewController,
              homeViewController.viewIfLoaded?.window != nil else {
            stopRetrying()
            return
        }

        guard UIApplication.shared.applicationState == .active,
              let windowScene = homeViewController.view.window?.windowScene,
              windowScene.activationState == .foregroundActive else {
            stopRetrying()
            return
        }

        guard homeViewController.presentedViewController == nil,
              navigationController.presentedViewController == nil,
              homeViewController.transitionCoordinator == nil,
              navigationController.transitionCoordinator == nil,
              !AppUpdateManager.shared.isHandlingUpdatePresentation else {
            scheduleRetry()
            return
        }

        let previousRequestCount = requestCount
        let newRequestCount = previousRequestCount + 1
        if previousRequestCount == 0 {
            defaults.set(now(), forKey: DefaultsKey.firstRequestDate)
            defaults.set(false, forKey: DefaultsKey.hasQualifiedTrigger)
            pendingTriggers.removeAll()
        }
        defaults.set(newRequestCount, forKey: DefaultsKey.requestCount)

        stopRetrying()
        if newRequestCount >= Self.maximumRequestCount {
            clearPendingState()
        } else {
            scheduleFollowUpIfNeeded()
        }
        AppStore.requestReview(in: windowScene)
    }

    private func scheduleFollowUpIfNeeded() {
        followUpTask?.cancel()
        followUpTask = nil

        guard requestCount == 1,
              let firstRequestDate else {
            return
        }

        let remainingDelay = firstRequestDate
            .addingTimeInterval(Self.followUpDelay)
            .timeIntervalSince(now())
        guard remainingDelay > 0 else {
            return
        }

        followUpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled, let self else {
                return
            }

            followUpTask = nil
            attemptRequest()
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else {
            return
        }

        retryCount = min(retryCount + 1, maximumRetryDelay)
        let delay = retryCount
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else {
                return
            }

            retryTask = nil
            attemptRequest()
        }
    }

    private func clearPendingState() {
        pendingTriggers.removeAll()
        defaults.set(false, forKey: DefaultsKey.hasQualifiedTrigger)
        self.homeViewController = nil
        followUpTask?.cancel()
        followUpTask = nil
        stopRetrying()
    }

    private func stopRetrying() {
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
    }
}
