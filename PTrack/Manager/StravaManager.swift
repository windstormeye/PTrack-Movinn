//
//  StravaManager.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import AuthenticationServices
import CoreLocation
import Foundation
import HealthKit

final class StravaManager: NSObject {
    static let shared = StravaManager()

    private static let placeholderPublicationBatchSize = 100
    private static let detailPublicationBatchSize = 10

    private let define = StravaDefine()
    private let defaults: UserDefaults
    private let networkManager: NetworkManager
    private let syncStateStore: WorkoutSyncStateStore
    private let decoder = JSONDecoder()
    private var webAuthenticationSession: ASWebAuthenticationSession?

    private enum DefaultsKey {
        static let credentials = "studio.pj.PTrack.strava.credentials"
        static let authorizationAttempted = "studio.pj.PTrack.strava.authorizationAttempted"
        static let authorizationNeedsReauthorization = "studio.pj.PTrack.strava.authorizationNeedsReauthorization"
    }

    enum AuthorizationState {
        case notDetermined
        case authorized
        case needsReauthorization
    }

    struct ActivityReconciliationSnapshot: Codable, Sendable {
        let athleteID: Int64
        let activityIDs: Set<Int64>
        let capturedAt: Date
        let listingUpperBound: Date
        let coversFullHistory: Bool
        let didReachNaturalEnd: Bool
        let didUseCompleteReadScope: Bool

        /// Only a full-history listing that naturally reached its end is safe
        /// to participate in destructive reconciliation. The caller must still
        /// confirm an absence in two consecutive authoritative snapshots.
        var isAuthoritative: Bool {
            coversFullHistory && didReachNaturalEnd && didUseCompleteReadScope
        }
    }

    struct RateLimitInfo: Sendable {
        struct Window: Sendable {
            let limit: Int
            let usage: Int
            let resetDate: Date

            nonisolated var remaining: Int {
                max(limit - usage, 0)
            }
        }

        let shortTerm: Window?
        let daily: Window?
        let readShortTerm: Window?
        let readDaily: Window?
        let retryAfterDate: Date?
        let observedAt: Date

        var recommendedRetryDate: Date? {
            let exhaustedResetDates = [shortTerm, daily, readShortTerm, readDaily]
                .compactMap { $0 }
                .compactMap { window -> Date? in
                    let reserve: Int
                    if window.resetDate.timeIntervalSince(observedAt) <= 15 * 60 + 5 {
                        reserve = max(10, Int(ceil(Double(window.limit) * 0.1)))
                    } else {
                        reserve = max(50, Int(ceil(Double(window.limit) * 0.05)))
                    }
                    return window.remaining <= reserve ? window.resetDate : nil
                }
            return (exhaustedResetDates + [retryAfterDate].compactMap { $0 }).max()
        }
    }

    struct LoadResult {
        let reconciliationSnapshot: ActivityReconciliationSnapshot
        let workouts: [TrackedWorkout]
        /// IDs whose stream request or conversion failed and should be retried.
        let failedActivityIDs: Set<Int64>
        /// IDs whose successful stream response cannot form a route and should not be retried forever.
        let terminalActivityIDs: Set<Int64>
        /// IDs intentionally left for a later pass to stay within a safe request budget.
        let deferredActivityIDs: Set<Int64>
        /// Latest server quota state observed during this pass.
        let rateLimitInfo: RateLimitInfo?
        /// Earliest safe time for a deferred follow-up pass.
        let retryAfterDate: Date?
        /// All requests counted against this pass, including token refreshes and retries.
        let requestCount: Int
        /// Requests still available after applying both the local cap and the
        /// server-reported safety reserve.
        let remainingRequestBudget: Int

        var athleteID: Int64 {
            reconciliationSnapshot.athleteID
        }

        var didLoadCompleteActivitySummary: Bool {
            reconciliationSnapshot.didReachNaturalEnd
        }

        var didUseCompleteActivityReadScope: Bool {
            reconciliationSnapshot.didUseCompleteReadScope
        }

        var failedActivityCount: Int {
            failedActivityIDs.count
        }

        var deferredActivityCount: Int {
            deferredActivityIDs.count
        }

        var terminalActivityCount: Int {
            terminalActivityIDs.count
        }

        var didCompleteAuthoritativeSummary: Bool {
            reconciliationSnapshot.isAuthoritative
        }

        var needsDeferredRetry: Bool {
            !deferredActivityIDs.isEmpty
                || !didLoadCompleteActivitySummary
        }
    }

    private final class RequestBudget {
        private let maximumRequestCount: Int
        private(set) var requestCount = 0
        private(set) var rateLimitInfo: RateLimitInfo?

        init(maximumRequestCount: Int) {
            self.maximumRequestCount = max(maximumRequestCount, 0)
        }

        var canStartRequest: Bool {
            availableRequestCount > 0
        }

        var availableRequestCount: Int {
            let localRemaining = max(maximumRequestCount - requestCount, 0)
            guard let rateLimitInfo else {
                return localRemaining
            }

            let serverRemaining = Self.safeServerRemaining(rateLimitInfo)
            return min(localRemaining, serverRemaining ?? localRemaining)
        }

        var retryAfterDate: Date? {
            let localReset = requestCount >= maximumRequestCount
                ? Self.nextShortTermReset(after: Date())
                : nil
            let serverReset = rateLimitInfo.flatMap(Self.safeRetryDate)
            return [localReset, serverReset].compactMap { $0 }.max()
        }

        func beginRequest() throws {
            guard canStartRequest else {
                throw StravaManagerError.requestBudgetExhausted(retryAfter: retryAfterDate)
            }
            requestCount += 1
        }

        func observe(headers: [String: String], at date: Date = Date()) {
            guard !headers.isEmpty else {
                return
            }

            let standard = Self.ratePair(
                limit: Self.headerValue("X-RateLimit-Limit", in: headers),
                usage: Self.headerValue("X-RateLimit-Usage", in: headers),
                at: date
            )
            let read = Self.ratePair(
                limit: Self.headerValue("X-ReadRateLimit-Limit", in: headers),
                usage: Self.headerValue("X-ReadRateLimit-Usage", in: headers),
                at: date
            )
            let retryAfterDate = Self.retryAfterDate(
                from: Self.headerValue("Retry-After", in: headers),
                relativeTo: date
            )
            guard standard != nil || read != nil || retryAfterDate != nil else {
                return
            }

            rateLimitInfo = RateLimitInfo(
                shortTerm: standard?.shortTerm ?? rateLimitInfo?.shortTerm,
                daily: standard?.daily ?? rateLimitInfo?.daily,
                readShortTerm: read?.shortTerm ?? rateLimitInfo?.readShortTerm,
                readDaily: read?.daily ?? rateLimitInfo?.readDaily,
                retryAfterDate: [rateLimitInfo?.retryAfterDate, retryAfterDate]
                    .compactMap { $0 }
                    .max(),
                observedAt: date
            )
        }

        private nonisolated static func safeServerRemaining(_ info: RateLimitInfo) -> Int? {
            let windows = [info.shortTerm, info.daily, info.readShortTerm, info.readDaily]
                .compactMap { $0 }
            guard !windows.isEmpty else {
                return info.retryAfterDate.map { $0 > Date() ? 0 : Int.max }
            }

            return windows.map { window in
                max(window.remaining - safetyReserve(for: window, observedAt: info.observedAt), 0)
            }.min()
        }

        private nonisolated static func safeRetryDate(_ info: RateLimitInfo) -> Date? {
            let safetyResetDates = [info.shortTerm, info.daily, info.readShortTerm, info.readDaily]
                .compactMap { $0 }
                .compactMap { window -> Date? in
                    window.remaining <= safetyReserve(for: window, observedAt: info.observedAt)
                        ? window.resetDate
                        : nil
                }
            return (safetyResetDates + [info.retryAfterDate].compactMap { $0 }).max()
        }

        private nonisolated static func safetyReserve(
            for window: RateLimitInfo.Window,
            observedAt: Date
        ) -> Int {
            if window.resetDate.timeIntervalSince(observedAt) <= 15 * 60 + 5 {
                return max(10, Int(ceil(Double(window.limit) * 0.1)))
            }
            return max(50, Int(ceil(Double(window.limit) * 0.05)))
        }

