//
//  RouteCollectionCloudSyncStore.swift
//  PTrack
//
//  Created by Codex on 2026/6/18.
//

import CryptoKit
import Foundation
import UIKit

enum RouteCollectionCloudSyncSettings {
    static let isFeatureAvailable = true
    static let didChangeNotification = Notification.Name("studio.pj.PTrack.routeCollectionICloudSyncSettingDidChange")

    private static let isEnabledKey = "studio.pj.PTrack.routeCollection.iCloudSyncEnabled"
    private static let hasLocalDecisionKey = "studio.pj.PTrack.routeCollection.iCloudSyncHasLocalDecision"
    private static let knownRouteIDsKey = "studio.pj.PTrack.routeCollection.iCloudDocuments.knownRouteIDs"
    private static let pendingUploadRouteIDsKey = "studio.pj.PTrack.routeCollection.iCloudDocuments.pendingUploadRouteIDs"
    private static let pendingDeletionRouteIDsKey = "studio.pj.PTrack.routeCollection.iCloudDocuments.pendingDeletionRouteIDs"
    private static let identityTokenDataKey = "studio.pj.PTrack.routeCollection.iCloudDocuments.identityTokenData"
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool {
        isFeatureAvailable && defaults.bool(forKey: hasLocalDecisionKey) && defaults.bool(forKey: isEnabledKey)
    }

    static var knownRouteIDs: Set<String> {
        Set(defaults.stringArray(forKey: knownRouteIDsKey) ?? [])
    }

    static var pendingUploadRouteIDs: Set<String> {
        Set(defaults.stringArray(forKey: pendingUploadRouteIDsKey) ?? [])
    }

    static var pendingDeletionRouteIDs: Set<String> {
        Set(defaults.stringArray(forKey: pendingDeletionRouteIDsKey) ?? [])
    }

    static var identityTokenData: Data? {
        defaults.data(forKey: identityTokenDataKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        defaults.set(true, forKey: hasLocalDecisionKey)
        defaults.set(isEnabled, forKey: isEnabledKey)
        NotificationCenter.default.post(name: didChangeNotification, object: isEnabled)
    }

    static func setKnownRouteIDs(_ routeIDs: Set<String>) {
        defaults.set(Array(routeIDs).sorted(), forKey: knownRouteIDsKey)
    }

    static func addPendingUploadRouteIDs(_ routeIDs: Set<String>) {
        guard !routeIDs.isEmpty else {
            return
        }
        setPendingUploadRouteIDs(pendingUploadRouteIDs.union(routeIDs))
        setPendingDeletionRouteIDs(pendingDeletionRouteIDs.subtracting(routeIDs))
    }

    static func removePendingUploadRouteIDs(_ routeIDs: Set<String>) {
        guard !routeIDs.isEmpty else {
            return
        }
        setPendingUploadRouteIDs(pendingUploadRouteIDs.subtracting(routeIDs))
    }

    static func addPendingDeletionRouteID(_ routeID: String) {
        var deletions = pendingDeletionRouteIDs
        deletions.insert(routeID)
        setPendingDeletionRouteIDs(deletions)
        removePendingUploadRouteIDs([routeID])
    }

    static func removePendingDeletionRouteIDs(_ routeIDs: Set<String>) {
        guard !routeIDs.isEmpty else {
            return
        }
        setPendingDeletionRouteIDs(pendingDeletionRouteIDs.subtracting(routeIDs))
    }

    static func resetAccountSyncState() {
        defaults.removeObject(forKey: knownRouteIDsKey)
        defaults.removeObject(forKey: pendingUploadRouteIDsKey)
        defaults.removeObject(forKey: pendingDeletionRouteIDsKey)
        defaults.removeObject(forKey: identityTokenDataKey)
    }

    static func setIdentityTokenData(_ data: Data) {
        defaults.set(data, forKey: identityTokenDataKey)
    }

    private static func setPendingUploadRouteIDs(_ routeIDs: Set<String>) {
        defaults.set(Array(routeIDs).sorted(), forKey: pendingUploadRouteIDsKey)
    }

    private static func setPendingDeletionRouteIDs(_ routeIDs: Set<String>) {
        defaults.set(Array(routeIDs).sorted(), forKey: pendingDeletionRouteIDsKey)
    }
}

enum RouteCollectionCloudSyncError: LocalizedError {
    case proAccessRequired
    case iCloudAccountUnavailable
    case iCloudAccountChanged
    case containerUnavailable
    case documentUnavailable

    var errorDescription: String? {
        switch self {
        case .proAccessRequired:
            return AppLocalization.text(.proPaywallTitle)
        case .iCloudAccountUnavailable:
            return AppLocalization.text(.iCloudRouteSyncAccountUnavailableMessage)
        case .iCloudAccountChanged:
            return AppLocalization.text(.iCloudRouteSyncAccountChangedMessage)
        case .containerUnavailable:
            return AppLocalization.text(.iCloudRouteSyncDriveUnavailableMessage)
        case .documentUnavailable:
            return AppLocalization.text(.iCloudRouteSyncDocumentUnavailableMessage)
        }
    }
}

nonisolated struct RouteCollectionICloudDocumentState {
    let routeID: String
    let workout: TrackedWorkout
    let fileURL: URL
    let updatedAt: Date
    let isUploaded: Bool
    let isUploading: Bool
    let downloadingStatus: String?
    let isDownloading: Bool
    let transferErrorDescription: String?

    var needsTransfer: Bool {
        if transferErrorDescription != nil || isUploading || isDownloading || !isUploaded {
            return true
        }

        guard let downloadingStatus else {
            return false
        }
        return downloadingStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent
    }
}

struct RouteCollectionICloudDocumentsSnapshot {
    let documents: [RouteCollectionICloudDocumentState]
    let hasCompleteFileListing: Bool
    let isAuthoritative: Bool
    let failedDocumentCount: Int
    let errorDescription: String?
}

@MainActor
final class RouteCollectionICloudDocumentsStore {
    static let shared = RouteCollectionICloudDocumentsStore()

    private nonisolated struct MetadataEntry {
        let fileURL: URL
        let updatedAt: Date
        let fileSize: Int64?
        let isUploaded: Bool
        let isUploading: Bool
        let downloadingStatus: String?
        let isDownloading: Bool
        let transferErrorDescription: String?
    }

