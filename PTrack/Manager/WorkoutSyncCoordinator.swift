//
//  WorkoutSyncCoordinator.swift
//  PTrack
//

import Foundation

/// Owns the transient synchronization state that used to be spread across the
/// home view controller. Keeping generations, pending requests, and rollback
/// state together makes source hand-offs explicit and prevents a stale callback
/// from mutating a newer synchronization pass.
@MainActor
final class WorkoutSyncCoordinator {
    enum Source {
        case health
        case strava
    }

    enum StravaCompletion {
        /// The activity listing reached its natural end. Destructive
        /// reconciliation may still be unavailable for an incremental scope;
        /// deferred detail enrichment is coordinated independently.
        case summarySuccess(detailRetryAfter: Date?)
        case partialSuccess(retryAfter: Date?)
        case failure(
            retryAfter: Date?,
            retriesQueuedStravaImmediately: Bool,
            schedulesPendingRetry: Bool
        )
    }

    struct StravaRequest {
        let showsLoadingIndicator: Bool
        let presentsErrors: Bool

        func merging(showsLoadingIndicator: Bool, presentsErrors: Bool) -> Self {
            Self(
                showsLoadingIndicator: self.showsLoadingIndicator || showsLoadingIndicator,
                presentsErrors: self.presentsErrors || presentsErrors
            )
        }
    }

    struct DataSourceRequest {
        let showsLoadingIndicator: Bool

        func merging(showsLoadingIndicator: Bool) -> Self {
            Self(showsLoadingIndicator: self.showsLoadingIndicator || showsLoadingIndicator)
        }
    }

    struct StravaRollbackSnapshot {
        let generation: UInt64
        let athleteID: String
        let workouts: [TrackedWorkout]
        let pendingWorkouts: [TrackedWorkout]
    }

    private struct SourceState {
        var isInProgress = false
        var hasNewData = false
        var showsLoadingIndicator = false
        var generation: UInt64 = 0
    }

    private var health = SourceState()
    private var strava = SourceState()
    private(set) var pendingStravaRequest: StravaRequest?
    private(set) var pendingDataSourceRequest: DataSourceRequest?
    private(set) var needsHealthRepairAfterStrava = false
    private(set) var pendingStravaCacheAthleteID: String?
    private var stravaRollbackSnapshot: StravaRollbackSnapshot?

    var isNewDataSyncInProgress: Bool {
        health.hasNewData || strava.hasNewData
    }

    func isInProgress(_ source: Source) -> Bool {
        state(for: source).isInProgress
    }

    func isShowingLoadingIndicator(_ source: Source) -> Bool {
        state(for: source).showsLoadingIndicator
    }

    func begin(_ source: Source, showsLoadingIndicator: Bool) {
        update(source) { state in
            state.isInProgress = true
            state.hasNewData = false
            state.showsLoadingIndicator = showsLoadingIndicator
        }
    }

    func beginGeneration(_ source: Source) -> UInt64 {
        update(source) { $0.generation &+= 1 }
        return generation(for: source)
    }

    func beginStravaTransaction(
        athleteID: String,
        showsLoadingIndicator: Bool,
        workouts: [TrackedWorkout],
        pendingWorkouts: [TrackedWorkout]
    ) -> UInt64 {
        begin(.strava, showsLoadingIndicator: showsLoadingIndicator)
        let generation = beginGeneration(.strava)
        stravaRollbackSnapshot = StravaRollbackSnapshot(
            generation: generation,
            athleteID: athleteID,
            workouts: workouts,
            pendingWorkouts: pendingWorkouts
        )
        return generation
    }

    @discardableResult
    func finish(_ source: Source, generation: UInt64? = nil) -> Bool {
        if let generation, generation != self.generation(for: source) {
            return false
        }

        update(source) { state in
            state.isInProgress = false
            state.hasNewData = false
        }
        if source == .strava {
            stravaRollbackSnapshot = nil
        }
        return true
    }

    func markNewData(_ source: Source, generation: UInt64) {
        guard isCurrent(source, generation: generation) else {
            return
        }
        update(source) { $0.hasNewData = true }
    }

    func setNewData(_ hasNewData: Bool, for source: Source) {
        update(source) { $0.hasNewData = hasNewData }
    }

    /// Promotes a background synchronization to a visible one exactly once.
    func showLoadingIndicatorIfNeeded(_ source: Source) -> Bool {
        guard isInProgress(source), !isShowingLoadingIndicator(source) else {
            return false
        }
        update(source) { $0.showsLoadingIndicator = true }
        return true
    }

    /// Returns whether the caller must end a matching loading operation.
    func consumeLoadingIndicator(_ source: Source) -> Bool {
        guard isShowingLoadingIndicator(source) else {
            return false
        }
        update(source) { $0.showsLoadingIndicator = false }
        return true
    }

    func generation(for source: Source) -> UInt64 {
        state(for: source).generation
    }

    func isCurrent(_ source: Source, generation: UInt64) -> Bool {
        self.generation(for: source) == generation
    }

    func queueDataSource(showsLoadingIndicator: Bool) {
        pendingDataSourceRequest = pendingDataSourceRequest?.merging(
            showsLoadingIndicator: showsLoadingIndicator
        ) ?? DataSourceRequest(showsLoadingIndicator: showsLoadingIndicator)
    }

    func takePendingDataSourceRequest() -> DataSourceRequest? {
        defer { pendingDataSourceRequest = nil }
        return pendingDataSourceRequest
    }

    func queueStrava(showsLoadingIndicator: Bool, presentsErrors: Bool) {
        pendingStravaRequest = pendingStravaRequest?.merging(
            showsLoadingIndicator: showsLoadingIndicator,
            presentsErrors: presentsErrors
        ) ?? StravaRequest(
            showsLoadingIndicator: showsLoadingIndicator,
            presentsErrors: presentsErrors
        )
    }