        private nonisolated static func nextShortTermReset(after date: Date) -> Date {
            Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / 900) + 1) * 900 + 1)
        }

        private nonisolated static func ratePair(
            limit: String?,
            usage: String?,
            at date: Date
        ) -> (shortTerm: RateLimitInfo.Window, daily: RateLimitInfo.Window)? {
            guard let limits = commaSeparatedIntegers(limit),
                  let usages = commaSeparatedIntegers(usage),
                  limits.count >= 2,
                  usages.count >= 2 else {
                return nil
            }

            let shortTermReset = nextShortTermReset(after: date)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let dailyReset = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
                ?? date.addingTimeInterval(24 * 60 * 60)
            return (
                RateLimitInfo.Window(limit: limits[0], usage: usages[0], resetDate: shortTermReset),
                RateLimitInfo.Window(limit: limits[1], usage: usages[1], resetDate: dailyReset)
            )
        }

        private nonisolated static func commaSeparatedIntegers(_ value: String?) -> [Int]? {
            guard let value else {
                return nil
            }
            let values = value.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            return values.isEmpty ? nil : values
        }

        private nonisolated static func headerValue(
            _ name: String,
            in headers: [String: String]
        ) -> String? {
            headers[name.lowercased()]
        }

        private nonisolated static func retryAfterDate(from value: String?, relativeTo date: Date) -> Date? {
            guard let value else {
                return nil
            }
            if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
                return date.addingTimeInterval(max(seconds, 0))
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter.date(from: value)
        }
    }

    init(defaults: UserDefaults = .standard, networkManager: NetworkManager = .shared) {
        self.defaults = defaults
        self.networkManager = networkManager
        syncStateStore = WorkoutSyncStateStore(defaults: defaults)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        super.init()
    }

    var hasStoredAuthorization: Bool {
        storedCredentials() != nil
    }

    var storedAthleteID: Int64? {
        storedCredentials()?.athleteID
    }

    var authorizationState: AuthorizationState {
        if storedCredentials() != nil {
            return .authorized
        }

        if defaults.bool(forKey: DefaultsKey.authorizationNeedsReauthorization)
            || defaults.bool(forKey: DefaultsKey.authorizationAttempted) {
            return .needsReauthorization
        }

        return .notDetermined
    }

    func loadTrackedWorkoutResult(
        after startDate: Date? = nil,
        excludingStravaActivityIDs: Set<Int64> = [],
        pageLimit: Int? = nil,
        perPage: Int = 200,
        requestLimit: Int = 80,
        onNewDataDetected: ((Int) async -> Void)? = nil,
        onTrackedWorkouts: (([TrackedWorkout]) async -> Void)? = nil
    ) async throws -> LoadResult {
        guard let syncCredentials = storedCredentials(),
              let expectedAthleteID = syncCredentials.athleteID else {
            throw StravaManagerError.notAuthorized
        }
        guard let scope = syncCredentials.scope,
              Self.scopeComponents(scope).contains("activity:read_all") else {
            log("stored authorization is missing activity:read_all; requiring reauthorization")
            guard clearCredentialsIfCurrent(
                syncCredentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        }

        log(
            "load tracked workouts started, after: \(Self.debugDateString(startDate)), excluded cached IDs: \(excludingStravaActivityIDs.count), pageLimit: \(pageLimit.map(String.init) ?? "nil"), perPage: \(perPage), total request limit: \(requestLimit)"
        )
        let requestBudget = RequestBudget(maximumRequestCount: requestLimit)
        let activityListing = try await loadActivities(
            after: startDate,
            pageLimit: pageLimit,
            perPage: perPage,
            expectedAthleteID: expectedAthleteID,
            requestBudget: requestBudget
        )
        let activities = activityListing.activities
        log("loaded summary activities: \(activities.count)")

        let unsupportedCount = activities.filter { $0.supportedSport == nil }.count
        let withoutRouteHintCount = activities.filter { $0.supportedSport != nil && !$0.hasRouteHint }.count
        let alreadyCachedCount = activities.filter { excludingStravaActivityIDs.contains($0.id) }.count
        let summaryActivityIDs = Set(activities.map(\.id))
        let supportedActivities = activities.filter {
            $0.supportedSport != nil &&
            $0.hasRouteHint &&
            !excludingStravaActivityIDs.contains($0.id)
        }
        log(
            "filtered activities, route candidates: \(supportedActivities.count), unsupported: \(unsupportedCount), without route hint: \(withoutRouteHintCount), already cached: \(alreadyCachedCount)"
        )
        if !supportedActivities.isEmpty {
            await onNewDataDetected?(supportedActivities.count)
        }

        let activitiesToImport = Array(
            supportedActivities.prefix(requestBudget.availableRequestCount)
        )
        var deferredActivityIDs = Set(
            supportedActivities.dropFirst(activitiesToImport.count).map(\.id)
        )
        if !deferredActivityIDs.isEmpty {
            log(
                "deferred \(deferredActivityIDs.count) activity stream request(s) to a later import pass"
            )
        }

        // Publish lightweight summary-route placeholders for every missing
        // activity before requesting detailed streams. This restores a stable
        // activity count in one summary pass while detailed stream enrichment
        // remains bounded by the request budget.
        var trackedWorkoutsByActivityID: [Int64: TrackedWorkout] = [:]
        trackedWorkoutsByActivityID.reserveCapacity(supportedActivities.count)
        var terminalActivityIDs = Set<Int64>()
        var failedActivityIDs = Set<Int64>()
        var placeholderBatch: [TrackedWorkout] = []
        placeholderBatch.reserveCapacity(Self.placeholderPublicationBatchSize)
        for activity in supportedActivities {
            guard let placeholder = TrackedWorkout(
                stravaSummaryActivity: activity,
                isTerminal: false,
                athleteID: expectedAthleteID
            ) else {
                failedActivityIDs.insert(activity.id)
                log("summary activity \(activity.id) could not form a route placeholder")
                continue
            }

            trackedWorkoutsByActivityID[activity.id] = placeholder
            placeholderBatch.append(placeholder)
            if placeholderBatch.count == Self.placeholderPublicationBatchSize {
                await onTrackedWorkouts?(placeholderBatch)
                placeholderBatch.removeAll(keepingCapacity: true)
            }
        }
        if !placeholderBatch.isEmpty {
            await onTrackedWorkouts?(placeholderBatch)
        }

        var importedActivityIDs = Set<Int64>()
        var detailBatch: [TrackedWorkout] = []
        detailBatch.reserveCapacity(Self.detailPublicationBatchSize)

        activityImportLoop: for (index, activity) in activitiesToImport.enumerated() {
            guard importedActivityIDs.insert(activity.id).inserted else {
                log("skipping duplicate activity ID in current import: \(activity.id)")
                continue
            }

            do {
                log(
                    "loading streams \(index + 1)/\(activitiesToImport.count), activity: \(activity.id), sport: \(activity.sportType ?? activity.type ?? "unknown"), start: \(Self.debugDateString(activity.startDate))"
                )
                let streams = try await loadActivityStreams(
                    activityID: activity.id,
                    expectedAthleteID: expectedAthleteID,
                    requestBudget: requestBudget
                )
                if let workout = TrackedWorkout(
                    stravaActivity: activity,
                    streams: streams,
                    athleteID: expectedAthleteID
                ) {
                    trackedWorkoutsByActivityID[activity.id] = workout
                    failedActivityIDs.remove(activity.id)
                    detailBatch.append(workout)
                    if detailBatch.count == Self.detailPublicationBatchSize {
                        await onTrackedWorkouts?(detailBatch)
                        detailBatch.removeAll(keepingCapacity: true)
                    }
                    log(
                        "converted activity \(activity.id), coordinates: \(workout.coordinates.count), distance: \(workout.distanceMeters)"
                    )
                } else {
                    terminalActivityIDs.insert(activity.id)
                    failedActivityIDs.remove(activity.id)
                    if let placeholder = TrackedWorkout(
                        stravaSummaryActivity: activity,
                        isTerminal: true,
                        athleteID: expectedAthleteID
                    ) {
                        trackedWorkoutsByActivityID[activity.id] = placeholder
                        detailBatch.append(placeholder)
                        if detailBatch.count == Self.detailPublicationBatchSize {
                            await onTrackedWorkouts?(detailBatch)
                            detailBatch.removeAll(keepingCapacity: true)
                        }
                    }
                    log(
                        "skipped terminal activity \(activity.id), its successful stream response did not contain enough route data"
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let managerError = error as? StravaManagerError,
                   case .authorizationChangedDuringImport = managerError {
                    throw managerError
                }
                if Self.requiresReauthorization(error) {
                    if !detailBatch.isEmpty {
                        await onTrackedWorkouts?(detailBatch)
                        detailBatch.removeAll(keepingCapacity: true)
                    }
                    throw error
                }

                if Self.shouldStopImportPass(after: error) {
                    let remainingActivityIDs = activitiesToImport[index...].map(\.id)
                    if Self.isRateLimitFailure(error) || Self.isRequestBudgetFailure(error) {
                        deferredActivityIDs.formUnion(remainingActivityIDs)
                        log(
                            "request budget exhausted while loading activity \(activity.id); deferred \(remainingActivityIDs.count) activity/activities until \(Self.debugDateString(requestBudget.retryAfterDate))"
                        )
                    } else {
                        failedActivityIDs.formUnion(remainingActivityIDs)
                        log(
                            "transient import failure while loading activity \(activity.id); stopped this pass with \(remainingActivityIDs.count) activity/activities left for a later retry: \(error.localizedDescription)"
                        )
                    }
                    break activityImportLoop
                }

                failedActivityIDs.insert(activity.id)
                log("failed to load streams for activity \(activity.id): \(error.localizedDescription)")
            }
        }

        if !detailBatch.isEmpty {
            await onTrackedWorkouts?(detailBatch)
        }

        try validateStoredAuthorization(expectedAthleteID: expectedAthleteID)
        let sortedWorkouts = trackedWorkoutsByActivityID.values.sorted { $0.startDate > $1.startDate }
        log(
            "load tracked workouts completed, converted routes: \(sortedWorkouts.count), activity failures: \(failedActivityIDs.count), terminal: \(terminalActivityIDs.count), deferred: \(deferredActivityIDs.count), requests: \(requestBudget.requestCount)"
        )
        return LoadResult(
            reconciliationSnapshot: ActivityReconciliationSnapshot(
                athleteID: expectedAthleteID,
                activityIDs: summaryActivityIDs,
                capturedAt: Date(),
                listingUpperBound: activityListing.upperBound,
                coversFullHistory: startDate == nil,
                didReachNaturalEnd: activityListing.didReachEnd,
                didUseCompleteReadScope: true
            ),
            workouts: sortedWorkouts,
            failedActivityIDs: failedActivityIDs,
            terminalActivityIDs: terminalActivityIDs,
            deferredActivityIDs: deferredActivityIDs,
            rateLimitInfo: requestBudget.rateLimitInfo,
            retryAfterDate: requestBudget.retryAfterDate,
            requestCount: requestBudget.requestCount,
            remainingRequestBudget: requestBudget.availableRequestCount
        )
    }

    func authorize(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> StravaStoredCredentials {
        try validateRedirectURI()

        guard let authorizationURL = authorizationURL() else {
            throw StravaManagerError.invalidURL
        }
        let credentialsBeforeAuthorization = storedCredentials()

        log("starting authorization session: \(authorizationURL.absoluteString)")
        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: define.CallbackScheme
            ) { [weak self] callbackURL, error in
                guard let self else {
                    continuation.resume(throwing: StravaManagerError.cancelled)
                    return
                }

                self.webAuthenticationSession = nil

                if let error {
                    self.log("authorization session failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    self.log("authorization session finished without callback URL")
                    continuation.resume(throwing: StravaManagerError.missingAuthorizationCode)
                    return
                }

                self.log("authorization callback received: \(callbackURL.absoluteString)")
                Task {
                    do {
                        let credentials = try await self.handleAuthorizationCallback(
                            callbackURL,
                            credentialsBeforeAuthorization: credentialsBeforeAuthorization
                        )
                        continuation.resume(returning: credentials)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            authSession.presentationContextProvider = presentationContextProvider
            authSession.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = authSession

            if !authSession.start() {
                webAuthenticationSession = nil
                log("authorization session failed to start")
                continuation.resume(throwing: StravaManagerError.authorizationSessionFailedToStart)
            }
        }
    }

    private func validateRedirectURI() throws {
        guard let components = URLComponents(string: define.RedirectURI),
              components.scheme == define.CallbackScheme,
              components.host == define.AuthorizationCallbackDomain else {
            throw StravaManagerError.invalidRedirectURI(
                redirectURI: define.RedirectURI,
                callbackDomain: define.AuthorizationCallbackDomain
            )
        }
    }

    private func authorizationURL() -> URL? {
        var components = URLComponents(string: define.AuthorizationURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: define.ClientID),
            URLQueryItem(name: "redirect_uri", value: define.RedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: define.AuthorizationScope)
        ]
        return components?.url
    }

    private func handleAuthorizationCallback(
        _ callbackURL: URL,
        credentialsBeforeAuthorization: StravaStoredCredentials?
    ) async throws -> StravaStoredCredentials {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw StravaManagerError.missingAuthorizationCode
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            markAuthorizationNeedsReauthorization()
            throw StravaManagerError.authorizationDenied(error)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            markAuthorizationNeedsReauthorization()
            throw StravaManagerError.missingAuthorizationCode
        }

        let grantedScope = queryItems.first(where: { $0.name == "scope" })?.value
        log("authorization callback parsed, scope: \(grantedScope ?? "nil"), code: <redacted>")
        guard let grantedScope,
              Self.scopeComponents(grantedScope).contains("activity:read_all") else {
            log("authorization did not grant activity:read_all; requiring reauthorization")
            if let credentialsBeforeAuthorization {
                if !clearCredentialsIfCurrent(
                    credentialsBeforeAuthorization,
                    markReauthorizationRequired: true
                ) {
                    markAuthorizationNeedsReauthorization()
                }
            } else {
                markAuthorizationNeedsReauthorization()
            }
            throw StravaManagerError.reauthorizationRequired
        }
        return try await exchangeAuthorizationCode(
            code,
            grantedScope: grantedScope,
            previousAthleteID: credentialsBeforeAuthorization?.athleteID
                ?? syncStateStore.lastAuthorizedStravaAthleteID.flatMap(Int64.init)
        )
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        grantedScope: String?,
        previousAthleteID: Int64?
    ) async throws -> StravaStoredCredentials {
        log("exchanging authorization code for token")
        let response: StravaOAuthTokenResponse = try await sendTokenRequest(parameters: [
            "client_id": define.ClientID,
            "client_secret": define.ClientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ])

        let credentials = StravaStoredCredentials(
            tokenType: response.tokenType,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            scope: grantedScope,
            athleteID: response.athlete?.id
        )
        if let previousAthleteID,
           let currentAthleteID = credentials.athleteID {
            let previousCredentialOwner = String(previousAthleteID)
            let currentCredentialOwner = String(currentAthleteID)
            let existingHandoff = syncStateStore.stravaAuthorizationHandoff
            if previousCredentialOwner != currentCredentialOwner {
                let durableCacheOwner = syncStateStore.cachedStravaAthleteID
                    ?? syncStateStore.lastSynchronizedStravaAthleteID
                let canExtendExistingHandoff = durableCacheOwner == nil
                    && existingHandoff?.authorizedAthleteIDs.contains(previousCredentialOwner) == true
                let cacheOwner = durableCacheOwner
                    ?? (canExtendExistingHandoff ? existingHandoff?.cacheOwnerAthleteID : nil)
                    ?? previousCredentialOwner
                var authorizedAthleteIDs = canExtendExistingHandoff
                    ? existingHandoff?.authorizedAthleteIDs ?? []
                    : []
                authorizedAthleteIDs.insert(currentCredentialOwner)

                // Persist the account handoff before replacing credentials. If
                // the process exits during a rapid A -> B -> C (or A -> B -> A)
                // chain, every still-possible credential owner remains covered.
                syncStateStore.stravaAuthorizationHandoff = .init(
                    cacheOwnerAthleteID: cacheOwner,
                    authorizedAthleteIDs: authorizedAthleteIDs,
                    capturedAt: Date()
                )
            }
        }
        saveCredentials(credentials)
        log(
            "authorization token saved, athlete: \(credentials.athleteID.map(String.init) ?? "nil"), expiresAt: \(Self.debugDateString(credentials.expiresAt)), scope: \(credentials.scope ?? "nil")"
        )
        return credentials
    }

    private func refreshCredentials(
        _ credentials: StravaStoredCredentials,
        expectedAthleteID: Int64,
        requestBudget: RequestBudget? = nil
    ) async throws -> StravaStoredCredentials {
        guard credentials.athleteID == expectedAthleteID,
              let storedCredentialsBeforeRefresh = storedCredentials(),
              storedCredentialsBeforeRefresh.athleteID == expectedAthleteID,
              let scopeBeforeRefresh = storedCredentialsBeforeRefresh.scope,
              Self.scopeComponents(scopeBeforeRefresh).contains("activity:read_all"),
              storedCredentialsBeforeRefresh.accessToken == credentials.accessToken,
              storedCredentialsBeforeRefresh.refreshToken == credentials.refreshToken else {
            throw StravaManagerError.authorizationChangedDuringImport
        }
        guard !credentials.refreshToken.isEmpty else {
            log("stored refresh token is empty; clearing authorization")
            guard clearCredentialsIfCurrent(
                credentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        }

        log("refreshing access token, previous expiresAt: \(Self.debugDateString(credentials.expiresAt))")
        let response: StravaOAuthTokenResponse
        do {
            response = try await sendTokenRequest(parameters: [
                "client_id": define.ClientID,
                "client_secret": define.ClientSecret,
                "grant_type": "refresh_token",
                "refresh_token": credentials.refreshToken
            ], requestBudget: requestBudget)
        } catch let error as NetworkError where Self.isAuthorizationFailure(error) {
            log("access token refresh failed because authorization is invalid; clearing stored credentials")
            guard clearCredentialsIfCurrent(
                credentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        } catch {
            throw error
        }

        // A browser authorization can finish while the refresh request is in
        // flight. Never overwrite those newer credentials with this response.
        guard let storedCredentialsAfterRefresh = storedCredentials(),
              storedCredentialsAfterRefresh.athleteID == expectedAthleteID,
              let scopeAfterRefresh = storedCredentialsAfterRefresh.scope,
              Self.scopeComponents(scopeAfterRefresh).contains("activity:read_all"),
              storedCredentialsAfterRefresh.accessToken == credentials.accessToken,
              storedCredentialsAfterRefresh.refreshToken == credentials.refreshToken else {
            throw StravaManagerError.authorizationChangedDuringImport
        }
        if let responseAthleteID = response.athlete?.id,
           responseAthleteID != expectedAthleteID {
            throw StravaManagerError.authorizationChangedDuringImport
        }

        let refreshedCredentials = StravaStoredCredentials(
            tokenType: response.tokenType,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            scope: credentials.scope,
            athleteID: response.athlete?.id ?? credentials.athleteID
        )
        saveCredentials(refreshedCredentials)
        log("access token refreshed, expiresAt: \(Self.debugDateString(refreshedCredentials.expiresAt))")
        return refreshedCredentials
    }

    private func sendTokenRequest<Response: Decodable>(
        parameters: [String: String],
        requestBudget: RequestBudget? = nil
    ) async throws -> Response {
        let endpoint = try NetworkEndpoint(
            urlString: define.TokenURL,
            method: .post,
            parameters: Self.optionalParameters(parameters),
            parameterEncoding: .formURLEncoded
        )
        let grantType = parameters["grant_type"] ?? "unknown"
        log("token request started, grant_type: \(grantType)")
        do {
            try requestBudget?.beginRequest()
            let response: NetworkResponse<Response> = try await networkManager.response(endpoint, decoder: decoder)
            requestBudget?.observe(headers: response.headers)
            log("token request completed, grant_type: \(grantType), status: \(response.statusCode), bytes: \(response.data.count)")
            return response.value
        } catch {
            if let networkError = error as? NetworkError {
                requestBudget?.observe(headers: networkError.responseHeaders)
            }
            log("token request failed, grant_type: \(grantType), error: \(error.localizedDescription)")
            throw error
        }
    }

    private func loadActivities(
        after startDate: Date?,
        pageLimit: Int?,
        perPage: Int,
        expectedAthleteID: Int64,
        requestBudget: RequestBudget
    ) async throws -> StravaActivityListing {
        let pageSize = min(max(perPage, 1), 200)
        var allActivities: [StravaSummaryActivity] = []
        var loadedActivityIDs = Set<Int64>()
        var page = 1
        var didReachEnd = false
        let pagingSnapshotDate = Date()
        var beforeEpoch = Int(ceil(pagingSnapshotDate.timeIntervalSince1970)) + 1

        log(
            "activity paging started, after: \(Self.debugDateString(startDate)), pageLimit: \(pageLimit.map(String.init) ?? "nil"), perPage: \(pageSize)"
        )
        while pageLimit.map({ page <= max($0, 1) }) ?? true {
            guard requestBudget.canStartRequest else {
                log("activity paging deferred because the request budget is exhausted")
                break
            }

            var parameters: [String: NetworkParameterValue?] = [
                // Keep page fixed and move a time cursor. Offset pagination can
                // skip a record when an activity is removed while paging.
                "page": .int(1),
                "per_page": .int(pageSize),
                "before": .int(beforeEpoch)
            ]
            if let startDate {
                parameters["after"] = .int(Int(startDate.timeIntervalSince1970))
            }

            let endpoint = try NetworkEndpoint(
                urlString: "\(define.APIBaseURL)/athlete/activities",
                method: .get,
                parameters: parameters,
                parameterEncoding: .query
            )
            log("activity page \(page) request queued")
            let pageActivities: [StravaSummaryActivity]
            do {
                pageActivities = try await authorizedJSON(
                    endpoint,
                    expectedAthleteID: expectedAthleteID,
                    requestBudget: requestBudget
                )
            } catch {
                if Self.isRateLimitFailure(error) || Self.isRequestBudgetFailure(error) {
                    log(
                        "activity paging deferred after page \(page - 1), retry after: \(Self.debugDateString(requestBudget.retryAfterDate))"
                    )
                    break
                }
                throw error
            }
            var newActivityCount = 0
            for activity in pageActivities where loadedActivityIDs.insert(activity.id).inserted {
                allActivities.append(activity)
                newActivityCount += 1
            }
            log(
                "activity page \(page) loaded, received: \(pageActivities.count), new after dedupe: \(newActivityCount), total: \(allActivities.count)"
            )

            if pageActivities.count < pageSize {
                log("activity paging finished because page \(page) returned less than page size")
                didReachEnd = true
                break
            }
            guard let oldestStartEpoch = pageActivities.compactMap(\.startDate)
                .map({ Int($0.timeIntervalSince1970) })
                .min(),
                  oldestStartEpoch < beforeEpoch else {
                log("activity paging stopped because its time cursor did not advance")
                break
            }

            // `before` is exclusive. Keep a one-second overlap so activities
            // sharing the page-boundary timestamp cannot be skipped. A full
            // overlap page with no new IDs means the boundary itself is
            // ambiguous (for example 200 activities in the same second), so
            // stop with a non-authoritative listing rather than skip records.
            let overlappingBeforeEpoch = oldestStartEpoch + 1
            guard newActivityCount > 0,
                  overlappingBeforeEpoch < beforeEpoch else {
                log("activity paging stopped at an ambiguous timestamp boundary")
                break
            }
            beforeEpoch = overlappingBeforeEpoch
            page += 1
        }

        log(
            "activity paging completed, total unique activities: \(allActivities.count), reached end: \(didReachEnd)"
        )
        return StravaActivityListing(
            activities: allActivities,
            didReachEnd: didReachEnd,
            upperBound: pagingSnapshotDate
        )
    }

    private func loadActivityStreams(
        activityID: Int64,
        expectedAthleteID: Int64,
        requestBudget: RequestBudget
    ) async throws -> StravaActivityStreamSet {
        let endpoint = try NetworkEndpoint(
            urlString: "\(define.APIBaseURL)/activities/\(activityID)/streams",
            method: .get,
            parameters: [
                "keys": .stringArray(["time", "latlng", "altitude", "velocity_smooth", "distance", "grade_smooth", "heartrate", "cadence", "watts", "temp"]),
                "key_by_type": .bool(true)
            ],
            parameterEncoding: .query
        )
        let streams: StravaActivityStreamSet = try await authorizedJSON(
            endpoint,
            expectedAthleteID: expectedAthleteID,
            requestBudget: requestBudget
        )
        log("activity \(activityID) streams loaded, \(streamSummary(streams))")
        return streams
    }

    private func authorizedJSON<Response: Decodable>(
        _ endpoint: NetworkEndpoint,
        expectedAthleteID: Int64,
        requestBudget: RequestBudget
    ) async throws -> Response {
        var credentials = try await validCredentials(
            expectedAthleteID: expectedAthleteID,
            requestBudget: requestBudget
        )
        do {
            let response: Response = try await authorizedJSON(
                endpoint,
                accessToken: credentials.accessToken,
                requestBudget: requestBudget
            )
            try validateStoredAuthorization(expectedAthleteID: expectedAthleteID)
            return response
        } catch let error as NetworkError where error.statusCode == 401 {
            log("request unauthorized, refreshing token before retry: \(requestDescription(endpoint))")
            credentials = try await refreshCredentials(
                credentials,
                expectedAthleteID: expectedAthleteID,
                requestBudget: requestBudget
            )
            log("retrying request after token refresh: \(requestDescription(endpoint))")
            do {
                let response: Response = try await authorizedJSON(
                    endpoint,
                    accessToken: credentials.accessToken,
                    requestBudget: requestBudget
                )
                try validateStoredAuthorization(expectedAthleteID: expectedAthleteID)
                return response
            } catch let retryError as NetworkError
                where Self.isAPIAuthorizationFailure(retryError) {
                log("request remained unauthorized after token refresh; clearing stored credentials")
                guard clearCredentialsIfCurrent(
                    credentials,
                    markReauthorizationRequired: true
                ) else {
                    throw StravaManagerError.authorizationChangedDuringImport
                }
                throw StravaManagerError.reauthorizationRequired
            }
        } catch let error as NetworkError where Self.isAPIAuthorizationFailure(error) {
            log("request authorization is invalid; clearing stored credentials")
            guard clearCredentialsIfCurrent(
                credentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        }
    }

    private func authorizedJSON<Response: Decodable>(
        _ endpoint: NetworkEndpoint,
        accessToken: String,
        requestBudget: RequestBudget
    ) async throws -> Response {
        var endpoint = endpoint
        endpoint.headers["Authorization"] = "Bearer \(accessToken)"
        let description = requestDescription(endpoint)
        log("request started: \(description)")
        do {
            try requestBudget.beginRequest()
            let response: NetworkResponse<Response> = try await networkManager.response(endpoint, decoder: decoder)
            requestBudget.observe(headers: response.headers)
            log("request completed: \(description), status: \(response.statusCode), bytes: \(response.data.count)")
            return response.value
        } catch {
            if let networkError = error as? NetworkError {
                requestBudget.observe(headers: networkError.responseHeaders)
            }
            log("request failed: \(description), error: \(error.localizedDescription)")
            throw error
        }
    }

    private func validCredentials(
        expectedAthleteID: Int64,
        requestBudget: RequestBudget
    ) async throws -> StravaStoredCredentials {
        guard let credentials = storedCredentials() else {
            log("no stored Strava credentials")
            throw StravaManagerError.notAuthorized
        }
        guard credentials.athleteID == expectedAthleteID else {
            throw StravaManagerError.authorizationChangedDuringImport
        }
        guard let scope = credentials.scope,
              Self.scopeComponents(scope).contains("activity:read_all") else {
            guard clearCredentialsIfCurrent(
                credentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        }

        if credentials.isAccessTokenValid {
            log("using stored access token, expiresAt: \(Self.debugDateString(credentials.expiresAt))")
            return credentials
        }

        log("stored access token expired or missing expiry, refreshing")
        return try await refreshCredentials(
            credentials,
            expectedAthleteID: expectedAthleteID,
            requestBudget: requestBudget
        )
    }

    private func validateStoredAuthorization(expectedAthleteID: Int64) throws {
        guard let credentials = storedCredentials(),
              credentials.athleteID == expectedAthleteID else {
            log("authorization identity or scope changed during import; discarding this pass")
            throw StravaManagerError.authorizationChangedDuringImport
        }
        guard let scope = credentials.scope,
              Self.scopeComponents(scope).contains("activity:read_all") else {
            guard clearCredentialsIfCurrent(
                credentials,
                markReauthorizationRequired: true
            ) else {
                throw StravaManagerError.authorizationChangedDuringImport
            }
            throw StravaManagerError.reauthorizationRequired
        }
    }

    private func storedCredentials() -> StravaStoredCredentials? {
        if let data = defaults.data(forKey: DefaultsKey.credentials),
           let credentials = try? JSONDecoder().decode(StravaStoredCredentials.self, from: data) {
            guard credentials.athleteID != nil else {
                log("clearing legacy Strava credentials without athlete ID")
                clearCredentials(markReauthorizationRequired: false)
                return nil
            }
            return credentials
        }

        return nil
    }

    private func saveCredentials(_ credentials: StravaStoredCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else {
            log("failed to encode credentials for storage")
            return
        }

        defaults.set(data, forKey: DefaultsKey.credentials)
        if let athleteID = credentials.athleteID {
            syncStateStore.lastAuthorizedStravaAthleteID = String(athleteID)
        }
        defaults.set(true, forKey: DefaultsKey.authorizationAttempted)
        defaults.set(false, forKey: DefaultsKey.authorizationNeedsReauthorization)
    }

    @discardableResult
    private func clearCredentialsIfCurrent(
        _ expectedCredentials: StravaStoredCredentials,
        markReauthorizationRequired: Bool
    ) -> Bool {
        guard let currentCredentials = storedCredentials(),
              currentCredentials.athleteID == expectedCredentials.athleteID,
              currentCredentials.accessToken == expectedCredentials.accessToken,
              currentCredentials.refreshToken == expectedCredentials.refreshToken else {
            return false
        }

        if let athleteID = currentCredentials.athleteID {
            syncStateStore.lastAuthorizedStravaAthleteID = String(athleteID)
        }
        clearCredentials(markReauthorizationRequired: markReauthorizationRequired)
        return true
    }

    private func clearCredentials(markReauthorizationRequired: Bool) {
        defaults.removeObject(forKey: DefaultsKey.credentials)
        if markReauthorizationRequired {
            markAuthorizationNeedsReauthorization()
        }
    }

    private func markAuthorizationNeedsReauthorization() {
        defaults.set(true, forKey: DefaultsKey.authorizationAttempted)
        defaults.set(true, forKey: DefaultsKey.authorizationNeedsReauthorization)
    }

    static func requiresReauthorization(_ error: Error) -> Bool {
        guard let managerError = error as? StravaManagerError else {
            return false
        }

        switch managerError {
        case .notAuthorized, .reauthorizationRequired:
            return true
        case .authorizationDenied,
             .authorizationChangedDuringImport,
             .authorizationSessionFailedToStart,
             .cancelled,
             .invalidRedirectURI,
             .invalidURL,
             .missingAuthorizationCode,
             .requestBudgetExhausted:
            return false
        }
    }

    static func shouldRetryImport(after error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let managerError = error as? StravaManagerError {
            if case .requestBudgetExhausted = managerError {
                return true
            }
            return false
        }
        guard let networkError = error as? NetworkError else {
            return false
        }

        switch networkError {
        case .transportFailed(let underlying):
            return (underlying as? URLError)?.code != .cancelled
        case .invalidResponse, .decodingFailed:
            return true
        case .httpStatus(let statusCode, _, _, _):
            return statusCode == 408
                || statusCode == 425
                || statusCode == 429
                || statusCode >= 500
        case .invalidURL:
            return false
        }
    }

    private static func optionalParameters(_ parameters: [String: String]) -> [String: NetworkParameterValue?] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, Optional(NetworkParameterValue.string($0.value))) })
    }

    private func log(_ message: String) {
        print("PTrack Strava: \(message)")
    }

    private func requestDescription(_ endpoint: NetworkEndpoint) -> String {
        let parameters = endpoint.parameters.compactMapValues { $0 }
        let parameterDescription = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(redactedParameterValue($0.value, key: $0.key))" }
            .joined(separator: "&")

        let path = endpoint.url.path.isEmpty ? endpoint.url.absoluteString : endpoint.url.path
        guard !parameterDescription.isEmpty else {
            return "\(endpoint.method.rawValue) \(path)"
        }

        return "\(endpoint.method.rawValue) \(path)?\(parameterDescription)"
    }

    private func redactedParameterValue(_ value: NetworkParameterValue, key: String) -> String {
        let lowercasedKey = key.lowercased()
        if lowercasedKey.contains("token") || lowercasedKey.contains("secret") || lowercasedKey.contains("code") {
            return "<redacted>"
        }

        return value.description
    }

    private func streamSummary(_ streams: StravaActivityStreamSet) -> String {
        let keys = streams.streams.keys.sorted().joined(separator: ",")
        let latLngCount = streams.streams["latlng"]?.data.latLngValues.count ?? 0
        let timeCount = streams.streams["time"]?.data.intValues.count ?? 0
        let distanceCount = streams.streams["distance"]?.data.doubleValues.count ?? 0
        return "keys: [\(keys)], latlng: \(latLngCount), time: \(timeCount), distance: \(distanceCount)"
    }

    private static func debugDateString(_ date: Date?) -> String {
        guard let date else {
            return "nil"
        }

        return ISO8601DateFormatter().string(from: date)
    }

    private static func isAuthorizationFailure(_ error: NetworkError) -> Bool {
        guard let statusCode = error.statusCode else {
            return false
        }

        return statusCode == 400 || statusCode == 401 || statusCode == 403
    }

    private static func isRateLimitFailure(_ error: Error) -> Bool {
        (error as? NetworkError)?.statusCode == 429
    }

    private static func isRequestBudgetFailure(_ error: Error) -> Bool {
        guard let managerError = error as? StravaManagerError else {
            return false
        }
        if case .requestBudgetExhausted = managerError {
            return true
        }
        return false
    }

    private static func scopeComponents(_ scope: String) -> Set<String> {
        Set(
            scope
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map(String.init)
        )
    }

    private static func isAPIAuthorizationFailure(_ error: NetworkError) -> Bool {
        error.statusCode == 401 || error.statusCode == 403
    }

    private static func shouldStopImportPass(after error: Error) -> Bool {
        if let managerError = error as? StravaManagerError {
            switch managerError {
            case .authorizationChangedDuringImport, .requestBudgetExhausted:
                return true
            default:
                break
            }
        }

        guard let networkError = error as? NetworkError else {
            return false
        }

        switch networkError {
        case .httpStatus(let statusCode, _, _, _):
            return statusCode == 400
                || statusCode == 401
                || statusCode == 403
                || statusCode == 429
                || statusCode >= 500
        case .transportFailed, .invalidResponse, .invalidURL, .decodingFailed:
            return true
        }
    }
}

struct StravaStoredCredentials: Codable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let scope: String?
    let athleteID: Int64?

    var isAccessTokenValid: Bool {
        guard let expiresAt else {
            return false
        }

        return expiresAt.timeIntervalSinceNow > 60
    }
}

enum StravaManagerError: LocalizedError {
    case authorizationDenied(String)
    case authorizationChangedDuringImport
    case authorizationSessionFailedToStart
    case cancelled
    case invalidRedirectURI(redirectURI: String, callbackDomain: String)
    case invalidURL
    case missingAuthorizationCode
    case notAuthorized
    case reauthorizationRequired
    case requestBudgetExhausted(retryAfter: Date?)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied(let message):
            return message
        case .authorizationChangedDuringImport:
            return "Strava authorization changed during synchronization. Please retry."
        case .authorizationSessionFailedToStart:
            return "Strava authorization could not be started."
        case .cancelled:
            return "Strava authorization was cancelled."
        case .invalidRedirectURI(let redirectURI, let callbackDomain):
            return "Strava redirect_uri must use the app URL scheme and the configured callback domain. Current redirect_uri: \(redirectURI), callback domain: \(callbackDomain)."
        case .invalidURL:
            return "Invalid Strava URL."
        case .missingAuthorizationCode:
            return "Strava did not return an authorization code."
        case .notAuthorized:
            return "Strava authorization is required."
        case .reauthorizationRequired:
            return "Strava authorization has expired. Please sign in again."
        case .requestBudgetExhausted(let retryAfter):
            guard let retryAfter else {
                return "The Strava request budget for this synchronization pass is exhausted."
            }
            return "The Strava request budget is exhausted. Retry after \(ISO8601DateFormatter().string(from: retryAfter))."
        }
    }
}

