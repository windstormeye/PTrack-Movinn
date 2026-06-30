//
//  ProSubscriptionManager.swift
//  PTrack
//
//  Created by Codex on 2026/6/30.
//

import Foundation
import StoreKit
import UIKit

enum ProSubscriptionPurchaseResult: Equatable {
    case purchased
    case alreadyActive
    case cancelled
    case pending
}

enum ProSubscriptionRestoreResult: Equatable {
    case restored
    case noActivePurchase
}

enum ProSubscriptionError: LocalizedError {
    case productUnavailable
    case paymentsNotAllowed
    case purchasePending
    case purchaseUnverified
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return AppLocalization.text(.proProductUnavailable)
        case .paymentsNotAllowed:
            return AppLocalization.text(.proPurchaseNotAllowed)
        case .purchasePending:
            return AppLocalization.text(.proPurchasePending)
        case .purchaseUnverified:
            return AppLocalization.text(.proPurchaseUnverified)
        case .purchaseFailed:
            return AppLocalization.text(.proPurchaseFailed)
        }
    }
}

@MainActor
final class ProSubscriptionManager {
    static let shared = ProSubscriptionManager()
    static let didChangeNotification = Notification.Name("studio.pj.PTrack.proSubscriptionDidChange")

    private enum Strategy {
        static let proProductID = "movinn.pro"
        static let productIDs: Set<String> = [proProductID]
    }

    var isProUser: Bool {
        #if DEBUG
        if let debugProAccessOverride {
            return debugProAccessOverride
        }
        #endif
        return storeKitIsProUser
    }

    private var storeKitIsProUser = false
    private(set) var hasResolvedEntitlements = false

    var displayPrice: String? {
        product?.displayPrice
    }

    #if DEBUG
    var debugProAccessOverrideValue: Bool? {
        debugProAccessOverride
    }
    #endif

    private var product: Product?
    private var productLoadTask: Task<Product, Error>?
    private var purchaseTask: Task<ProSubscriptionPurchaseResult, Error>?
    private var restoreTask: Task<ProSubscriptionRestoreResult, Error>?
    private var transactionUpdatesTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?
    #if DEBUG
    private var debugProAccessOverride: Bool?
    #endif

