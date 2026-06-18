//
//  RouteCollectionCloudSyncStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/18.
//

import CloudKit
import Foundation

enum RouteCollectionCloudSyncSettings {
    static let isFeatureAvailable = false
    static let didChangeNotification = Notification.Name("studio.pj.PTrack.routeCollectionICloudSyncSettingDidChange")

    private static let isEnabledKey = "studio.pj.PTrack.routeCollection.iCloudSyncEnabled"
    private static let hasLocalDecisionKey = "studio.pj.PTrack.routeCollection.iCloudSyncHasLocalDecision"
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool {
        isFeatureAvailable && defaults.bool(forKey: hasLocalDecisionKey) && defaults.bool(forKey: isEnabledKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        defaults.set(true, forKey: hasLocalDecisionKey)
        defaults.set(isEnabled, forKey: isEnabledKey)
        NotificationCenter.default.post(name: didChangeNotification, object: isEnabled)
    }
}

enum RouteCollectionCloudSyncError: LocalizedError {
    case storeUnavailable
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "iCloud route collection sync is unavailable."
        case .accountUnavailable:
            return "iCloud account is unavailable."
        }
    }
}

@MainActor
final class RouteCollectionCloudSyncStore {
    static let shared = RouteCollectionCloudSyncStore()

    private static let cloudKitContainerIdentifier = "iCloud.studio.pj.app.PTrack"
    private static let zoneName = "PTrackRouteCollection"
    private static let zoneID = CKRecordZone.ID(zoneName: zoneName)
    private static let recordType = "ImportedRoute"
    private static let routeIDField = "routeID"
    private static let payloadField = "payload"
    private static let legacyPayloadDataField = "payloadData"
    private static let updatedAtField = "updatedAt"
    private static let isDeletedField = "isDeleted"

    private let container: CKContainer
    private let database: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let assetDirectoryURL: URL
    private var didEnsureRecordZone = false

    private init() {
        container = CKContainer(identifier: Self.cloudKitContainerIdentifier)
        database = container.privateCloudDatabase
        assetDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("PTrackRouteCollectionCloudAssets", isDirectory: true)
    }