private struct StravaOAuthTokenResponse: Decodable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int?
    let athlete: StravaAthlete?
}

private struct StravaAthlete: Decodable {
    let id: Int64
}

private struct StravaActivityListing {
    let activities: [StravaSummaryActivity]
    let didReachEnd: Bool
    let upperBound: Date
}

private struct StravaSummaryActivity: Decodable {
    let id: Int64
    let name: String?
    let distance: Double?
    let movingTime: TimeInterval?
    let elapsedTime: TimeInterval?
    let totalElevationGain: Double?
    let type: String?
    let sportType: String?
    let startDate: Date?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let calories: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let averageWatts: Double?
    let maxWatts: Double?
    let weightedAverageWatts: Double?
    let kilojoules: Double?
    let map: StravaPolylineMap?
    let startLatlng: StravaLatLng?
    let endLatlng: StravaLatLng?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case distance
        case movingTime
        case elapsedTime
        case totalElevationGain
        case type
        case sportType
        case startDate
        case averageSpeed
        case maxSpeed
        case calories
        case averageHeartrate
        case maxHeartrate
        case averageWatts
        case maxWatts
        case weightedAverageWatts
        case kilojoules
        case map
        case startLatlng
        case endLatlng
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        movingTime = try container.decodeIfPresent(TimeInterval.self, forKey: .movingTime)
        elapsedTime = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsedTime)
        totalElevationGain = try container.decodeIfPresent(Double.self, forKey: .totalElevationGain)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        sportType = try container.decodeIfPresent(String.self, forKey: .sportType)
        startDate = Self.date(from: try container.decodeIfPresent(String.self, forKey: .startDate))
        averageSpeed = try container.decodeIfPresent(Double.self, forKey: .averageSpeed)
        maxSpeed = try container.decodeIfPresent(Double.self, forKey: .maxSpeed)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories)
        averageHeartrate = try container.decodeIfPresent(Double.self, forKey: .averageHeartrate)
        maxHeartrate = try container.decodeIfPresent(Double.self, forKey: .maxHeartrate)
        averageWatts = try container.decodeIfPresent(Double.self, forKey: .averageWatts)
        maxWatts = try container.decodeIfPresent(Double.self, forKey: .maxWatts)
        weightedAverageWatts = try container.decodeIfPresent(Double.self, forKey: .weightedAverageWatts)
        kilojoules = try container.decodeIfPresent(Double.self, forKey: .kilojoules)
        map = try container.decodeIfPresent(StravaPolylineMap.self, forKey: .map)
        startLatlng = Self.latLng(from: container, forKey: .startLatlng)
        endLatlng = Self.latLng(from: container, forKey: .endLatlng)
    }

    var supportedSport: StravaSupportedSport? {
        StravaSupportedSport(stravaSportType: sportType ?? type)
    }

    var hasRouteHint: Bool {
        if map?.hasPolyline == true {
            return true
        }

        return startLatlng != nil && endLatlng != nil
    }

    private static func date(from string: String?) -> Date? {
        guard let string else {
            return nil
        }

        return ISO8601DateFormatter.stravaFormatter.date(from: string)
            ?? ISO8601DateFormatter.stravaFormatterWithoutFractionalSeconds.date(from: string)
    }

    private static func latLng(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> StravaLatLng? {
        guard let values = try? container.decodeIfPresent([Double].self, forKey: key),
              values.count >= 2 else {
            return nil
        }

        return StravaLatLng(latitude: values[0], longitude: values[1])
    }
}