    private nonisolated struct DocumentFingerprint: Equatable {
        let standardizedPath: String
        let updatedAt: Date
        let fileSize: Int64?
    }

    private struct ParsedDocumentCacheEntry {
        let fingerprint: DocumentFingerprint
        let workout: TrackedWorkout?
        let parseErrorDescription: String?
    }

    private struct CachedDocumentParseError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private let fileManager = FileManager.default
    private var containerURL: URL?
    private var routesDirectoryURL: URL?
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryObservers: [NSObjectProtocol] = []
    private var identityObserver: NSObjectProtocol?
    private var didFinishInitialGathering = false
    private var didTimeOutWaitingForInitialGathering = false
    private var gatheringWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var documentURLsByRouteID: [String: Set<URL>] = [:]
    private var parsedDocumentCacheByPath: [String: ParsedDocumentCacheEntry] = [:]
    private(set) var identityGeneration = 0
    private var metadataQueryErrorDescription: String?

    var documentsDidChangeHandler: (() -> Void)?
    var iCloudIdentityDidChangeHandler: (() -> Void)?

    private init() {
        identityObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleICloudIdentityDidChange()
            }
        }
    }

    deinit {
        if let identityObserver {
            NotificationCenter.default.removeObserver(identityObserver)
        }
        metadataQueryObservers.forEach(NotificationCenter.default.removeObserver)
        metadataQuery?.stop()
    }

    func ensureReady(allowsIdentityChange: Bool = false) async throws {
        guard let identityToken = fileManager.ubiquityIdentityToken else {
            throw RouteCollectionCloudSyncError.iCloudAccountUnavailable
        }
        try validateIdentityToken(identityToken, allowsIdentityChange: allowsIdentityChange)
        let preparationGeneration = identityGeneration

        if routesDirectoryURL == nil {
            let resolvedContainerURL = await Task.detached(priority: .utility) {
                FileManager.default.url(forUbiquityContainerIdentifier: nil)
            }.value
            try validateIdentityDuringPreparation(expectedGeneration: preparationGeneration)
            guard let resolvedContainerURL else {
                throw RouteCollectionCloudSyncError.containerUnavailable
            }

            let resolvedRoutesDirectoryURL = resolvedContainerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Routes", isDirectory: true)
            containerURL = resolvedContainerURL
            routesDirectoryURL = resolvedRoutesDirectoryURL
        }

        guard let routesDirectoryURL else {
            throw RouteCollectionCloudSyncError.containerUnavailable
        }
        let routesDirectoryAlreadyExists = try await Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: routesDirectoryURL.path,
                isDirectory: &isDirectory
            )
            try FileManager.default.createDirectory(
                at: routesDirectoryURL,
                withIntermediateDirectories: true
            )
            return exists && isDirectory.boolValue
        }.value
        if !routesDirectoryAlreadyExists {
            documentURLsByRouteID.removeAll()
            parsedDocumentCacheByPath.removeAll()
        }

        try validateIdentityDuringPreparation(expectedGeneration: preparationGeneration)
        startMonitoringIfNeeded()
    }

    func documentSnapshot(
        progressHandler: ((_ completedCount: Int, _ totalCount: Int) -> Void)? = nil,
        cancellationCheck: (() throws -> Void)? = nil
    ) async throws -> RouteCollectionICloudDocumentsSnapshot {
        try await ensureReady()
        try cancellationCheck?()
        let queryFinished = await waitForInitialGathering()
        try cancellationCheck?()
        let entries = metadataEntriesIncludingLocalFiles()
        let currentPaths = Set(entries.map { $0.fileURL.standardizedFileURL.path })
        parsedDocumentCacheByPath = parsedDocumentCacheByPath.filter { currentPaths.contains($0.key) }
        progressHandler?(0, entries.count)

        var documents: [RouteCollectionICloudDocumentState] = []
        var firstErrorDescription: String?
        var failedDocumentCount = 0

        for (index, entry) in entries.enumerated() {
            do {
                try cancellationCheck?()
                let document = try await documentState(
                    for: entry,
                    cancellationCheck: cancellationCheck
                )
                documents.append(document)
            } catch {
                if error is CancellationError {
                    throw error
                }
                failedDocumentCount += 1
                firstErrorDescription = firstErrorDescription
                    ?? "\(entry.fileURL.lastPathComponent): \(error.localizedDescription)"
                print("PTrack Route Collection iCloud Documents: failed to read \(entry.fileURL.lastPathComponent): \(error)")
            }
            progressHandler?(index + 1, entries.count)
        }

        documents.sort { $0.updatedAt > $1.updatedAt }
        firstErrorDescription = firstErrorDescription
            ?? documents.compactMap(\.transferErrorDescription).first
        documentURLsByRouteID = Dictionary(grouping: documents, by: \.routeID)
            .mapValues { Set($0.map(\.fileURL)) }
        return RouteCollectionICloudDocumentsSnapshot(
            documents: documents,
            hasCompleteFileListing: queryFinished,
            isAuthoritative: queryFinished && failedDocumentCount == 0,
            failedDocumentCount: failedDocumentCount,
            errorDescription: firstErrorDescription ?? metadataQueryErrorDescription
        )
    }

    @discardableResult
    func upsert(
        routes: [TrackedWorkout],
        progressHandler: ((_ completedCount: Int, _ totalCount: Int) -> Void)? = nil,
        cancellationCheck: (() throws -> Void)? = nil
    ) async throws -> Set<String> {
        try await ensureReady()
        guard let routesDirectoryURL else {
            throw RouteCollectionCloudSyncError.containerUnavailable
        }

        progressHandler?(0, routes.count)
        var uploadedRouteIDs = Set<String>()
        for (index, route) in routes.enumerated() {
            try cancellationCheck?()
            let data = try await Task.detached(priority: .utility) {
                try GPXRouteExporter.iCloudDocumentData(for: route)
            }.value
            try cancellationCheck?()
            let destinationURL = documentURLsByRouteID[route.id]?.first
                ?? routesDirectoryURL.appendingPathComponent(Self.fileName(for: route), isDirectory: false)

            try await Task.detached(priority: .utility) {
                try Self.moveOrWriteUbiquitousDocument(data: data, destinationURL: destinationURL)
            }.value

            parsedDocumentCacheByPath.removeValue(forKey: destinationURL.standardizedFileURL.path)
            documentURLsByRouteID[route.id, default: []].insert(destinationURL)
            uploadedRouteIDs.insert(route.id)
            progressHandler?(index + 1, routes.count)
        }
        return uploadedRouteIDs
    }

    func deleteDocuments(
        routeIDs: Set<String>,
        documents: [RouteCollectionICloudDocumentState],
        cancellationCheck: (() throws -> Void)? = nil
    ) async throws -> Set<String> {
        guard !routeIDs.isEmpty else {
            return []
        }

        var documentURLsByID: [String: Set<URL>] = [:]
        for document in documents where routeIDs.contains(document.routeID) {
            documentURLsByID[document.routeID, default: []].insert(document.fileURL)
        }
        for routeID in routeIDs {
            if let cachedURLs = documentURLsByRouteID[routeID] {
                documentURLsByID[routeID, default: []].formUnion(cachedURLs)
            }
        }

        var deletedRouteIDs = Set<String>()
        for routeID in routeIDs {
            try cancellationCheck?()
            let fileURLs = documentURLsByID[routeID] ?? []
            var didDeleteEveryDocument = !fileURLs.isEmpty
            for fileURL in fileURLs {
                try cancellationCheck?()
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    didDeleteEveryDocument = false
                    continue
                }
                try await Task.detached(priority: .utility) {
                    try Self.coordinatedDelete(at: fileURL)
                }.value
                parsedDocumentCacheByPath.removeValue(forKey: fileURL.standardizedFileURL.path)
            }
            if didDeleteEveryDocument {
                deletedRouteIDs.insert(routeID)
                documentURLsByRouteID.removeValue(forKey: routeID)
            }
        }
        return deletedRouteIDs
    }

    private func startMonitoringIfNeeded() {
        guard metadataQuery == nil else {
            return
        }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE[c] %@", NSMetadataItemFSNameKey, "*.gpx")

        let didFinishObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.metadataQueryDidFinishGathering()
            }
        }
        let didUpdateObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.documentsDidChangeHandler?()
            }
        }

        metadataQuery = query
        metadataQueryObservers = [didFinishObserver, didUpdateObserver]
        didFinishInitialGathering = false
        didTimeOutWaitingForInitialGathering = false
        guard query.start() else {
            metadataQueryErrorDescription = AppLocalization.text(.iCloudRouteSyncDriveUnavailableMessage)
            stopMonitoring()
            return
        }
        metadataQueryErrorDescription = nil
    }

    private func metadataQueryDidFinishGathering() {
        didFinishInitialGathering = true
        let shouldRefreshAfterTimeout = didTimeOutWaitingForInitialGathering
        didTimeOutWaitingForInitialGathering = false
        let waiters = gatheringWaiters.values
        gatheringWaiters.removeAll()
        waiters.forEach { $0.resume(returning: true) }
        if shouldRefreshAfterTimeout {
            documentsDidChangeHandler?()
        }
    }

    private func waitForInitialGathering() async -> Bool {
        guard metadataQuery != nil else {
            return false
        }
        guard !didFinishInitialGathering else {
            return true
        }

        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            gatheringWaiters[waiterID] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let continuation = self?.gatheringWaiters.removeValue(forKey: waiterID) else {
                    return
                }
                self?.didTimeOutWaitingForInitialGathering = true
                continuation.resume(returning: false)
            }
        }
    }

    private func metadataEntriesIncludingLocalFiles() -> [MetadataEntry] {
        var entriesByPath: [String: MetadataEntry] = [:]

        if let metadataQuery {
            metadataQuery.disableUpdates()
            let results = metadataQuery.results
            for case let item as NSMetadataItem in results {
                guard let fileURL = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                      isRouteDocumentURL(fileURL) else {
                    continue
                }

                let uploadError = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
                let downloadError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
                entriesByPath[fileURL.standardizedFileURL.path] = MetadataEntry(
                    fileURL: fileURL,
                    updatedAt: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast,
                    fileSize: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value,
                    isUploaded: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? false,
                    isUploading: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool ?? false,
                    downloadingStatus: item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
                    isDownloading: item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false,
                    transferErrorDescription: uploadError?.localizedDescription ?? downloadError?.localizedDescription
                )
            }
            metadataQuery.enableUpdates()
        }

        if let routesDirectoryURL,
           let localFileURLs = try? fileManager.contentsOfDirectory(
               at: routesDirectoryURL,
               includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
               options: [.skipsHiddenFiles]
           ) {
            for fileURL in localFileURLs where fileURL.pathExtension.lowercased() == "gpx" {
                let path = fileURL.standardizedFileURL.path
                guard entriesByPath[path] == nil else {
                    continue
                }
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                entriesByPath[path] = MetadataEntry(
                    fileURL: fileURL,
                    updatedAt: values?.contentModificationDate ?? .distantPast,
                    fileSize: values?.fileSize.map(Int64.init),
                    isUploaded: false,
                    isUploading: true,
                    downloadingStatus: nil,
                    isDownloading: false,
                    transferErrorDescription: nil
                )
            }
        }

        return entriesByPath.values.sorted { $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent }
    }

    private func isRouteDocumentURL(_ fileURL: URL) -> Bool {
        guard fileURL.pathExtension.lowercased() == "gpx",
              let routesDirectoryURL else {
            return false
        }
        let directoryPath = routesDirectoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }

    private func documentState(
        for entry: MetadataEntry,
        cancellationCheck: (() throws -> Void)?
    ) async throws -> RouteCollectionICloudDocumentState {
        let path = entry.fileURL.standardizedFileURL.path
        let fingerprint = DocumentFingerprint(
            standardizedPath: path,
            updatedAt: entry.updatedAt,
            fileSize: entry.fileSize
        )

        if let cachedEntry = parsedDocumentCacheByPath[path],
           cachedEntry.fingerprint == fingerprint {
            if let workout = cachedEntry.workout {
                return Self.makeDocumentState(workout: workout, entry: entry)
            }
            throw CachedDocumentParseError(
                message: cachedEntry.parseErrorDescription
                    ?? AppLocalization.text(.iCloudRouteSyncDocumentUnavailableMessage)
            )
        }

        let data = try await readDocument(
            at: entry.fileURL,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck?()
        do {
            let workout = try await Task.detached(priority: .utility) {
                try Self.makeWorkout(data: data, entry: entry)
            }.value
            parsedDocumentCacheByPath[path] = ParsedDocumentCacheEntry(
                fingerprint: fingerprint,
                workout: workout,
                parseErrorDescription: nil
            )
            return Self.makeDocumentState(workout: workout, entry: entry)
        } catch {
            if error is CancellationError {
                throw error
            }
            parsedDocumentCacheByPath[path] = ParsedDocumentCacheEntry(
                fingerprint: fingerprint,
                workout: nil,
                parseErrorDescription: error.localizedDescription
            )
            throw error
        }
    }

    private func readDocument(
        at fileURL: URL,
        cancellationCheck: (() throws -> Void)?
    ) async throws -> Data {
        try cancellationCheck?()
        try? await Task.detached(priority: .utility) {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }.value

        var lastError: Error?
        for attempt in 0..<24 {
            try cancellationCheck?()
            try Task.checkCancellation()
            do {
                return try await Task.detached(priority: .utility) {
                    try Self.coordinatedData(at: fileURL)
                }.value
            } catch {
                lastError = error
                guard attempt < 23 else {
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw lastError ?? RouteCollectionCloudSyncError.documentUnavailable
    }

    private nonisolated static func makeWorkout(
        data: Data,
        entry: MetadataEntry
    ) throws -> TrackedWorkout {
        let fallbackDate = entry.updatedAt == .distantPast ? Date() : entry.updatedAt
        let parsedRoute = try GPXRouteParser.parse(data: data, fallbackDate: fallbackDate)
        let appMetadata = parsedRoute.appMetadata
        let rawRouteID = GPXRouteIdentity.routeCollectionID(
            embeddedID: appMetadata?.routeCollectionID,
            documentData: data
        )
        let fallbackTitle = entry.fileURL.deletingPathExtension().lastPathComponent
        return TrackedWorkout(
            routeCollectionID: rawRouteID,
            title: appMetadata?.title?.nonBlank ?? parsedRoute.title?.nonBlank ?? fallbackTitle,
            sourceName: appMetadata?.sourceName?.nonBlank ?? TrackedWorkout.routeCollectionImportSourceName,
            sourceURL: entry.fileURL,
            importedAt: appMetadata?.importedAt ?? fallbackDate,
            coordinates: parsedRoute.coordinates,
            segmentCoordinateCounts: parsedRoute.segmentCoordinateCounts,
            distanceMeters: appMetadata?.distanceMeters,
            durationSeconds: appMetadata?.durationSeconds,
            startDate: appMetadata?.startDate,
            activityTypeRawValue: appMetadata?.activityTypeRawValue,
            additionalMetadata: appMetadata?.additionalMetadata ?? [:]
        )
    }

    private nonisolated static func makeDocumentState(
        workout: TrackedWorkout,
        entry: MetadataEntry
    ) -> RouteCollectionICloudDocumentState {
        RouteCollectionICloudDocumentState(
            routeID: workout.id,
            workout: workout,
            fileURL: entry.fileURL,
            updatedAt: entry.updatedAt,
            isUploaded: entry.isUploaded,
            isUploading: entry.isUploading,
            downloadingStatus: entry.downloadingStatus,
            isDownloading: entry.isDownloading,
            transferErrorDescription: entry.transferErrorDescription
        )
    }

    private func handleICloudIdentityDidChange() {
        identityGeneration += 1
        stopMonitoring()
        containerURL = nil
        routesDirectoryURL = nil
        documentURLsByRouteID.removeAll()
        parsedDocumentCacheByPath.removeAll()
        iCloudIdentityDidChangeHandler?()
    }

    func validateIdentityGeneration(_ expectedGeneration: Int) throws {
        guard identityGeneration == expectedGeneration else {
            throw RouteCollectionCloudSyncError.iCloudAccountChanged
        }
    }

    func suspendMonitoring() {
        stopMonitoring()
    }

    func cancelPendingSnapshotWaits() {
        let waiters = gatheringWaiters.values
        gatheringWaiters.removeAll()
        waiters.forEach { $0.resume(returning: false) }
    }

    private func validateIdentityDuringPreparation(expectedGeneration: Int) throws {
        try validateIdentityGeneration(expectedGeneration)
        guard let currentIdentityToken = fileManager.ubiquityIdentityToken else {
            throw RouteCollectionCloudSyncError.iCloudAccountUnavailable
        }
        try validateIdentityToken(currentIdentityToken, allowsIdentityChange: false)
        try validateIdentityGeneration(expectedGeneration)
    }

    private func validateIdentityToken(_ identityToken: Any, allowsIdentityChange: Bool) throws {
        if let storedData = RouteCollectionCloudSyncSettings.identityTokenData {
            let storedToken = decodeIdentityToken(from: storedData)
            let tokensMatch: Bool
            if let currentObject = identityToken as? NSObject,
               let storedObject = storedToken as? NSObject {
                tokensMatch = currentObject.isEqual(storedObject)
            } else {
                tokensMatch = false
            }

            if !tokensMatch {
                handleICloudIdentityDidChange()
                guard allowsIdentityChange else {
                    throw RouteCollectionCloudSyncError.iCloudAccountChanged
                }
            }
        }

        let tokenData = try NSKeyedArchiver.archivedData(
            withRootObject: identityToken,
            requiringSecureCoding: false
        )
        RouteCollectionCloudSyncSettings.setIdentityTokenData(tokenData)
    }

    private func decodeIdentityToken(from data: Data) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
            return nil
        }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    }

    private func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        metadataQueryObservers.forEach(NotificationCenter.default.removeObserver)
        metadataQueryObservers.removeAll()
        didFinishInitialGathering = false
        didTimeOutWaitingForInitialGathering = false

        let waiters = gatheringWaiters.values
        gatheringWaiters.removeAll()
        waiters.forEach { $0.resume(returning: false) }
    }

    private nonisolated static func coordinatedData(at fileURL: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { coordinatedURL in
            readResult = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let readResult else {
            throw RouteCollectionCloudSyncError.documentUnavailable
        }
        return try readResult.get()
    }

    private nonisolated static func moveOrWriteUbiquitousDocument(data: Data, destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try coordinatedWrite(data: data, destinationURL: destinationURL)
            return
        }

        let stagingDirectoryURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PTrack", isDirectory: true)
            .appendingPathComponent("iCloudDocumentStaging", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
        let stagingURL = stagingDirectoryURL.appendingPathComponent(UUID().uuidString + ".gpx", isDirectory: false)
        try data.write(to: stagingURL, options: [.atomic])

        do {
            try fileManager.setUbiquitous(true, itemAt: stagingURL, destinationURL: destinationURL)
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: stagingURL)
                try coordinatedWrite(data: data, destinationURL: destinationURL)
            } else {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
        }
    }

    private nonisolated static func coordinatedWrite(data: Data, destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private nonisolated static func coordinatedDelete(at fileURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var deletionError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                deletionError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let deletionError {
            throw deletionError
        }
    }

    private nonisolated static func fileName(for route: TrackedWorkout) -> String {
        let title = utf8Prefix(sanitizedFileName(route.routeCollectionTitle ?? "Movinn Route"), maximumByteCount: 140)
        let routeHash = sha256Hex(Data(route.id.utf8)).prefix(32)
        return "\(title)--\(routeHash).gpx"
    }

    private nonisolated static func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let components = value
            .components(separatedBy: invalidCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let name = components.joined(separator: "-")
        return name.isEmpty ? "Movinn-Route" : String(name.prefix(60))
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func utf8Prefix(_ value: String, maximumByteCount: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let characterString = String(character)
            let nextByteCount = characterString.utf8.count
            guard byteCount + nextByteCount <= maximumByteCount else {
                break
            }
            result.append(character)
            byteCount += nextByteCount
        }
        return result.isEmpty ? "Movinn-Route" : result
    }
}

struct RouteCollectionCloudSyncProgress: Equatable {
    let isEnabled: Bool
    let completedCount: Int
    let totalCount: Int
    let isSynchronizing: Bool
    let errorDescription: String?

    init(
        isEnabled: Bool,
        completedCount: Int,
        totalCount: Int,
        isSynchronizing: Bool,
        errorDescription: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.isSynchronizing = isSynchronizing
        self.errorDescription = errorDescription
    }

    static let disabled = RouteCollectionCloudSyncProgress(
        isEnabled: false,
        completedCount: 0,
        totalCount: 0,
        isSynchronizing: false
    )

    var pendingCount: Int {
        max(totalCount - completedCount, 0)
    }

    var isComplete: Bool {
        isEnabled && !isSynchronizing && pendingCount == 0 && errorDescription == nil
    }
}

@MainActor
final class RouteCollectionCloudSyncCoordinator {
    static let shared = RouteCollectionCloudSyncCoordinator()
    static let progressDidChangeNotification = Notification.Name("studio.pj.PTrack.routeCollectionICloudSyncProgressDidChange")

    private let documentStoreProvider: @MainActor () -> RouteCollectionICloudDocumentsStore
    private var isSynchronizing = false
    private var needsAnotherPass = false
    private var progress = RouteCollectionCloudSyncProgress.disabled
    private var startSyncTask: Task<Void, Never>?
    private var metadataSyncTask: Task<Void, Never>?
    private var proSubscriptionObserver: NSObjectProtocol?
    private var didInstallDocumentHandlers = false
    private var synchronizationGeneration = 0
    private var localMutationGeneration = 0
    private var expiredSynchronizationGeneration: Int?

    var currentProgress: RouteCollectionCloudSyncProgress {
        let settingsEnabled = RouteCollectionCloudSyncSettings.isEnabled
        guard settingsEnabled || progress.isSynchronizing else {
            return .disabled
        }
        guard ProSubscriptionManager.shared.hasResolvedEntitlements,
              ProSubscriptionManager.shared.isProUser else {
            return .disabled
        }

        if settingsEnabled && !progress.isEnabled && !progress.isSynchronizing {
            return RouteCollectionCloudSyncProgress(
                isEnabled: true,
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                isSynchronizing: true,
                errorDescription: progress.errorDescription
            )
        }

        return RouteCollectionCloudSyncProgress(
            isEnabled: settingsEnabled || progress.isEnabled,
            completedCount: progress.completedCount,
            totalCount: progress.totalCount,
            isSynchronizing: progress.isSynchronizing,
            errorDescription: progress.errorDescription
        )
    }

    convenience init() {
        self.init(documentStoreProvider: { RouteCollectionICloudDocumentsStore.shared })
    }

    init(documentStoreProvider: @MainActor @escaping () -> RouteCollectionICloudDocumentsStore) {
        self.documentStoreProvider = documentStoreProvider
        proSubscriptionObserver = NotificationCenter.default.addObserver(
            forName: ProSubscriptionManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleProSubscriptionDidChange()
            }
        }
    }

    deinit {
        if let proSubscriptionObserver {
            NotificationCenter.default.removeObserver(proSubscriptionObserver)
        }
    }

    func startIfEnabled() {
        startIfEnabled(store: RouteCollectionStore())
    }

    func startIfEnabled(store: RouteCollectionStore) {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            updateProgress(.disabled)
            return
        }
        guard startSyncTask == nil, !isSynchronizing else {
            return
        }

        startSyncTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                startSyncTask = nil
            }

            do {
                try await synchronize(store: store)
            } catch is CancellationError {
                return
            } catch {
                print("PTrack Route Collection iCloud Documents: failed to start sync: \(error)")
            }
        }
    }

    func enableSync() async throws {
        try await enableSync(store: RouteCollectionStore())
    }

    func enableSync(store: RouteCollectionStore) async throws {
        await ProSubscriptionManager.shared.refreshAccess()
        guard ProSubscriptionManager.shared.isProUser else {
            throw RouteCollectionCloudSyncError.proAccessRequired
        }

        synchronizationGeneration += 1
        let documentStore = documentStoreProvider()
        installDocumentHandlersIfNeeded(on: documentStore)
        try await documentStore.ensureReady(allowsIdentityChange: true)
        await ProSubscriptionManager.shared.refreshAccess()
        guard ProSubscriptionManager.shared.isProUser else {
            documentStore.suspendMonitoring()
            throw RouteCollectionCloudSyncError.proAccessRequired
        }

        RouteCollectionCloudSyncSettings.setEnabled(true)
        let localRouteCount = await Self.loadLocalRoutes().count
        updateProgress(
            completedCount: 0,
            totalCount: localRouteCount,
            isSynchronizing: true,
            isEnabled: true
        )
        requestSynchronization(store: store)
    }

    func disableSync() {
        pauseRuntimeSync()
        RouteCollectionCloudSyncSettings.setEnabled(false)
    }

    private func pauseRuntimeSync() {
        synchronizationGeneration += 1
        needsAnotherPass = false
        startSyncTask?.cancel()
        startSyncTask = nil
        metadataSyncTask?.cancel()
        metadataSyncTask = nil
        if didInstallDocumentHandlers {
            documentStoreProvider().suspendMonitoring()
        }
        updateProgress(.disabled)
    }

    private func handleProSubscriptionDidChange() {
        guard ProSubscriptionManager.shared.hasResolvedEntitlements else {
            return
        }

        guard !ProSubscriptionManager.shared.isProUser else {
            if RouteCollectionCloudSyncSettings.isEnabled {
                if isSynchronizing {
                    needsAnotherPass = true
                } else {
                    startIfEnabled()
                }
            }
            return
        }

        if RouteCollectionCloudSyncSettings.isEnabled {
            pauseRuntimeSync()
        } else {
            updateProgress(.disabled)
        }
    }

    func synchronize() async throws {
        try await synchronize(store: RouteCollectionStore())
    }

    func synchronize(store: RouteCollectionStore) async throws {
        await ProSubscriptionManager.shared.refreshAccess()
        try Task.checkCancellation()
        guard ProSubscriptionManager.shared.isProUser else {
            if RouteCollectionCloudSyncSettings.isEnabled {
                pauseRuntimeSync()
            } else {
                updateProgress(.disabled)
            }
            return
        }

        try await synchronize(store: store, documentStore: documentStoreProvider())
    }

    func handleRoutesAppended(_ routes: [TrackedWorkout]) {
        guard RouteCollectionCloudSyncSettings.isEnabled, !routes.isEmpty else {
            return
        }

        localMutationGeneration += 1
        RouteCollectionCloudSyncSettings.addPendingUploadRouteIDs(Set(routes.map(\.id)))
        requestSynchronization(store: RouteCollectionStore())
    }

    func handleRouteDeleted(_ route: TrackedWorkout) {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            return
        }

        localMutationGeneration += 1
        RouteCollectionCloudSyncSettings.addPendingDeletionRouteID(route.id)
        requestSynchronization(store: RouteCollectionStore())
    }

    private func synchronize(
        store: RouteCollectionStore,
        documentStore: RouteCollectionICloudDocumentsStore,
        treatsSyncAsEnabled: Bool? = nil
    ) async throws {
        installDocumentHandlersIfNeeded(on: documentStore)
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            updateProgress(.disabled)
            return
        }
        guard !isSynchronizing else {
            needsAnotherPass = true
            return
        }

        let expectedSynchronizationGeneration = synchronizationGeneration
        isSynchronizing = true
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "Movinn iCloud Route Sync"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isSynchronizing,
                      self.synchronizationGeneration == expectedSynchronizationGeneration else {
                    return
                }
                self.expiredSynchronizationGeneration = expectedSynchronizationGeneration
                self.synchronizationGeneration += 1
                self.needsAnotherPass = false
                documentStore.cancelPendingSnapshotWaits()
            }
        }
        defer {
            let shouldRetry = needsAnotherPass
                && RouteCollectionCloudSyncSettings.isEnabled
                && ProSubscriptionManager.shared.isProUser
                && expiredSynchronizationGeneration != expectedSynchronizationGeneration
            isSynchronizing = false
            if expiredSynchronizationGeneration == expectedSynchronizationGeneration {
                expiredSynchronizationGeneration = nil
            }
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
            if shouldRetry {
                needsAnotherPass = false
                requestSynchronization(store: RouteCollectionStore())
            }
        }

        repeat {
            needsAnotherPass = false
            do {
                try await performSynchronizationPass(
                    store: store,
                    documentStore: documentStore,
                    treatsSyncAsEnabled: treatsSyncAsEnabled,
                    expectedSynchronizationGeneration: expectedSynchronizationGeneration
                )
            } catch {
                if error is CancellationError {
                    if !RouteCollectionCloudSyncSettings.isEnabled {
                        updateProgress(.disabled)
                    } else if expiredSynchronizationGeneration == expectedSynchronizationGeneration {
                        updateProgress(
                            completedCount: progress.completedCount,
                            totalCount: progress.totalCount,
                            isSynchronizing: false,
                            isEnabled: true,
                            errorDescription: progress.errorDescription
                        )
                    }
                    throw error
                }
                let localRouteCount = await Self.loadLocalRoutes().count
                let pendingOperationCount = RouteCollectionCloudSyncSettings.pendingUploadRouteIDs
                    .union(RouteCollectionCloudSyncSettings.pendingDeletionRouteIDs)
                    .count
                let fallbackTotalCount = max(max(progress.totalCount, localRouteCount), pendingOperationCount)
                let fallbackCompletedCount = min(
                    progress.completedCount,
                    max(fallbackTotalCount - pendingOperationCount, 0)
                )
                updateProgress(
                    completedCount: fallbackCompletedCount,
                    totalCount: fallbackTotalCount,
                    isSynchronizing: false,
                    isEnabled: treatsSyncAsEnabled ?? RouteCollectionCloudSyncSettings.isEnabled,
                    errorDescription: error.localizedDescription
                )
                throw error
            }
        } while needsAnotherPass
    }

    private func performSynchronizationPass(
        store: RouteCollectionStore,
        documentStore: RouteCollectionICloudDocumentsStore,
        treatsSyncAsEnabled: Bool?,
        expectedSynchronizationGeneration: Int
    ) async throws {
        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        let expectedLocalMutationGeneration = localMutationGeneration
        let progressIsEnabled = treatsSyncAsEnabled ?? RouteCollectionCloudSyncSettings.isEnabled
        let localRoutes = await Self.loadLocalRoutes()
        updateProgress(
            completedCount: 0,
            totalCount: localRoutes.count,
            isSynchronizing: true,
            isEnabled: progressIsEnabled
        )

        try await documentStore.ensureReady()
        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        guard validateLocalMutationGeneration(expectedLocalMutationGeneration) else {
            return
        }
        let identityGeneration = documentStore.identityGeneration
        let snapshot = try await documentStore.documentSnapshot(
            progressHandler: { [weak self] completedCount, cloudRouteCount in
                self?.updateProgress(
                    completedCount: min(completedCount, max(localRoutes.count, cloudRouteCount)),
                    totalCount: max(localRoutes.count, cloudRouteCount),
                    isSynchronizing: true,
                    isEnabled: progressIsEnabled
                )
            },
            cancellationCheck: { [weak self] in
                guard let self else {
                    throw CancellationError()
                }
                try self.validateSynchronizationGeneration(expectedSynchronizationGeneration)
            }
        )
        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        guard validateLocalMutationGeneration(expectedLocalMutationGeneration) else {
            return
        }
        try documentStore.validateIdentityGeneration(identityGeneration)

        var documents = snapshot.documents
        var remoteRouteIDs = Set(documents.map(\.routeID))
        let localRouteIDs = Set(localRoutes.map(\.id))
        let allPendingLocalUploadRouteIDs = RouteCollectionCloudSyncSettings.pendingUploadRouteIDs
        let pendingLocalUploadRouteIDs = allPendingLocalUploadRouteIDs.intersection(localRouteIDs)
        RouteCollectionCloudSyncSettings.removePendingUploadRouteIDs(
            allPendingLocalUploadRouteIDs.subtracting(localRouteIDs)
        )
        let pendingDeletionRouteIDs = RouteCollectionCloudSyncSettings.pendingDeletionRouteIDs
        if !pendingDeletionRouteIDs.isEmpty {
            try validateSynchronizationGeneration(expectedSynchronizationGeneration)
            let deletedRouteIDs = try await documentStore.deleteDocuments(
                routeIDs: pendingDeletionRouteIDs,
                documents: documents,
                cancellationCheck: { [weak self] in
                    guard let self else {
                        throw CancellationError()
                    }
                    try self.validateSynchronizationGeneration(expectedSynchronizationGeneration)
                }
            )
            try validateSynchronizationGeneration(expectedSynchronizationGeneration)
            guard validateLocalMutationGeneration(expectedLocalMutationGeneration) else {
                return
            }
            try documentStore.validateIdentityGeneration(identityGeneration)
            let absentDeletionRouteIDs = snapshot.isAuthoritative
                ? pendingDeletionRouteIDs.subtracting(remoteRouteIDs)
                : []
            let completedDeletionRouteIDs = deletedRouteIDs.union(absentDeletionRouteIDs)
            RouteCollectionCloudSyncSettings.removePendingDeletionRouteIDs(completedDeletionRouteIDs)
            documents.removeAll { completedDeletionRouteIDs.contains($0.routeID) }
            remoteRouteIDs.subtract(completedDeletionRouteIDs)
        }

        var knownRouteIDs = RouteCollectionCloudSyncSettings.knownRouteIDs
        let remotelyDeletedRouteIDs: Set<String>
        if snapshot.isAuthoritative {
            remotelyDeletedRouteIDs = knownRouteIDs
                .subtracting(remoteRouteIDs)
                .subtracting(pendingLocalUploadRouteIDs)
                .subtracting(RouteCollectionCloudSyncSettings.pendingDeletionRouteIDs)
        } else {
            remotelyDeletedRouteIDs = []
        }

        let locallyExcludedRouteIDs = remotelyDeletedRouteIDs
            .union(RouteCollectionCloudSyncSettings.pendingDeletionRouteIDs)
        var routesByID = Dictionary(
            uniqueKeysWithValues: localRoutes
                .filter { !locallyExcludedRouteIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )
        var resolvedRemoteRouteIDs = Set<String>()
        for document in documents where resolvedRemoteRouteIDs.insert(document.routeID).inserted {
            if pendingLocalUploadRouteIDs.contains(document.routeID), routesByID[document.routeID] != nil {
                continue
            }
            routesByID[document.routeID] = document.workout
        }

        let mergedRoutes = routesByID.values.sorted {
            let lhsDate = $0.routeCollectionImportedAt ?? $0.startDate
            let rhsDate = $1.routeCollectionImportedAt ?? $1.startDate
            return lhsDate == rhsDate ? $0.startDate > $1.startDate : lhsDate > rhsDate
        }
        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        try documentStore.validateIdentityGeneration(identityGeneration)
        let routesAreEquivalent = await Self.routesAreEquivalent(localRoutes, mergedRoutes)
        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        guard validateLocalMutationGeneration(expectedLocalMutationGeneration) else {
            return
        }
        try documentStore.validateIdentityGeneration(identityGeneration)
        if !routesAreEquivalent {
            store.replaceAfterExternalComparison(with: mergedRoutes)
        }

        let uploadCandidates = mergedRoutes.filter {
            (pendingLocalUploadRouteIDs.contains($0.id) || !remoteRouteIDs.contains($0.id))
                && !remotelyDeletedRouteIDs.contains($0.id)
        }
        let routesNeedingUpload: [TrackedWorkout]
        let deferredUploadRouteIDs: Set<String>
        if snapshot.hasCompleteFileListing {
            routesNeedingUpload = uploadCandidates
            deferredUploadRouteIDs = []
        } else {
            routesNeedingUpload = []
            deferredUploadRouteIDs = Set(uploadCandidates.map(\.id))
        }

        let mergedRouteIDs = Set(mergedRoutes.map(\.id))
        let pendingBeforeUpload = Set(documents.filter(\.needsTransfer).map(\.routeID))
            .union(RouteCollectionCloudSyncSettings.pendingUploadRouteIDs)
            .union(uploadCandidates.map(\.id))
            .intersection(mergedRouteIDs)
            .count + snapshot.failedDocumentCount
        let totalBeforeUpload = mergedRoutes.count + snapshot.failedDocumentCount
        updateProgress(
            completedCount: max(totalBeforeUpload - pendingBeforeUpload, 0),
            totalCount: totalBeforeUpload,
            isSynchronizing: true,
            isEnabled: progressIsEnabled,
            errorDescription: snapshot.errorDescription
        )

        RouteCollectionCloudSyncSettings.addPendingUploadRouteIDs(
            Set(routesNeedingUpload.map(\.id))
        )
        var newlyPlacedRouteIDs = Set<String>()
        for route in routesNeedingUpload {
            try validateSynchronizationGeneration(expectedSynchronizationGeneration)
            let placedRouteIDs = try await documentStore.upsert(
                routes: [route],
                cancellationCheck: { [weak self] in
                    guard let self else {
                        throw CancellationError()
                    }
                    try self.validateSynchronizationGeneration(expectedSynchronizationGeneration)
                }
            )
            try validateSynchronizationGeneration(expectedSynchronizationGeneration)
            guard validateLocalMutationGeneration(expectedLocalMutationGeneration) else {
                return
            }
            try documentStore.validateIdentityGeneration(identityGeneration)
            RouteCollectionCloudSyncSettings.removePendingUploadRouteIDs(placedRouteIDs)
            newlyPlacedRouteIDs.formUnion(placedRouteIDs)
            knownRouteIDs.formUnion(placedRouteIDs)
            RouteCollectionCloudSyncSettings.setKnownRouteIDs(knownRouteIDs)
        }
        if !newlyPlacedRouteIDs.isEmpty {
            needsAnotherPass = true
        }

        try validateSynchronizationGeneration(expectedSynchronizationGeneration)
        try documentStore.validateIdentityGeneration(identityGeneration)
        knownRouteIDs.formUnion(remoteRouteIDs)
        knownRouteIDs.subtract(remotelyDeletedRouteIDs)
        knownRouteIDs.subtract(RouteCollectionCloudSyncSettings.pendingDeletionRouteIDs)
        RouteCollectionCloudSyncSettings.setKnownRouteIDs(knownRouteIDs)

        let transferPendingRouteIDs = Set(documents.filter(\.needsTransfer).map(\.routeID))
            .union(RouteCollectionCloudSyncSettings.pendingUploadRouteIDs)
            .union(newlyPlacedRouteIDs)
            .union(deferredUploadRouteIDs)
        let pendingCount = transferPendingRouteIDs.intersection(mergedRouteIDs).count
            + snapshot.failedDocumentCount
        let totalCount = mergedRoutes.count + snapshot.failedDocumentCount
        updateProgress(
            completedCount: max(totalCount - pendingCount, 0),
            totalCount: totalCount,
            isSynchronizing: !snapshot.hasCompleteFileListing,
            isEnabled: progressIsEnabled,
            errorDescription: snapshot.errorDescription
        )
    }

    private func installDocumentHandlersIfNeeded(on documentStore: RouteCollectionICloudDocumentsStore) {
        guard !didInstallDocumentHandlers else {
            return
        }
        didInstallDocumentHandlers = true
        documentStore.documentsDidChangeHandler = { [weak self] in
            self?.handleDocumentsDidChange()
        }
        documentStore.iCloudIdentityDidChangeHandler = { [weak self] in
            guard let self else {
                return
            }
            self.synchronizationGeneration += 1
            RouteCollectionCloudSyncSettings.resetAccountSyncState()
            if RouteCollectionCloudSyncSettings.isEnabled {
                RouteCollectionCloudSyncSettings.setEnabled(false)
            }
            self.updateProgress(.disabled)
        }
    }

    private func handleDocumentsDidChange() {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            return
        }
        if isSynchronizing {
            needsAnotherPass = true
            return
        }

        metadataSyncTask?.cancel()
        metadataSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else {
                return
            }
            do {
                try await self?.synchronize(store: RouteCollectionStore())
            } catch {
                print("PTrack Route Collection iCloud Documents: metadata refresh failed: \(error)")
            }
        }
    }

    private func requestSynchronization(store: RouteCollectionStore) {
        guard RouteCollectionCloudSyncSettings.isEnabled else {
            return
        }
        if isSynchronizing {
            needsAnotherPass = true
            return
        }
        Task { @MainActor [weak self] in
            guard RouteCollectionCloudSyncSettings.isEnabled else {
                return
            }
            do {
                try await self?.synchronize(store: store)
            } catch {
                print("PTrack Route Collection iCloud Documents: route change sync failed: \(error)")
            }
        }
    }

    private nonisolated static func loadLocalRoutes() async -> [TrackedWorkout] {
        await Task.detached(priority: .utility) {
            RouteCollectionStore().load()
        }.value
    }

    private nonisolated static func routesAreEquivalent(
        _ lhs: [TrackedWorkout],
        _ rhs: [TrackedWorkout]
    ) async -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
        }.value
    }

    private func validateSynchronizationGeneration(_ expectedGeneration: Int) throws {
        guard RouteCollectionCloudSyncSettings.isEnabled,
              ProSubscriptionManager.shared.hasResolvedEntitlements,
              ProSubscriptionManager.shared.isProUser,
              synchronizationGeneration == expectedGeneration else {
            throw CancellationError()
        }
    }

    private func validateLocalMutationGeneration(_ expectedGeneration: Int) -> Bool {
        guard localMutationGeneration == expectedGeneration else {
            needsAnotherPass = true
            return false
        }
        return true
    }

    private func updateProgress(
        completedCount: Int,
        totalCount: Int,
        isSynchronizing: Bool,
        isEnabled: Bool,
        errorDescription: String? = nil
    ) {
        let normalizedTotalCount = max(totalCount, 0)
        let normalizedCompletedCount = min(max(completedCount, 0), normalizedTotalCount)
        updateProgress(RouteCollectionCloudSyncProgress(
            isEnabled: isEnabled,
            completedCount: normalizedCompletedCount,
            totalCount: normalizedTotalCount,
            isSynchronizing: isSynchronizing,
            errorDescription: errorDescription
        ))
    }

    private func updateProgress(_ nextProgress: RouteCollectionCloudSyncProgress) {
        guard progress != nextProgress else {
            return
        }
        progress = nextProgress
        NotificationCenter.default.post(name: Self.progressDidChangeNotification, object: nextProgress)
    }
}

private extension String {
    nonisolated var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
