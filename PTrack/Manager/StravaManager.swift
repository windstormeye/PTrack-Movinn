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
    static let trackedWorkoutsDidImportNotification = Notification.Name("studio.pj.PTrack.stravaTrackedWorkoutsDidImport")

    private let define = StravaDefine()
    private let defaults: UserDefaults
    private let networkManager: NetworkManager
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

    init(defaults: UserDefaults = .standard, networkManager: NetworkManager = .shared) {
        self.defaults = defaults
        self.networkManager = networkManager
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        super.init()
    }

    var hasStoredAuthorization: Bool {
        storedCredentials() != nil
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

    func authorizeAndLoadTrackedWorkouts(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        after startDate: Date? = nil,
        excludingStravaActivityIDs: Set<Int64> = [],
        pageLimit: Int? = nil,
        perPage: Int = 200,
        onTrackedWorkout: ((TrackedWorkout) async -> Void)? = nil
    ) async throws -> [TrackedWorkout] {
        _ = try await authorize(presentationContextProvider: presentationContextProvider)
        let workouts = try await loadTrackedWorkouts(
            after: startDate,
            excludingStravaActivityIDs: excludingStravaActivityIDs,
            pageLimit: pageLimit,
            perPage: perPage,
            onTrackedWorkout: onTrackedWorkout
        )
        NotificationCenter.default.post(name: Self.trackedWorkoutsDidImportNotification, object: workouts)
        return workouts
    }

    func loadTrackedWorkouts(
        after startDate: Date? = nil,
        excludingStravaActivityIDs: Set<Int64> = [],
        pageLimit: Int? = nil,
        perPage: Int = 200,
        onTrackedWorkout: ((TrackedWorkout) async -> Void)? = nil
    ) async throws -> [TrackedWorkout] {
        log(
            "load tracked workouts started, after: \(Self.debugDateString(startDate)), excluded cached IDs: \(excludingStravaActivityIDs.count), pageLimit: \(pageLimit.map(String.init) ?? "nil"), perPage: \(perPage)"
        )
        let activities = try await loadActivities(
            after: startDate,
            pageLimit: pageLimit,
            perPage: perPage
        )
        log("loaded summary activities: \(activities.count)")

        let unsupportedCount = activities.filter { $0.supportedSport == nil }.count
        let withoutRouteHintCount = activities.filter { $0.supportedSport != nil && !$0.hasRouteHint }.count
        let alreadyCachedCount = activities.filter { excludingStravaActivityIDs.contains($0.id) }.count
        let supportedActivities = activities.filter {
            $0.supportedSport != nil &&
            $0.hasRouteHint &&
            !excludingStravaActivityIDs.contains($0.id)
        }
        log(
            "filtered activities, route candidates: \(supportedActivities.count), unsupported: \(unsupportedCount), without route hint: \(withoutRouteHintCount), already cached: \(alreadyCachedCount)"
        )

        var trackedWorkouts: [TrackedWorkout] = []
        trackedWorkouts.reserveCapacity(supportedActivities.count)
        var importedActivityIDs = Set<Int64>()

        for (index, activity) in supportedActivities.enumerated() {
            guard importedActivityIDs.insert(activity.id).inserted else {
                log("skipping duplicate activity ID in current import: \(activity.id)")
                continue
            }

            do {
                log(
                    "loading streams \(index + 1)/\(supportedActivities.count), activity: \(activity.id), sport: \(activity.sportType ?? activity.type ?? "unknown"), start: \(Self.debugDateString(activity.startDate))"
                )
                let streams = try await loadActivityStreams(activityID: activity.id)
                if let workout = TrackedWorkout(stravaActivity: activity, streams: streams) {
                    trackedWorkouts.append(workout)
                    await onTrackedWorkout?(workout)
                    log(
                        "converted activity \(activity.id), coordinates: \(workout.coordinates.count), distance: \(workout.distanceMeters)"
                    )
                } else {
                    log("skipped activity \(activity.id), streams did not contain enough route data")
                }
            } catch {
                log("failed to load streams for activity \(activity.id): \(error.localizedDescription)")
            }
        }

        let sortedWorkouts = trackedWorkouts.sorted { $0.startDate > $1.startDate }
        log("load tracked workouts completed, converted routes: \(sortedWorkouts.count)")
        return sortedWorkouts
    }

    func authorize(
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> StravaStoredCredentials {
        try validateRedirectURI()

        guard let authorizationURL = authorizationURL() else {
            throw StravaManagerError.invalidURL
        }

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
                        let credentials = try await self.handleAuthorizationCallback(callbackURL)
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

    private func handleAuthorizationCallback(_ callbackURL: URL) async throws -> StravaStoredCredentials {
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
        return try await exchangeAuthorizationCode(code, grantedScope: grantedScope)
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        grantedScope: String?
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
        saveCredentials(credentials)
        log(
            "authorization token saved, athlete: \(credentials.athleteID.map(String.init) ?? "nil"), expiresAt: \(Self.debugDateString(credentials.expiresAt)), scope: \(credentials.scope ?? "nil")"
        )
        return credentials
    }

    private func refreshCredentials(_ credentials: StravaStoredCredentials) async throws -> StravaStoredCredentials {
        guard !credentials.refreshToken.isEmpty else {
            log("stored refresh token is empty; clearing authorization")
            clearCredentials(markReauthorizationRequired: true)
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
            ])
        } catch let error as NetworkError where Self.isAuthorizationFailure(error) {
            log("access token refresh failed because authorization is invalid; clearing stored credentials")
            clearCredentials(markReauthorizationRequired: true)
            throw StravaManagerError.reauthorizationRequired
        } catch {
            throw error
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

    private func sendTokenRequest<Response: Decodable>(parameters: [String: String]) async throws -> Response {
        let endpoint = try NetworkEndpoint(
            urlString: define.TokenURL,
            method: .post,
            parameters: Self.optionalParameters(parameters),
            parameterEncoding: .formURLEncoded
        )
        let grantType = parameters["grant_type"] ?? "unknown"
        log("token request started, grant_type: \(grantType)")
        do {
            let response: NetworkResponse<Response> = try await networkManager.response(endpoint, decoder: decoder)
            log("token request completed, grant_type: \(grantType), status: \(response.statusCode), bytes: \(response.data.count)")
            return response.value
        } catch {
            log("token request failed, grant_type: \(grantType), error: \(error.localizedDescription)")
            throw error
        }
    }

    private func loadActivities(
        after startDate: Date?,
        pageLimit: Int?,
        perPage: Int
    ) async throws -> [StravaSummaryActivity] {
        let pageSize = min(max(perPage, 1), 200)
        var allActivities: [StravaSummaryActivity] = []
        var loadedActivityIDs = Set<Int64>()
        var page = 1

        log(
            "activity paging started, after: \(Self.debugDateString(startDate)), pageLimit: \(pageLimit.map(String.init) ?? "nil"), perPage: \(pageSize)"
        )
        while pageLimit.map({ page <= max($0, 1) }) ?? true {
            var parameters: [String: NetworkParameterValue?] = [
                "page": .int(page),
                "per_page": .int(pageSize)
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
            let pageActivities: [StravaSummaryActivity] = try await authorizedJSON(endpoint)
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
                break
            }
            page += 1
        }

        log("activity paging completed, total unique activities: \(allActivities.count)")
        return allActivities
    }

    private func loadActivityStreams(activityID: Int64) async throws -> StravaActivityStreamSet {
        let endpoint = try NetworkEndpoint(
            urlString: "\(define.APIBaseURL)/activities/\(activityID)/streams",
            method: .get,
            parameters: [
                "keys": .stringArray(["time", "latlng", "altitude", "velocity_smooth", "distance", "heartrate", "cadence", "watts"]),
                "key_by_type": .bool(true)
            ],
            parameterEncoding: .query
        )
        let streams: StravaActivityStreamSet = try await authorizedJSON(endpoint)
        log("activity \(activityID) streams loaded, \(streamSummary(streams))")
        return streams
    }

    private func authorizedJSON<Response: Decodable>(_ endpoint: NetworkEndpoint) async throws -> Response {
        var credentials = try await validCredentials()
        do {
            return try await authorizedJSON(endpoint, accessToken: credentials.accessToken)
        } catch let error as NetworkError where error.statusCode == 401 {
            log("request unauthorized, refreshing token before retry: \(requestDescription(endpoint))")
            credentials = try await refreshCredentials(credentials)
            log("retrying request after token refresh: \(requestDescription(endpoint))")
            return try await authorizedJSON(endpoint, accessToken: credentials.accessToken)
        }
    }

    private func authorizedJSON<Response: Decodable>(
        _ endpoint: NetworkEndpoint,
        accessToken: String
    ) async throws -> Response {
        var endpoint = endpoint
        endpoint.headers["Authorization"] = "Bearer \(accessToken)"
        let description = requestDescription(endpoint)
        log("request started: \(description)")
        do {
            let response: NetworkResponse<Response> = try await networkManager.response(endpoint, decoder: decoder)
            log("request completed: \(description), status: \(response.statusCode), bytes: \(response.data.count)")
            return response.value
        } catch {
            log("request failed: \(description), error: \(error.localizedDescription)")
            throw error
        }
    }

    private func validCredentials() async throws -> StravaStoredCredentials {
        guard let credentials = storedCredentials() else {
            log("no stored Strava credentials")
            throw StravaManagerError.notAuthorized
        }

        if credentials.isAccessTokenValid {
            log("using stored access token, expiresAt: \(Self.debugDateString(credentials.expiresAt))")
            return credentials
        }

        log("stored access token expired or missing expiry, refreshing")
        return try await refreshCredentials(credentials)
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
        defaults.set(true, forKey: DefaultsKey.authorizationAttempted)
        defaults.set(false, forKey: DefaultsKey.authorizationNeedsReauthorization)
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
             .authorizationSessionFailedToStart,
             .cancelled,
             .invalidRedirectURI,
             .invalidURL,
             .missingAuthorizationCode:
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
    case authorizationSessionFailedToStart
    case cancelled
    case invalidRedirectURI(redirectURI: String, callbackDomain: String)
    case invalidURL
    case missingAuthorizationCode
    case notAuthorized
    case reauthorizationRequired

    var errorDescription: String? {
        switch self {
        case .authorizationDenied(let message):
            return message
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
        let altitudes = streams["altitude"]?.data.doubleValues
        let speeds = streams["velocity_smooth"]?.data.doubleValues

        return latLngPairs.enumerated().map { index, pair in
            RouteCoordinate(
                latitude: pair.latitude,
                longitude: pair.longitude,
                timestamp: startDate.addingTimeInterval(TimeInterval(times?[safe: index] ?? index)),
                horizontalAccuracyMeters: nil,
                altitudeMeters: altitudes?[safe: index],
                verticalAccuracyMeters: nil,
                speedMetersPerSecond: speeds?[safe: index],
                speedAccuracyMetersPerSecond: nil,
                courseDegrees: nil,
                courseAccuracyDegrees: nil,
                floorLevel: nil
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
    init?(stravaActivity activity: StravaSummaryActivity, streams: StravaActivityStreamSet) {
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
        metadata = Self.stravaMetadata(activity: activity, sport: sport)
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
        sport: StravaSupportedSport
    ) -> [String: TrackedMetadataValue] {
        var metadata: [String: TrackedMetadataValue] = [
            "strava.id": TrackedMetadataValue(type: "string", stringValue: "\(activity.id)")
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