private struct StravaPolylineMap: Decodable {
    let id: String?
    let polyline: String?
    let summaryPolyline: String?

    var hasPolyline: Bool {
        [polyline, summaryPolyline].contains { value in
            guard let value else {
                return false
            }

            return !value.isEmpty
        }
    }
}

private extension StravaSummaryActivity {
    func placeholderRouteCoordinates(startDate: Date) -> [RouteCoordinate] {
        var points: [StravaLatLng] = []
        if let encodedPolyline = [map?.polyline, map?.summaryPolyline]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty }) {
            points = Self.decodePolyline(encodedPolyline)
        }

        if points.count < 2 {
            points = [startLatlng, endLatlng].compactMap { $0 }
        }

        points = points.filter {
            $0.latitude.isFinite
                && $0.longitude.isFinite
                && (-90...90).contains($0.latitude)
                && (-180...180).contains($0.longitude)
        }
        guard points.count > 1 else {
            return []
        }

        let duration = max(elapsedTime ?? movingTime ?? TimeInterval(points.count - 1), 1)
        let totalDistanceMeters = self.distance.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let denominator = Double(max(points.count - 1, 1))
        return points.enumerated().map { index, point in
            let progress = Double(index) / denominator
            return RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                timestamp: startDate.addingTimeInterval(duration * progress),
                sourceDistanceMeters: totalDistanceMeters.map { $0 * progress },
                horizontalAccuracyMeters: nil,
                altitudeMeters: nil,
                verticalAccuracyMeters: nil,
                gradeRatio: nil,
                speedMetersPerSecond: nil,
                speedAccuracyMetersPerSecond: nil,
                courseDegrees: nil,
                courseAccuracyDegrees: nil,
                floorLevel: nil,
                heartRateBeatsPerMinute: nil,
                powerWatts: nil,
                temperatureCelsius: nil
            )
        }
    }

    static func decodePolyline(_ encodedPolyline: String) -> [StravaLatLng] {
        let bytes = Array(encodedPolyline.utf8)
        guard !bytes.isEmpty else {
            return []
        }

        var index = 0
        var latitude: Int64 = 0
        var longitude: Int64 = 0
        var points: [StravaLatLng] = []
        points.reserveCapacity(min(bytes.count / 2, 4_096))

        func nextDelta() -> Int64? {
            var result: Int64 = 0
            var shift: Int64 = 0
            while index < bytes.count, shift <= 55 {
                let value = Int64(bytes[index]) - 63
                index += 1
                guard value >= 0 else {
                    return nil
                }

                result |= (value & 0x1f) << shift
                if value < 0x20 {
                    return (result & 1) == 0 ? result >> 1 : ~(result >> 1)
                }
                shift += 5
            }
            return nil
        }

        while index < bytes.count, points.count < 100_000 {
            guard let latitudeDelta = nextDelta(),
                  let longitudeDelta = nextDelta() else {
                return []
            }
            latitude += latitudeDelta
            longitude += longitudeDelta
            points.append(
                StravaLatLng(
                    latitude: Double(latitude) / 100_000,
                    longitude: Double(longitude) / 100_000
                )
            )
        }

        return points
    }
}