    func ensureReady() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            throw RouteCollectionCloudSyncError.accountUnavailable(status)
        }
        try await ensureRecordZoneExists()
    }

    func recordStates(
        downloadProgressHandler: ((_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws -> [RouteCollectionCloudRecordState] {
        let records = try await fetchRouteRecordsFromChanges()
        let activeRecords = records.filter { record in
            !(record[Self.isDeletedField] as? Bool ?? false)
        }
        var completedDownloadCount = 0

        print("PTrack Route Collection iCloud: found \(activeRecords.count) active remote route records.")
        downloadProgressHandler?(0, activeRecords.count)

        let activeRecordIDs = Set(activeRecords.map(\.recordID))
        var states: [RouteCollectionCloudRecordState] = []

        for record in records {
            guard activeRecordIDs.contains(record.recordID) else {
                if let state = try decodedState(from: record) {
                    states.append(state)
                }
                continue
            }

            if let state = try decodedState(from: record) {
                states.append(state)
            }
            completedDownloadCount += 1
            downloadProgressHandler?(completedDownloadCount, activeRecords.count)
        }

        return states.sorted { $0.updatedAt > $1.updatedAt }
    }

    func upsert(
        routes: [TrackedWorkout],
        progressHandler: ((_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws {
        progressHandler?(0, routes.count)

        guard !routes.isEmpty else {
            return
        }

        try fileManager.createDirectory(at: assetDirectoryURL, withIntermediateDirectories: true)

        for (index, route) in routes.enumerated() {
            let record = try await record(routeID: route.id)
                ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: route.id))
            let payloadData = try encoder.encode(route)
            let payloadURL = assetFileURL(routeID: route.id)
            try payloadData.write(to: payloadURL, options: [.atomic])

            record[Self.routeIDField] = route.id
            record[Self.payloadField] = CKAsset(fileURL: payloadURL)
            record[Self.legacyPayloadDataField] = nil
            record[Self.updatedAtField] = Date()
            record[Self.isDeletedField] = false

            try await save(record)
            try? fileManager.removeItem(at: payloadURL)

            progressHandler?(index + 1, routes.count)
        }
    }

    func markDeleted(routeID: String) async throws {
        let record = try await record(routeID: routeID)
            ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: routeID))

        record[Self.routeIDField] = routeID
        record[Self.payloadField] = nil
        record[Self.legacyPayloadDataField] = nil
        record[Self.updatedAtField] = Date()
        record[Self.isDeletedField] = true

        try await save(record)
    }

    private func fetchRouteRecordsFromChanges() async throws -> [CKRecord] {
        let desiredKeys = [
            Self.routeIDField,
            Self.payloadField,
            Self.legacyPayloadDataField,
            Self.updatedAtField,
            Self.isDeletedField
        ]
        var recordsByID: [CKRecord.ID: CKRecord] = [:]
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let page = try await database.recordZoneChanges(
                inZoneWith: Self.zoneID,
                since: changeToken,
                desiredKeys: desiredKeys,
                resultsLimit: 100
            )

            for (recordID, result) in page.modificationResultsByID {
                let modification = try result.get()
                guard modification.record.recordType == Self.recordType else {
                    continue
                }
                recordsByID[recordID] = modification.record
            }

            for deletion in page.deletions where deletion.recordType == Self.recordType {
                recordsByID.removeValue(forKey: deletion.recordID)
            }

            changeToken = page.changeToken
            moreComing = page.moreComing
        }

        return Array(recordsByID.values)
    }

    private func ensureRecordZoneExists() async throws {
        guard !didEnsureRecordZone else {
            return
        }

        let existingZones = try await database.recordZones(for: [Self.zoneID])
        if let existingZoneResult = existingZones[Self.zoneID] {
            do {
                _ = try existingZoneResult.get()
                didEnsureRecordZone = true
                return
            } catch {
                if !isUnknownItemError(error) {
                    throw error
                }
            }
        }

        let zone = CKRecordZone(zoneID: Self.zoneID)
        let result = try await database.modifyRecordZones(saving: [zone], deleting: [])
        guard let saveResult = result.saveResults[Self.zoneID] else {
            throw RouteCollectionCloudSyncError.storeUnavailable
        }

        _ = try saveResult.get()
        didEnsureRecordZone = true
    }

    private func record(routeID: String) async throws -> CKRecord? {
        try await record(recordID: Self.recordID(for: routeID), desiredKeys: nil)
    }

    private func record(recordID: CKRecord.ID, desiredKeys: [String]?) async throws -> CKRecord? {
        let results = try await database.records(for: [recordID], desiredKeys: desiredKeys)

        guard let result = results[recordID] else {
            return nil
        }

        do {
            return try result.get()
        } catch {
            if isUnknownItemError(error) {
                return nil
            }
            throw error
        }
    }

    private func save(_ record: CKRecord) async throws {
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        guard let savedResult = result.saveResults[record.recordID] else {
            throw RouteCollectionCloudSyncError.storeUnavailable
        }

        _ = try savedResult.get()
    }

    private func decodedState(from record: CKRecord) throws -> RouteCollectionCloudRecordState? {
        let routeID = record[Self.routeIDField] as? String ?? record.recordID.recordName
        let isDeleted = record[Self.isDeletedField] as? Bool ?? false
        let updatedAt = record[Self.updatedAtField] as? Date
            ?? record.modificationDate
            ?? Date.distantPast
        let workout = try decodedWorkout(from: record, routeID: routeID, isDeleted: isDeleted)

        if !isDeleted, workout == nil {
            print("PTrack Route Collection iCloud: skipped route \(routeID) because payload is missing.")
            return nil
        }

        return RouteCollectionCloudRecordState(
            routeID: routeID,
            workout: workout,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }

    private func decodedWorkout(from record: CKRecord, routeID: String, isDeleted: Bool) throws -> TrackedWorkout? {
        guard !isDeleted else {
            return nil
        }

        let payloadData: Data
        if let payloadAsset = record[Self.payloadField] as? CKAsset, let fileURL = payloadAsset.fileURL {
            payloadData = try Data(contentsOf: fileURL)
        } else if let legacyPayloadData = record[Self.legacyPayloadDataField] as? Data {
            payloadData = legacyPayloadData
        } else {
            return nil
        }

        do {
            return try decoder.decode(TrackedWorkout.self, from: payloadData)
        } catch {
            print("PTrack Route Collection iCloud: failed to decode route \(routeID): \(error)")
            throw error
        }
    }

    private func assetFileURL(routeID: String) -> URL {
        assetDirectoryURL.appendingPathComponent(
            "\(Self.recordName(for: routeID))-\(UUID().uuidString).json",
            isDirectory: false
        )
    }

    private func isUnknownItemError(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func recordID(for routeID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName(for: routeID), zoneID: zoneID)
    }

    private static func recordName(for routeID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return routeID.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? routeID
    }
}

struct RouteCollectionCloudRecordState {
    let routeID: String
    let workout: TrackedWorkout?
    let updatedAt: Date
    let isDeleted: Bool
}

struct RouteCollectionCloudSyncProgress: Equatable {
    let isEnabled: Bool
    let completedCount: Int
    let totalCount: Int
    let isSynchronizing: Bool

    static let disabled = RouteCollectionCloudSyncProgress(
        isEnabled: false,
        completedCount: 0,
        totalCount: 0,
        isSynchronizing: false
    )

    var isComplete: Bool {
        isEnabled && !isSynchronizing && completedCount >= totalCount
    }
}

@MainActor
final class RouteCollectionCloudSyncCoordinator {
    static let shared = RouteCollectionCloudSyncCoordinator()
    static let progressDidChangeNotification = Notification.Name("studio.pj.PTrack.routeCollectionICloudSyncProgressDidChange")

    private let cloudStoreProvider: @MainActor () -> RouteCollectionCloudSyncStore
    private var isSynchronizing = false
    private var progress = RouteCollectionCloudSyncProgress.disabled

    var currentProgress: RouteCollectionCloudSyncProgress {
        let settingsEnabled = RouteCollectionCloudSyncSettings.isEnabled
        guard settingsEnabled || progress.isSynchronizing else {
            return .disabled
        }

        if settingsEnabled && !progress.isEnabled && !progress.isSynchronizing {
            return RouteCollectionCloudSyncProgress(
                isEnabled: true,
                completedCount: 0,
                totalCount: 0,
                isSynchronizing: true
            )
        }

        return settingsEnabled && progress.isEnabled
            ? progress
            : RouteCollectionCloudSyncProgress(
                isEnabled: settingsEnabled || progress.isEnabled,
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                isSynchronizing: progress.isSynchronizing
            )
    }

    convenience init() {
        self.init(cloudStoreProvider: { RouteCollectionCloudSyncStore.shared })
    }

    init(cloudStoreProvider: @MainActor @escaping () -> RouteCollectionCloudSyncStore) {
        self.cloudStoreProvider = cloudStoreProvider
    }

    func startIfEnabled() {
        startIfEnabled(store: RouteCollectionStore())
    }

    func startIfEnabled(store: RouteCollectionStore) {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            updateProgress(.disabled)
            return
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.synchronize(store: store)
            } catch {
                print("PTrack Route Collection iCloud: failed to start sync: \(error)")
            }
        }
    }

    func enableSync() async throws {
        try await enableSync(store: RouteCollectionStore())
    }

    func enableSync(store: RouteCollectionStore) async throws {
        let cloudStore = cloudStoreProvider()
        try await cloudStore.ensureReady()
        do {
            try await synchronize(store: store, cloudStore: cloudStore, treatsSyncAsEnabled: true)
            RouteCollectionCloudSyncSettings.setEnabled(true)
        } catch {
            if !RouteCollectionCloudSyncSettings.isEnabled {
                updateProgress(.disabled)
            }
            throw error
        }
    }

    func synchronize() async throws {
        try await synchronize(store: RouteCollectionStore())
    }

    func synchronize(store: RouteCollectionStore) async throws {
        try await synchronize(store: store, cloudStore: cloudStoreProvider())
    }

    private func synchronize(
        store: RouteCollectionStore,
        cloudStore: RouteCollectionCloudSyncStore,
        treatsSyncAsEnabled: Bool? = nil
    ) async throws {
        guard !isSynchronizing else {
            return
        }

        isSynchronizing = true
        defer {
            isSynchronizing = false
        }

        let progressIsEnabled = treatsSyncAsEnabled ?? RouteCollectionCloudSyncSettings.isEnabled
        let localRoutes = store.load()
        updateProgress(
            completedCount: 0,
            totalCount: localRoutes.count,
            isSynchronizing: true,
            isEnabled: progressIsEnabled
        )

        do {
            try await cloudStore.ensureReady()
        } catch {
            updateProgress(
                completedCount: 0,
                totalCount: localRoutes.count,
                isSynchronizing: false,
                isEnabled: progressIsEnabled
            )
            throw error
        }

        let recordStates: [RouteCollectionCloudRecordState]
        do {
            recordStates = try await cloudStore.recordStates { [weak self] completedCount, cloudRouteCount in
                self?.updateProgress(
                    completedCount: completedCount,
                    totalCount: max(localRoutes.count, cloudRouteCount),
                    isSynchronizing: true,
                    isEnabled: progressIsEnabled
                )
            }
        } catch {
            updateProgress(
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                isSynchronizing: false,
                isEnabled: progressIsEnabled
            )
            throw error
        }

        let mergedRoutes = mergedRoutes(localRoutes: localRoutes, recordStates: recordStates)
        let activeCloudRouteIDs = Set(
            recordStates
                .filter { !$0.isDeleted && $0.workout != nil }
                .map(\.routeID)
        )
        let routesNeedingUpload = mergedRoutes.filter { !activeCloudRouteIDs.contains($0.id) }
        let totalCount = mergedRoutes.count
        let initialCompletedCount = max(0, totalCount - routesNeedingUpload.count)
        let needsLocalReplace = !routesAreEquivalent(localRoutes, mergedRoutes)

        if needsLocalReplace || !routesNeedingUpload.isEmpty {
            updateProgress(
                completedCount: initialCompletedCount,
                totalCount: totalCount,
                isSynchronizing: true,
                isEnabled: progressIsEnabled
            )
        }

        if needsLocalReplace {
            store.replace(with: mergedRoutes)
        }

        if !routesNeedingUpload.isEmpty {
            try await cloudStore.upsert(routes: routesNeedingUpload) { [weak self] uploadedCount, _ in
                self?.updateProgress(
                    completedCount: min(initialCompletedCount + uploadedCount, totalCount),
                    totalCount: totalCount,
                    isSynchronizing: true,
                    isEnabled: progressIsEnabled
                )
            }
        }

        updateProgress(
            completedCount: totalCount,
            totalCount: totalCount,
            isSynchronizing: false,
            isEnabled: progressIsEnabled
        )
    }

    func handleRoutesAppended(_ routes: [TrackedWorkout]) {
        guard RouteCollectionCloudSyncSettings.isEnabled, !routes.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.synchronize(store: RouteCollectionStore())
            } catch {
                print("PTrack Route Collection iCloud: failed to upload routes: \(error)")
            }
        }
    }

    func handleRouteDeleted(_ route: TrackedWorkout) {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let remainingRouteCount = RouteCollectionStore().load().count
                updateProgress(
                    completedCount: remainingRouteCount,
                    totalCount: remainingRouteCount,
                    isSynchronizing: true,
                    isEnabled: true
                )
                try await cloudStoreProvider().markDeleted(routeID: route.id)
                updateProgress(
                    completedCount: remainingRouteCount,
                    totalCount: remainingRouteCount,
                    isSynchronizing: false,
                    isEnabled: true
                )
            } catch {
                print("PTrack Route Collection iCloud: failed to delete route: \(error)")
            }
        }
    }

    private func mergedRoutes(
        localRoutes: [TrackedWorkout],
        recordStates: [RouteCollectionCloudRecordState]
    ) -> [TrackedWorkout] {
        let deletedRouteIDs = Set(recordStates.filter(\.isDeleted).map(\.routeID))
        var routesByID = Dictionary(
            uniqueKeysWithValues: localRoutes
                .filter { !deletedRouteIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        for state in recordStates where !state.isDeleted {
            guard let workout = state.workout else {
                continue
            }

            routesByID[workout.id] = workout
        }

        return routesByID.values.sorted { $0.startDate > $1.startDate }
    }

    private func routesAreEquivalent(_ lhs: [TrackedWorkout], _ rhs: [TrackedWorkout]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        let encoder = JSONEncoder()
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }

    private func updateProgress(
        completedCount: Int,
        totalCount: Int,
        isSynchronizing: Bool,
        isEnabled: Bool
    ) {
        let normalizedTotalCount = max(0, totalCount)
        let normalizedCompletedCount = min(max(0, completedCount), normalizedTotalCount)
        updateProgress(RouteCollectionCloudSyncProgress(
            isEnabled: isEnabled,
            completedCount: normalizedCompletedCount,
            totalCount: normalizedTotalCount,
            isSynchronizing: isSynchronizing
        ))
    }

    private func updateProgress(_ nextProgress: RouteCollectionCloudSyncProgress) {
        guard progress != nextProgress else {
            return
        }

        progress = nextProgress
        NotificationCenter.default.post(
            name: Self.progressDidChangeNotification,
            object: nextProgress
        )
    }
}