    private init() {
        #if DEBUG
        debugProAccessOverride = Self.loadDebugProAccessOverride()
        #endif

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAccess()
            }
        }

        Task { [weak self] in
            await self?.prepare()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    func prepare() async {
        await refreshAccess()
        do {
            _ = try await loadConfiguredProduct()
        } catch {
            print("PTrack StoreKit: failed to prepare Pro subscription: \(error)")
        }
    }

    func ensureAccessResolved() async {
        guard !hasResolvedEntitlements else {
            return
        }

        await refreshAccess()
    }

    @discardableResult
    func refreshAccess() async -> Bool {
        var hasActiveProEntitlement = false
        let referenceDate = Date()
        let hadResolvedEntitlements = hasResolvedEntitlements

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.isActiveProTransaction(transaction, referenceDate: referenceDate) else {
                continue
            }

            hasActiveProEntitlement = true
            break
        }

        hasResolvedEntitlements = true
        updateProState(hasActiveProEntitlement, shouldNotify: !hadResolvedEntitlements)
        return isProUser
    }

    @discardableResult
    func purchase() async throws -> ProSubscriptionPurchaseResult {
        if let purchaseTask {
            return try await purchaseTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw ProSubscriptionError.purchaseFailed
            }

            if isProUser {
                return ProSubscriptionPurchaseResult.alreadyActive
            }

            guard AppStore.canMakePayments else {
                throw ProSubscriptionError.paymentsNotAllowed
            }

            let product = try await loadConfiguredProduct()
            let purchaseResult = try await product.purchase()

            switch purchaseResult {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                guard Self.isConfiguredProductID(transaction.productID) else {
                    await transaction.finish()
                    throw ProSubscriptionError.purchaseFailed
                }

                await transaction.finish()
                await refreshAccess()
                guard isProUser else {
                    throw ProSubscriptionError.purchaseFailed
                }

                return ProSubscriptionPurchaseResult.purchased
            case .userCancelled:
                return ProSubscriptionPurchaseResult.cancelled
            case .pending:
                await refreshAccess()
                return ProSubscriptionPurchaseResult.pending
            @unknown default:
                throw ProSubscriptionError.purchaseFailed
            }
        }
        purchaseTask = task

        do {
            let result = try await task.value
            purchaseTask = nil
            return result
        } catch {
            purchaseTask = nil
            throw error
        }
    }

    @discardableResult
    func restore() async throws -> ProSubscriptionRestoreResult {
        if let restoreTask {
            return try await restoreTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                throw ProSubscriptionError.purchaseFailed
            }

            try await AppStore.sync()
            let isActive = await refreshAccess()
            return isActive
                ? ProSubscriptionRestoreResult.restored
                : ProSubscriptionRestoreResult.noActivePurchase
        }
        restoreTask = task

        do {
            let result = try await task.value
            restoreTask = nil
            return result
        } catch {
            restoreTask = nil
            throw error
        }
    }

    private func loadConfiguredProduct() async throws -> Product {
        if let product {
            return product
        }

        if let productLoadTask {
            return try await productLoadTask.value
        }

        let task = Task<Product, Error> {
            let products = try await Product.products(for: Array(Strategy.productIDs))
            guard let product = products.first(where: { $0.id == Strategy.proProductID }) else {
                throw ProSubscriptionError.productUnavailable
            }

            return product
        }
        productLoadTask = task

        do {
            let loadedProduct = try await task.value
            product = loadedProduct
            productLoadTask = nil
            postChangeNotification()
            return loadedProduct
        } catch {
            productLoadTask = nil
            throw error
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard Self.isConfiguredProductID(transaction.productID) else {
                return
            }

            await transaction.finish()
            await refreshAccess()
        case .unverified:
            await refreshAccess()
        }
    }

    private func verifiedTransaction(
        from result: VerificationResult<StoreKit.Transaction>
    ) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw ProSubscriptionError.purchaseUnverified
        }
    }

    private static func isConfiguredProductID(_ productID: String) -> Bool {
        Strategy.productIDs.contains(productID)
    }

    private static func isActiveProTransaction(
        _ transaction: StoreKit.Transaction,
        referenceDate: Date
    ) -> Bool {
        guard transaction.productID == Strategy.proProductID,
              transaction.revocationDate == nil,
              !transaction.isUpgraded else {
            return false
        }

        if let expirationDate = transaction.expirationDate, expirationDate <= referenceDate {
            return false
        }

        return true
    }

    private func updateProState(_ isProUser: Bool, shouldNotify: Bool = false) {
        let previousEffectiveProState = self.isProUser
        guard storeKitIsProUser != isProUser else {
            if shouldNotify || previousEffectiveProState != self.isProUser {
                postChangeNotification()
            }
            return
        }

        storeKitIsProUser = isProUser
        if shouldNotify || previousEffectiveProState != self.isProUser {
            postChangeNotification()
        }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

#if DEBUG
extension ProSubscriptionManager {
    private enum DebugDefaults {
        static let proAccessOverrideKey = "studio.pj.PTrack.debug.proAccessOverride"
    }

    func setDebugProAccessOverride(_ isProUser: Bool) {
        debugProAccessOverride = isProUser
        hasResolvedEntitlements = true
        UserDefaults.standard.set(isProUser, forKey: DebugDefaults.proAccessOverrideKey)
        postChangeNotification()
    }

    private static func loadDebugProAccessOverride() -> Bool? {
        guard UserDefaults.standard.object(forKey: DebugDefaults.proAccessOverrideKey) != nil else {
            return nil
        }

        return UserDefaults.standard.bool(forKey: DebugDefaults.proAccessOverrideKey)
    }
}
#endif