private enum StravaSupportedSport {
    case run
    case walk
    case trailRun
    case ride
    case hike
    case swim
    case paddle
    case rowing
    case sailing
    case surf
    case snow
    case skate
    case handCycle

    init?(stravaSportType: String?) {
        switch stravaSportType {
        case "Run", "VirtualRun":
            self = .run
        case "Walk":
            self = .walk
        case "TrailRun":
            self = .trailRun
        case "Ride", "GravelRide", "MountainBikeRide", "VirtualRide", "EBikeRide", "EMountainBikeRide", "Velomobile":
            self = .ride
        case "Hike":
            self = .hike
        case "Swim":
            self = .swim
        case "Canoeing", "Kayaking", "StandUpPaddling":
            self = .paddle
        case "Rowing", "VirtualRow":
            self = .rowing
        case "Sail":
            self = .sailing
        case "Surfing", "Kitesurf", "Windsurf":
            self = .surf
        case "AlpineSki", "BackcountrySki", "NordicSki", "Snowboard", "Snowshoe":
            self = .snow
        case "IceSkate", "InlineSkate", "RollerSki", "Skateboard":
            self = .skate
        case "Handcycle":
            self = .handCycle
        default:
            return nil
        }
    }

    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .run, .trailRun:
            return .running
        case .walk:
            return .walking
        case .ride:
            return .cycling
        case .hike:
            return .hiking
        case .swim:
            return .swimming
        case .paddle:
            return .paddleSports
        case .rowing:
            return .rowing
        case .sailing:
            return .sailing
        case .surf:
            return .surfingSports
        case .snow:
            return .snowSports
        case .skate:
            return .skatingSports
        case .handCycle:
            return .handCycling
        }
    }
}