    func takePendingStravaRequest() -> StravaRequest? {
        defer { pendingStravaRequest = nil }
        return pendingStravaRequest
    }

    func clearPendingStravaRequest() {
        pendingStravaRequest = nil
    }

    func requireHealthRepairAfterStrava() {
        needsHealthRepairAfterStrava = true
    }

    func consumeHealthRepairAfterStrava() {
        needsHealthRepairAfterStrava = false
    }

    func stageStravaCacheOwner(_ athleteID: String) {
        pendingStravaCacheAthleteID = athleteID
    }

    func clearPendingStravaCacheOwner(ifMatching athleteID: String) {
        guard pendingStravaCacheAthleteID == athleteID else {
            return
        }
        pendingStravaCacheAthleteID = nil
    }

    func rollbackSnapshot(generation: UInt64, athleteID: String) -> StravaRollbackSnapshot? {
        guard let snapshot = stravaRollbackSnapshot,
              snapshot.generation == generation,
              snapshot.athleteID == athleteID else {
            return nil
        }
        stravaRollbackSnapshot = nil
        return snapshot
    }

    private func state(for source: Source) -> SourceState {
        switch source {
        case .health:
            return health
        case .strava:
            return strava
        }
    }

    private func update(_ source: Source, mutation: (inout SourceState) -> Void) {
        switch source {
        case .health:
            mutation(&health)
        case .strava:
            mutation(&strava)
        }
    }
}

/// Typed persistence for synchronization ownership and reconciliation history.
/// These values intentionally keep their existing keys for migration safety.
final class WorkoutSyncStateStore {
    struct StravaAuthorizationHandoff: Codable {
        let cacheOwnerAthleteID: String
        let authorizedAthleteIDs: Set<String>
        let capturedAt: Date
    }

    struct StravaReconciliationRecord: Codable {
        let athleteID: String
        let activityIDs: Set<Int64>
        /// Local IDs absent from this authoritative listing. Optional so
        /// records written by older app versions decode conservatively: the
        /// first pass after upgrade establishes candidates but deletes none.
        let missingCandidateIDs: Set<Int64>?
        let capturedAt: Date
    }

    private enum Key {
        static let stravaCachedAthleteID = "studio.pj.PTrack.strava.cachedAthleteID"
        static let stravaLastSynchronizedAthleteID = "studio.pj.PTrack.strava.lastSynchronizedAthleteID"
        static let stravaReconciliationRecord = "studio.pj.PTrack.strava.reconciliationRecord"
        static let stravaDeferredRetryDate = "studio.pj.PTrack.strava.deferredRetryDate"
        static let stravaDeferredRetryProgressKey = "studio.pj.PTrack.strava.deferredRetryProgressKey"
        static let stravaDeferredRetryAttempt = "studio.pj.PTrack.strava.deferredRetryAttempt"
        static let stravaAuthorizationHandoff = "studio.pj.PTrack.strava.authorizationHandoff"
        static let lastAuthorizedStravaAthleteID = "studio.pj.PTrack.strava.lastAuthorizedAthleteID"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var cachedStravaAthleteID: String? {
        get { defaults.string(forKey: Key.stravaCachedAthleteID) }
        set { defaults.set(newValue, forKey: Key.stravaCachedAthleteID) }
    }

    var lastSynchronizedStravaAthleteID: String? {
        get { defaults.string(forKey: Key.stravaLastSynchronizedAthleteID) }
        set { defaults.set(newValue, forKey: Key.stravaLastSynchronizedAthleteID) }
    }

    var stravaReconciliationRecord: StravaReconciliationRecord? {
        get {
            guard let data = defaults.data(forKey: Key.stravaReconciliationRecord) else {
                return nil
            }
            return try? decoder.decode(StravaReconciliationRecord.self, from: data)
        }
        set {
            guard let newValue, let data = try? encoder.encode(newValue) else {
                defaults.removeObject(forKey: Key.stravaReconciliationRecord)
                return
            }
            defaults.set(data, forKey: Key.stravaReconciliationRecord)
        }
    }

    var stravaDeferredRetryDate: Date? {
        get { defaults.object(forKey: Key.stravaDeferredRetryDate) as? Date }
        set { defaults.set(newValue, forKey: Key.stravaDeferredRetryDate) }
    }

    var stravaDeferredRetryProgressKey: String? {
        get { defaults.string(forKey: Key.stravaDeferredRetryProgressKey) }
        set { defaults.set(newValue, forKey: Key.stravaDeferredRetryProgressKey) }
    }

    var stravaDeferredRetryAttempt: Int {
        get { defaults.integer(forKey: Key.stravaDeferredRetryAttempt) }
        set { defaults.set(max(newValue, 0), forKey: Key.stravaDeferredRetryAttempt) }
    }

    var stravaAuthorizationHandoff: StravaAuthorizationHandoff? {
        get {
            guard let data = defaults.data(forKey: Key.stravaAuthorizationHandoff) else {
                return nil
            }
            return try? decoder.decode(StravaAuthorizationHandoff.self, from: data)
        }
        set {
            guard let newValue, let data = try? encoder.encode(newValue) else {
                defaults.removeObject(forKey: Key.stravaAuthorizationHandoff)
                return
            }
            defaults.set(data, forKey: Key.stravaAuthorizationHandoff)
        }
    }

    var lastAuthorizedStravaAthleteID: String? {
        get { defaults.string(forKey: Key.lastAuthorizedStravaAthleteID) }
        set { defaults.set(newValue, forKey: Key.lastAuthorizedStravaAthleteID) }
    }
}
