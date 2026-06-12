//
//  HealthWorkoutStore.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import CoreLocation
import Foundation
import HealthKit

final class HealthWorkoutStore {
    private let healthStore = HKHealthStore()

    var progressHandler: ((String) -> Void)?

    func requestAuthorization(completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthWorkoutStoreError.healthDataUnavailable))
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        print("PTrack HealthKit: requesting authorization on main thread: \(Thread.isMainThread), read type count: \(readTypes.count)")
        progressHandler?("正在请求 Apple 健康体能训练和路线读取权限...")
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            print("PTrack HealthKit: authorization request completed, success: \(success), error: \(String(describing: error))")
            if let error {
                completion(.failure(error))
            } else if success {
                completion(.success(()))
            } else {
                completion(.failure(HealthWorkoutStoreError.authorizationDenied))
            }
        }
    }

    func loadTrackedWorkouts(
        after startDate: Date?,
        excludingIDs excludedIDs: Set<String>,
        onTrackedWorkout: @escaping (TrackedWorkout) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        let types: [HKWorkoutActivityType] = [.cycling, .hiking, .walking, .running]
        let typePredicates = types.map { HKQuery.predicateForWorkouts(with: $0) }
        var predicates: [NSPredicate] = [
            NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        ]

        if let startDate {
            predicates.append(HKQuery.predicateForSamples(
                withStart: startDate.addingTimeInterval(-60),
                end: nil,
                options: .strictStartDate
            ))
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error {
                print("PTrack HealthKit: workout query failed: \(error)")
                completion(.failure(error))
                return
            }

            let workouts = ((samples as? [HKWorkout]) ?? [])
                .filter { !excludedIDs.contains($0.uuid.uuidString) }
            print("PTrack HealthKit: found \(workouts.count) new cycling/hiking/walking/running workouts")
            self.progressHandler?("找到 \(workouts.count) 条运动记录，正在逐条读取轨迹...")
            self.loadRoutes(
                for: workouts,
                onTrackedWorkout: onTrackedWorkout,
                completion: completion
            )
        }

        healthStore.execute(query)
    }

    private func loadRoutes(
        for workouts: [HKWorkout],
        onTrackedWorkout: @escaping (TrackedWorkout) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard !workouts.isEmpty else {
            completion(.success(0))
            return
        }

        var trackedWorkoutCount = 0
        var firstError: Error?

        func loadNextWorkout(at index: Int) {
            guard index < workouts.count else {
                if let firstError, trackedWorkoutCount == 0 {
                    completion(.failure(firstError))
                } else {
                    completion(.success(trackedWorkoutCount))
                }
                return
            }

            let workout = workouts[index]
            progressHandler?("正在读取 \(index + 1)/\(workouts.count)，已找到 \(trackedWorkoutCount) 条轨迹")

            loadLocations(for: workout) { result in
                switch result {
                case .success(let locations):
                    print(
                        "PTrack HealthKit: \(workout.workoutActivityType.rawValue) \(workout.startDate) route locations: \(locations.count)"
                    )
                    if locations.count > 1 {
                        trackedWorkoutCount += 1
                        onTrackedWorkout(TrackedWorkout(workout: workout, locations: locations))
                    }
                case .failure(let error):
                    print(
                        "PTrack HealthKit: route load failed for \(workout.workoutActivityType.rawValue) \(workout.startDate): \(error)"
                    )
                    if firstError == nil {
                        firstError = error
                    }
                }

                loadNextWorkout(at: index + 1)
            }
        }

        loadNextWorkout(at: 0)
    }

    private func loadLocations(
        for workout: HKWorkout,
        completion: @escaping (Result<[CLLocation], Error>) -> Void
    ) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let query = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error {
                print("PTrack HealthKit: route sample query failed: \(error)")
                completion(.failure(error))
                return
            }

            let routes = (samples as? [HKWorkoutRoute]) ?? []
            print("PTrack HealthKit: \(workout.workoutActivityType.rawValue) \(workout.startDate) routes: \(routes.count)")
            self.progressHandler?("正在读取 \(workout.startDate) 的 \(routes.count) 段轨迹...")
            self.collectLocations(from: routes, completion: completion)
        }

        healthStore.execute(query)
    }

    private func collectLocations(
        from routes: [HKWorkoutRoute],
        completion: @escaping (Result<[CLLocation], Error>) -> Void
    ) {
        guard !routes.isEmpty else {
            completion(.success([]))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var allLocations: [CLLocation] = []
        var firstError: Error?

        for route in routes {
            group.enter()

            var routeLocations: [CLLocation] = []
            var isFinished = false
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                func finishRouteIfNeeded() {
                    guard !isFinished else { return }
                    isFinished = true
                    lock.lock()
                    allLocations.append(contentsOf: routeLocations)
                    lock.unlock()
                    group.leave()
                }

                if let error {
                    print("PTrack HealthKit: workout route query failed: \(error)")
                    lock.lock()
                    if firstError == nil {
                        firstError = error
                    }
                    lock.unlock()
                    finishRouteIfNeeded()
                    return
                }

                if let locations {
                    routeLocations.append(contentsOf: locations)
                }

                if done {
                    finishRouteIfNeeded()
                }
            }

            healthStore.execute(routeQuery)
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let firstError, allLocations.isEmpty {
                completion(.failure(firstError))
            } else {
                completion(.success(allLocations.sorted { $0.timestamp < $1.timestamp }))
            }
        }
    }
}