private struct StravaActivityStreamSet: Decodable {
    let streams: [String: StravaRawStream]

    init(from decoder: Decoder) throws {
        if let keyedStreams = try? [String: StravaRawStream](from: decoder) {
            streams = keyedStreams.reduce(into: [String: StravaRawStream]()) { partialResult, item in
                var stream = item.value
                stream.type = stream.type ?? item.key
                partialResult[item.key] = stream
            }
            return
        }

        let streamArray = try [StravaRawStream](from: decoder)
        streams = streamArray.reduce(into: [String: StravaRawStream]()) { partialResult, stream in
            guard let type = stream.type else {
                return
            }
            partialResult[type] = stream
        }
    }

    func routeCoordinates(startDate: Date) -> [RouteCoordinate] {
        guard let latLngPairs = streams["latlng"]?.data.latLngValues, !latLngPairs.isEmpty else {
            return []
        }

        let times = streams["time"]?.data.intValues
        let distances = streams["distance"]?.data.doubleValues
        let altitudes = streams["altitude"]?.data.doubleValues
        let gradePercents = streams["grade_smooth"]?.data.doubleValues
        let speeds = streams["velocity_smooth"]?.data.doubleValues
        let heartRates = streams["heartrate"]?.data.doubleValues
        let powers = streams["watts"]?.data.doubleValues
        let temperatures = streams["temp"]?.data.doubleValues

        let alignedSourceDistances: [Double]? = {
            guard let distances,
                  distances.count == latLngPairs.count,
                  let firstDistance = distances.first,
                  firstDistance.isFinite,
                  firstDistance >= 0 else {
                return nil
            }
            var normalizedDistances: [Double] = [firstDistance]
            normalizedDistances.reserveCapacity(distances.count)
            var previousDistance = firstDistance
            var hasForwardProgress = false
            for distance in distances.dropFirst() {
                guard distance.isFinite,
                      distance >= 0,
                      distance >= previousDistance - 0.01 else {
                    return nil
                }
                let normalizedDistance = max(distance, previousDistance)
                if normalizedDistance > previousDistance + 0.001 {
                    hasForwardProgress = true
                }
                normalizedDistances.append(normalizedDistance)
                previousDistance = normalizedDistance
            }
            guard hasForwardProgress,
                  previousDistance - firstDistance >= 20 else {
                return nil
            }
            return normalizedDistances
        }()
        let alignedGradePercents: [Double]? = {
            guard alignedSourceDistances != nil,
                  let gradePercents,
                  gradePercents.count == latLngPairs.count else {
                return nil
            }
            return gradePercents
        }()

        return latLngPairs.enumerated().map { index, pair in
            let gradeRatio = (alignedGradePercents?[index]).flatMap { gradePercent -> Double? in
                let ratio = gradePercent / 100
                return ratio.isFinite && (-1...1).contains(ratio) ? ratio : nil
            }

            return RouteCoordinate(
                latitude: pair.latitude,
                longitude: pair.longitude,
                timestamp: startDate.addingTimeInterval(TimeInterval(times?[safe: index] ?? index)),
                sourceDistanceMeters: alignedSourceDistances?[index],
                horizontalAccuracyMeters: nil,
                altitudeMeters: altitudes?[safe: index],
                verticalAccuracyMeters: nil,
                gradeRatio: gradeRatio,
                speedMetersPerSecond: speeds?[safe: index],
                speedAccuracyMetersPerSecond: nil,
                courseDegrees: nil,
                courseAccuracyDegrees: nil,
                floorLevel: nil,
                heartRateBeatsPerMinute: heartRates?[safe: index],
                powerWatts: powers?[safe: index],
                temperatureCelsius: temperatures?[safe: index]
            )
        }
    }

    func doubleValues(for type: String) -> [Double] {
        streams[type]?.data.doubleValues ?? []
    }

    func intValues(for type: String) -> [Int] {
        streams[type]?.data.intValues ?? []
    }
}

private struct StravaRawStream: Decodable {
    var type: String?
    let data: StravaStreamData
}

private enum StravaStreamData: Decodable {
    case doubleValues([Double])
    case intValues([Int])
    case latLngValues([StravaLatLng])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let latLngValues = try? container.decode([StravaLatLng].self) {
            self = .latLngValues(latLngValues)
            return
        }

        if let intValues = try? container.decode([Int].self) {
            self = .intValues(intValues)
            return
        }

        if let doubleValues = try? container.decode([Double].self) {
            self = .doubleValues(doubleValues)
            return
        }

        self = .doubleValues([])
    }

    var doubleValues: [Double] {
        switch self {
        case .doubleValues(let values):
            return values
        case .intValues(let values):
            return values.map(Double.init)
        case .latLngValues:
            return []
        }
    }

    var intValues: [Int] {
        switch self {
        case .doubleValues(let values):
            return values.map(Int.init)
        case .intValues(let values):
            return values
        case .latLngValues:
            return []
        }
    }

    var latLngValues: [StravaLatLng] {
        switch self {
        case .latLngValues(let values):
            return values
        case .doubleValues, .intValues:
            return []
        }
    }
}

private struct StravaLatLng: Decodable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        latitude = try container.decode(Double.self)
        longitude = try container.decode(Double.self)
    }
}

private extension TrackedWorkout {
    init?(
        stravaSummaryActivity activity: StravaSummaryActivity,
        isTerminal: Bool,
        athleteID: Int64
    ) {
        guard let sport = activity.supportedSport,
              let startDate = activity.startDate else {
            return nil
        }

        let rawCoordinates = activity.placeholderRouteCoordinates(startDate: startDate)
        guard rawCoordinates.count > 1 else {
            return nil
        }

        let sampledCoordinates = RouteSampler.downsample(rawCoordinates, limit: 1_200)
        let quantityMetrics = Self.stravaQuantityMetrics(activity: activity, sport: sport)
        var placeholderMetadata = Self.stravaMetadata(
            activity: activity,
            sport: sport,
            athleteID: athleteID
        )
        placeholderMetadata[Self.stravaStreamDataVersionMetadataKey] = TrackedMetadataValue(
            type: "number",
            doubleValue: 0
        )
        placeholderMetadata[Self.stravaSummaryPlaceholderMetadataKey] = TrackedMetadataValue(
            type: "bool",
            boolValue: true
        )
        if isTerminal {
            placeholderMetadata[Self.stravaTerminalPlaceholderMetadataKey] = TrackedMetadataValue(
                type: "bool",
                boolValue: true
            )
        }

        id = "strava-\(activity.id)"
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = sport.healthKitActivityType.rawValue
        self.startDate = startDate
        endDate = startDate.addingTimeInterval(activity.elapsedTime ?? activity.movingTime ?? 0)
        durationSeconds = activity.movingTime ?? activity.elapsedTime
        distanceMeters = activity.distance ?? 0
        totalEnergyBurnedKilocalories = activity.calories
        sourceRevision = TrackedWorkoutSourceRevision(stravaActivityID: activity.id)
        device = nil
        metadata = placeholderMetadata
        workoutEvents = nil
        routeSegments = nil
        routeSummary = TrackedRouteSummary(
            stravaSummaryCoordinates: rawCoordinates,
            sampledCoordinateCount: sampledCoordinates.count,
            activity: activity
        )
        self.quantityMetrics = quantityMetrics.isEmpty ? nil : quantityMetrics
        coordinates = sampledCoordinates
        fullCoordinates = Self.fullCoordinatesIfSampled(
            rawCoordinates: rawCoordinates,
            sampledCoordinates: sampledCoordinates
        )
    }

    init?(
        stravaActivity activity: StravaSummaryActivity,
        streams: StravaActivityStreamSet,
        athleteID: Int64
    ) {
        guard let sport = activity.supportedSport,
              let startDate = activity.startDate else {
            return nil
        }

        let rawCoordinates = streams.routeCoordinates(startDate: startDate)
        guard rawCoordinates.count > 1 else {
            return nil
        }

        let sampledCoordinates = RouteSampler.downsample(rawCoordinates, limit: 1_200)
        let quantityMetrics = Self.stravaQuantityMetrics(activity: activity, sport: sport)

        id = "strava-\(activity.id)"
        healthDataVersion = Self.currentHealthDataVersion
        activityTypeRawValue = sport.healthKitActivityType.rawValue
        self.startDate = startDate
        endDate = startDate.addingTimeInterval(activity.elapsedTime ?? activity.movingTime ?? 0)
        durationSeconds = activity.movingTime ?? activity.elapsedTime
        distanceMeters = activity.distance ?? streams.doubleValues(for: "distance").last ?? 0
        totalEnergyBurnedKilocalories = activity.calories
        sourceRevision = TrackedWorkoutSourceRevision(stravaActivityID: activity.id)
        device = nil
        metadata = Self.stravaMetadata(
            activity: activity,
            sport: sport,
            athleteID: athleteID
        )
        workoutEvents = nil
        routeSegments = nil
        routeSummary = TrackedRouteSummary(
            stravaCoordinates: rawCoordinates,
            sampledCoordinateCount: sampledCoordinates.count,
            activity: activity,
            streams: streams
        )
        self.quantityMetrics = quantityMetrics.isEmpty ? nil : quantityMetrics
        coordinates = sampledCoordinates
        fullCoordinates = Self.fullCoordinatesIfSampled(
            rawCoordinates: rawCoordinates,
            sampledCoordinates: sampledCoordinates
        )
    }

    private static func stravaMetadata(
        activity: StravaSummaryActivity,
        sport: StravaSupportedSport,
        athleteID: Int64
    ) -> [String: TrackedMetadataValue] {
        var metadata: [String: TrackedMetadataValue] = [
            "strava.id": TrackedMetadataValue(type: "string", stringValue: "\(activity.id)"),
            TrackedWorkout.stravaAthleteIDMetadataKey: TrackedMetadataValue(
                type: "string",
                stringValue: "\(athleteID)"
            ),
            TrackedWorkout.stravaStreamDataVersionMetadataKey: TrackedMetadataValue(
                type: "number",
                doubleValue: Double(TrackedWorkout.currentStravaStreamDataVersion)
            )
        ]

        if let name = activity.name {
            metadata["strava.name"] = TrackedMetadataValue(type: "string", stringValue: name)
        }
        if let sportType = activity.sportType ?? activity.type {
            metadata["strava.sportType"] = TrackedMetadataValue(type: "string", stringValue: sportType)
        }
        if let totalElevationGain = activity.totalElevationGain {
            metadata["strava.totalElevationGain"] = TrackedMetadataValue(type: "number", doubleValue: totalElevationGain)
        }
        if let kilojoules = activity.kilojoules {
            metadata["strava.kilojoules"] = TrackedMetadataValue(type: "number", doubleValue: kilojoules)
        }

        metadata["strava.healthKitActivityTypeRawValue"] = TrackedMetadataValue(
            type: "number",
            doubleValue: Double(sport.healthKitActivityType.rawValue)
        )

        return metadata
    }

    private static func stravaQuantityMetrics(
        activity: StravaSummaryActivity,
        sport: StravaSupportedSport
    ) -> [TrackedWorkoutQuantityMetric] {
        var metrics: [TrackedWorkoutQuantityMetric] = []

        if let calories = activity.calories {
            metrics.append(TrackedWorkoutQuantityMetric(
                identifier: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                unit: "kcal",
                sum: calories,
                average: nil,
                minimum: nil,
                maximum: nil
            ))
        }

        if activity.averageHeartrate != nil || activity.maxHeartrate != nil {
            metrics.append(TrackedWorkoutQuantityMetric(
                identifier: HKQuantityTypeIdentifier.heartRate.rawValue,
                unit: "count/min",
                sum: nil,
                average: activity.averageHeartrate,
                minimum: nil,
                maximum: activity.maxHeartrate
            ))
        }

        if activity.averageSpeed != nil || activity.maxSpeed != nil {
            metrics.append(TrackedWorkoutQuantityMetric(
                identifier: speedIdentifier(for: sport),
                unit: "m/s",
                sum: nil,
                average: activity.averageSpeed,
                minimum: nil,
                maximum: activity.maxSpeed
            ))
        }

        if activity.averageWatts != nil || activity.maxWatts != nil || activity.weightedAverageWatts != nil {
            metrics.append(TrackedWorkoutQuantityMetric(
                identifier: HKQuantityTypeIdentifier.cyclingPower.rawValue,
                unit: "W",
                sum: nil,
                average: activity.weightedAverageWatts ?? activity.averageWatts,
                minimum: nil,
                maximum: activity.maxWatts
            ))
        }

        return metrics
    }

    private static func speedIdentifier(for sport: StravaSupportedSport) -> String {
        switch sport {
        case .ride:
            return HKQuantityTypeIdentifier.cyclingSpeed.rawValue
        case .run, .trailRun:
            return HKQuantityTypeIdentifier.runningSpeed.rawValue
        case .walk, .hike, .swim, .paddle, .rowing, .sailing, .surf, .snow, .skate, .handCycle:
            return "strava.speed"
        }
    }
}

private extension TrackedWorkoutSourceRevision {
    init(stravaActivityID: Int64) {
        sourceName = "Strava"
        bundleIdentifier = "com.strava.activity.\(stravaActivityID)"
        version = nil
        productType = "Strava API"
        operatingSystemVersion = "api-v3"
    }
}

private extension TrackedRouteSummary {
    init(
        stravaSummaryCoordinates coordinates: [RouteCoordinate],
        sampledCoordinateCount: Int,
        activity: StravaSummaryActivity
    ) {
        rawLocationCount = coordinates.count
        self.sampledCoordinateCount = sampledCoordinateCount
        measuredDistanceMeters = activity.distance
        minimumAltitudeMeters = nil
        maximumAltitudeMeters = nil
        elevationGainMeters = activity.totalElevationGain
        elevationLossMeters = nil
        averageSpeedMetersPerSecond = activity.averageSpeed
        maximumSpeedMetersPerSecond = activity.maxSpeed
    }

    init(
        stravaCoordinates coordinates: [RouteCoordinate],
        sampledCoordinateCount: Int,
        activity: StravaSummaryActivity,
        streams: StravaActivityStreamSet
    ) {
        rawLocationCount = coordinates.count
        self.sampledCoordinateCount = sampledCoordinateCount
        measuredDistanceMeters = streams.doubleValues(for: "distance").last ?? activity.distance

        let altitudes = coordinates.compactMap(\.altitudeMeters)
        minimumAltitudeMeters = altitudes.min()
        maximumAltitudeMeters = altitudes.max()

        let elevationChange = Self.stravaElevationChange(for: altitudes)
        elevationGainMeters = activity.totalElevationGain ?? elevationChange.gain
        elevationLossMeters = elevationChange.loss
        averageSpeedMetersPerSecond = activity.averageSpeed
        maximumSpeedMetersPerSecond = activity.maxSpeed
    }

    private static func stravaElevationChange(for altitudes: [Double]) -> (gain: Double?, loss: Double?) {
        guard altitudes.count > 1 else {
            return (nil, nil)
        }

        var gain: Double = 0
        var loss: Double = 0
        var previousAltitude = altitudes[0]

        for altitude in altitudes.dropFirst() {
            let delta = altitude - previousAltitude
            if delta > 0 {
                gain += delta
            } else {
                loss += abs(delta)
            }
            previousAltitude = altitude
        }

        return (gain, loss)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}

private extension ISO8601DateFormatter {
    static let stravaFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let stravaFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
