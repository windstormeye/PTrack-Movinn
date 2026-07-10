//
//  RouteShareCollageView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import Photos
import PhotosUI
import SnapKit
import UIKit

struct RouteShareCollageLivePhotoPlayback {
    let livePhoto: PHLivePhoto
    let tileIndex: Int
    let representedID: String
    let duration: TimeInterval
    let freezeImage: UIImage?
}

struct RouteShareCollageTileRenderInfo {
    let tileFrame: CGRect
    let tilePath: UIBezierPath
    let cropScale: CGFloat
    let cropRotation: CGFloat
    let cropTranslation: CGPoint
}

struct RouteShareCollageLayout: Equatable {
    static let maximumPhotoCount = 9

    enum Kind: String {
        case twoVertical
        case twoHorizontal
        case twoDiagonal
        case threeVertical
        case threeHorizontal
        case threeDiagonal
        case fourGrid
        case fourVertical
        case fourHorizontal
        case fiveHeroTop
        case fiveHeroLeft
        case fiveRows
        case sixPortraitGrid
        case sixLandscapeGrid
        case sixCascade
        case sevenHeroTop
        case sevenHeroLeft
        case sevenBalanced
        case eightPortraitGrid
        case eightLandscapeGrid
        case eightBalanced
        case nineGrid
        case nineHeroTop
        case nineHeroLeft

        var photoCount: Int {
            switch self {
            case .twoVertical, .twoHorizontal, .twoDiagonal:
                return 2
            case .threeVertical, .threeHorizontal, .threeDiagonal:
                return 3
            case .fourGrid, .fourVertical, .fourHorizontal:
                return 4
            case .fiveHeroTop, .fiveHeroLeft, .fiveRows:
                return 5
            case .sixPortraitGrid, .sixLandscapeGrid, .sixCascade:
                return 6
            case .sevenHeroTop, .sevenHeroLeft, .sevenBalanced:
                return 7
            case .eightPortraitGrid, .eightLandscapeGrid, .eightBalanced:
                return 8
            case .nineGrid, .nineHeroTop, .nineHeroLeft:
                return 9
            }
        }
    }

    let kind: Kind
    var dividers: [CGFloat]

    static func library(for photoCount: Int) -> [RouteShareCollageLayout] {
        switch photoCount {
        case 2:
            return [
                RouteShareCollageLayout(kind: .twoVertical, dividers: [0.5]),
                RouteShareCollageLayout(kind: .twoHorizontal, dividers: [0.5]),
                RouteShareCollageLayout(kind: .twoDiagonal, dividers: [0.5])
            ]
        case 3:
            return [
                RouteShareCollageLayout(kind: .threeVertical, dividers: [1.0 / 3.0, 2.0 / 3.0]),
                RouteShareCollageLayout(kind: .threeHorizontal, dividers: [1.0 / 3.0, 2.0 / 3.0]),
                RouteShareCollageLayout(kind: .threeDiagonal, dividers: [0.25, 0.75])
            ]
        case 4:
            return [
                RouteShareCollageLayout(kind: .fourGrid, dividers: [0.5, 0.5]),
                RouteShareCollageLayout(kind: .fourVertical, dividers: [0.25, 0.5, 0.75]),
                RouteShareCollageLayout(kind: .fourHorizontal, dividers: [0.25, 0.5, 0.75])
            ]
        case 5:
            return [
                RouteShareCollageLayout(kind: .fiveHeroTop, dividers: [0.42, 0.71]),
                RouteShareCollageLayout(kind: .fiveHeroLeft, dividers: [0.44, 0.72]),
                RouteShareCollageLayout(kind: .fiveRows, dividers: [0.5])
            ]
        case 6:
            return [
                RouteShareCollageLayout(kind: .sixPortraitGrid, dividers: [1.0 / 3.0, 2.0 / 3.0]),
                RouteShareCollageLayout(kind: .sixLandscapeGrid, dividers: [0.5]),
                RouteShareCollageLayout(kind: .sixCascade, dividers: [0.38, 0.68])
            ]
        case 7:
            return [
                RouteShareCollageLayout(kind: .sevenHeroTop, dividers: [0.4, 0.7]),
                RouteShareCollageLayout(kind: .sevenHeroLeft, dividers: [0.44, 0.72]),
                RouteShareCollageLayout(kind: .sevenBalanced, dividers: [0.3, 0.7])
            ]
        case 8:
            return [
                RouteShareCollageLayout(kind: .eightPortraitGrid, dividers: [0.25, 0.5, 0.75]),
                RouteShareCollageLayout(kind: .eightLandscapeGrid, dividers: [0.5]),
                RouteShareCollageLayout(kind: .eightBalanced, dividers: [0.34, 0.67])
            ]
        case 9:
            return [
                RouteShareCollageLayout(kind: .nineGrid, dividers: [1.0 / 3.0, 2.0 / 3.0]),
                RouteShareCollageLayout(kind: .nineHeroTop, dividers: [0.42, 0.71]),
                RouteShareCollageLayout(kind: .nineHeroLeft, dividers: [0.42, 0.71])
            ]
        default:
            return []
        }
    }

    func matches(photoCount: Int) -> Bool {
        kind.photoCount == photoCount
    }
}

final class RouteShareCollageView: UIView, UIGestureRecognizerDelegate {
    var onLayoutChanged: ((RouteShareCollageLayout) -> Void)?
    var onTileSwap: ((_ sourceIndex: Int, _ destinationIndex: Int) -> Void)?
    var onCanvasTap: (() -> Void)?
    var onCropInteraction: (() -> Void)?

    private struct CropAdjustment {
        var scale: CGFloat = 1
        var rotation: CGFloat = 0
        var translation: CGPoint = .zero
    }

    private var layout = RouteShareCollageLayout(kind: .twoVertical, dividers: [0.5])
    private var items: [RouteSharePhotoItem] = []
    private var representedItemIDs: [String] = []
    private var imageRequestIDs: [Int: PHImageRequestID] = [:]
    private var imageRequestTokens: [Int: UUID] = [:]
    private var imageRetryCounts: [String: Int] = [:]
    private var tileContainerViews: [UIView] = []
    private var tileImageViews: [UIImageView] = []
    private var tileMaskLayers: [CAShapeLayer] = []
    private var dividerHandleViews: [UIView] = []
    private var livePhotoViews: [Int: PHLivePhotoView] = [:]
    private var livePhotoFreezeImageViews: [Int: UIImageView] = [:]
    private var livePhotoPlaybackWorkItems: [DispatchWorkItem] = []
    private var activeLivePhotoItemIDs: [Int: String] = [:]
    private var savedLivePhotoPlaybackHiddenStates: [(UIView, Bool)]?
    private var cropAdjustments: [String: CropAdjustment] = [:]
    private var activeDividerIndex: Int?
    private var activeCropIndex: Int?
    private var cropPanStartTranslation: CGPoint = .zero
    private var cropPinchStartScale: CGFloat = 1
    private var cropRotationStart: CGFloat = 0
    private var tileReorderSourceIndex: Int?
    private var tileReorderTargetIndex: Int?
    private var tileReorderTouchOffset: CGPoint = .zero
    private var tileReorderSnapshotView: UIView?
    private var isEditingChromeHidden = false
    private var canvasColor: UIColor = .white
    private let cropSelectionLayer = CAShapeLayer()
    private let tileReorderTargetLayer = CAShapeLayer()
    private let dividerLayer = CAShapeLayer()
    private let tileReorderImpactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let tileReorderSelectionFeedback = UISelectionFeedbackGenerator()
    private weak var dividerPanGesture: UIPanGestureRecognizer?
    private weak var cropDoubleTapGesture: UITapGestureRecognizer?
    private weak var cropCancelTapGesture: UITapGestureRecognizer?
    private weak var cropPanGesture: UIPanGestureRecognizer?
    private weak var cropPinchGesture: UIPinchGestureRecognizer?
    private weak var cropRotationGesture: UIRotationGestureRecognizer?
    private weak var tileReorderLongPressGesture: UILongPressGestureRecognizer?
    private var isDividerInteractionEnabled = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    deinit {
        cancelImageRequests()
        stopLivePhotoPlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayoutPaths()
    }

    func configure(items: [RouteSharePhotoItem], layout: RouteShareCollageLayout) {
        let clampedItems = Array(items.prefix(RouteShareCollageLayout.maximumPhotoCount))
        let itemIDs = clampedItems.map(\.id)
        let needsImageReload = itemIDs != representedItemIDs
        let slotCount = max(layout.kind.photoCount, clampedItems.count)
        var reusableImagesByItemID: [String: UIImage] = [:]
        if needsImageReload {
            for (index, itemID) in representedItemIDs.enumerated()
                where tileImageViews.indices.contains(index) {
                if let image = tileImageViews[index].image {
                    reusableImagesByItemID[itemID] = image
                }
            }
        }

        if needsImageReload {
            resetTileReorderState()
        }

        self.layout = layout
        self.items = clampedItems
        cropAdjustments = cropAdjustments.filter { itemIDs.contains($0.key) }
        if let activeCropIndex, !clampedItems.indices.contains(activeCropIndex) {
            self.activeCropIndex = nil
        }
        ensureTileViews(count: slotCount)

        if needsImageReload {
            stopLivePhotoPlayback()
            cancelImageRequests()
            representedItemIDs = itemIDs
            imageRetryCounts.removeAll()
            clearTileImages()
            for (index, itemID) in itemIDs.enumerated()
                where tileImageViews.indices.contains(index) {
                tileImageViews[index].image = reusableImagesByItemID[itemID]
            }
            requestImages()
        } else {
            requestMissingImages()
        }

        updateLayoutPaths()
    }

    func clear() {
        resetTileReorderState()
        cancelImageRequests()
        stopLivePhotoPlayback()
        items = []
        representedItemIDs = []
        imageRetryCounts.removeAll()
        activeCropIndex = nil
        cropAdjustments.removeAll()
        clearTileImages()
        tileContainerViews.forEach { $0.isHidden = true }
        cropSelectionLayer.path = nil
        dividerLayer.path = nil
        updateDividerHandles(count: 0)
    }

    func containsAdjustableDivider(at point: CGPoint) -> Bool {
        nearestDividerIndex(to: point, maximumDistance: 28) != nil
    }

    func containsAdjustableTile(at point: CGPoint) -> Bool {
        tileIndex(at: point) != nil
    }

    func setCropSelectionChromeHidden(_ hidden: Bool) {
        if hidden {
            resetTileReorderState()
        }
        isEditingChromeHidden = hidden
        cropSelectionLayer.isHidden = hidden
        tileReorderTargetLayer.isHidden = hidden || tileReorderTargetIndex == nil
        updateDividerHandleFrames()
    }

    func setDividerInteractionEnabled(_ enabled: Bool) {
        isDividerInteractionEnabled = enabled
        dividerPanGesture?.isEnabled = enabled
        if !enabled {
            activeDividerIndex = nil
        }
    }

    var hasActiveCropSelection: Bool {
        activeCropIndex != nil
    }

    var activeCropSelectionIndex: Int? {
        activeCropIndex
    }

    func clearCropSelection() {
        resetTileReorderState()
        activeCropIndex = nil
        updateCropSelectionPath()
    }

    func resetCropAdjustments() {
        resetTileReorderState()
        activeCropIndex = nil
        cropAdjustments.removeAll()
        tileImageViews.indices.forEach { index in
            applyCropTransform(at: index)
        }
        updateCropSelectionPath()
    }

    func setCanvasColor(_ color: UIColor) {
        canvasColor = color
        backgroundColor = color
        tileContainerViews.forEach { $0.backgroundColor = color }
        tileImageViews.forEach { $0.backgroundColor = color }
        updateDividerColor()
    }

    func playLivePhotos(
        _ playbacks: [RouteShareCollageLivePhotoPlayback],
        playbackDuration: TimeInterval
    ) {
        stopLivePhotoPlayback()

        let validPlaybacks = playbacks.filter { playback in
            items.indices.contains(playback.tileIndex)
                && tileContainerViews.indices.contains(playback.tileIndex)
                && representedItemIDs.indices.contains(playback.tileIndex)
                && representedItemIDs[playback.tileIndex] == playback.representedID
        }
        guard !validPlaybacks.isEmpty else {
            return
        }

        let resolvedDuration = max(
            playbackDuration,
            validPlaybacks.map(\.duration).max() ?? 0,
            0.1
        )
        validPlaybacks.forEach { playback in
            let tileIndex = playback.tileIndex
            let livePhotoView = livePhotoView(for: tileIndex)
            let freezeImageView = livePhotoFreezeImageView(for: tileIndex)

            activeLivePhotoItemIDs[tileIndex] = playback.representedID
            freezeImageView.image = playback.freezeImage
            freezeImageView.isHidden = true
            livePhotoView.stopPlayback()
            livePhotoView.livePhoto = playback.livePhoto
            livePhotoView.isMuted = false
            livePhotoView.isHidden = false
            updateLivePhotoOverlayFramesIfNeeded(at: tileIndex)
            tileContainerViews[tileIndex].bringSubviewToFront(livePhotoView)
            livePhotoView.startPlayback(with: .full)

            let freezeDelay = min(max(playback.duration, 0.1), resolvedDuration)
            let workItem = DispatchWorkItem { [weak self] in
                self?.freezeLivePhoto(at: tileIndex, representedID: playback.representedID)
            }
            livePhotoPlaybackWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + freezeDelay, execute: workItem)
        }
    }

    func stopLivePhotoPlayback() {
        livePhotoPlaybackWorkItems.forEach { $0.cancel() }
        livePhotoPlaybackWorkItems.removeAll()
        savedLivePhotoPlaybackHiddenStates = nil
        livePhotoViews.values.forEach { livePhotoView in
            livePhotoView.stopPlayback()
            livePhotoView.livePhoto = nil
            livePhotoView.isHidden = true
            livePhotoView.removeFromSuperview()
        }
        livePhotoViews.removeAll()
        livePhotoFreezeImageViews.values.forEach { imageView in
            imageView.image = nil
            imageView.isHidden = true
            imageView.removeFromSuperview()
        }
        livePhotoFreezeImageViews.removeAll()
        activeLivePhotoItemIDs.removeAll()
    }

    func renderInfoForTile(at index: Int) -> RouteShareCollageTileRenderInfo? {
        layoutIfNeeded()
        guard items.indices.contains(index),
              tileContainerViews.indices.contains(index),
              !tileContainerViews[index].isHidden else {
            return nil
        }

        let paths = tilePaths(in: bounds)
        guard paths.indices.contains(index),
              let tilePath = paths[index].copy() as? UIBezierPath else {
            return nil
        }
        let adjustment = clampedCropAdjustment(cropAdjustment(at: index))
        return RouteShareCollageTileRenderInfo(
            tileFrame: tileContainerViews[index].frame,
            tilePath: tilePath,
            cropScale: adjustment.scale,
            cropRotation: adjustment.rotation,
            cropTranslation: adjustment.translation
        )
    }

    func isTileHiddenForRendering(at index: Int) -> Bool {
        guard tileContainerViews.indices.contains(index) else {
            return true
        }
        return tileContainerViews[index].isHidden
    }

    func setTileHiddenForRendering(at index: Int, hidden: Bool) {
        guard tileContainerViews.indices.contains(index) else {
            return
        }
        tileContainerViews[index].isHidden = hidden
    }

    var isLivePhotoPlaybackHiddenForRendering: Bool {
        livePhotoViews.values.allSatisfy(\.isHidden)
            && livePhotoFreezeImageViews.values.allSatisfy(\.isHidden)
    }

    func setLivePhotoPlaybackHiddenForRendering(_ hidden: Bool) {
        let playbackViews = Array(livePhotoViews.values) + Array(livePhotoFreezeImageViews.values)
        if hidden {
            savedLivePhotoPlaybackHiddenStates = playbackViews.map { ($0, $0.isHidden) }
            playbackViews.forEach { $0.isHidden = true }
            return
        }

        if let savedLivePhotoPlaybackHiddenStates {
            savedLivePhotoPlaybackHiddenStates.forEach { view, wasHidden in
                view.isHidden = wasHidden
            }
            self.savedLivePhotoPlaybackHiddenStates = nil
        } else {
            playbackViews.forEach { $0.isHidden = false }
        }
    }

    private func configureViews() {
        backgroundColor = canvasColor
        clipsToBounds = true

        cropSelectionLayer.fillColor = UIColor.clear.cgColor
        cropSelectionLayer.strokeColor = AppColors.movinnGreen.cgColor
        cropSelectionLayer.lineWidth = 2
        cropSelectionLayer.lineDashPattern = [6, 4]
        layer.addSublayer(cropSelectionLayer)

        tileReorderTargetLayer.fillColor = AppColors.movinnGreen.withAlphaComponent(0.14).cgColor
        tileReorderTargetLayer.strokeColor = AppColors.movinnGreen.cgColor
        tileReorderTargetLayer.lineWidth = 3
        tileReorderTargetLayer.isHidden = true
        layer.addSublayer(tileReorderTargetLayer)

        dividerLayer.fillColor = UIColor.clear.cgColor
        updateDividerColor()
        dividerLayer.lineWidth = 1.5
        layer.addSublayer(dividerLayer)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        dividerPanGesture = panGesture

        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCropDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.cancelsTouchesInView = false
        doubleTapGesture.delegate = self
        addGestureRecognizer(doubleTapGesture)
        cropDoubleTapGesture = doubleTapGesture

        let cancelTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCropCancelTap(_:)))
        cancelTapGesture.cancelsTouchesInView = false
        cancelTapGesture.delegate = self
        cancelTapGesture.require(toFail: doubleTapGesture)
        addGestureRecognizer(cancelTapGesture)
        cropCancelTapGesture = cancelTapGesture

        let cropPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleCropPan(_:)))
        cropPanGesture.delegate = self
        addGestureRecognizer(cropPanGesture)
        self.cropPanGesture = cropPanGesture

        let tileReorderLongPressGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleTileReorderLongPress(_:))
        )
        tileReorderLongPressGesture.minimumPressDuration = 0.32
        tileReorderLongPressGesture.allowableMovement = 12
        tileReorderLongPressGesture.delegate = self
        addGestureRecognizer(tileReorderLongPressGesture)
        self.tileReorderLongPressGesture = tileReorderLongPressGesture
        cropPanGesture.require(toFail: tileReorderLongPressGesture)

        let cropPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleCropPinch(_:)))
        cropPinchGesture.delegate = self
        addGestureRecognizer(cropPinchGesture)
        self.cropPinchGesture = cropPinchGesture

        let cropRotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleCropRotation(_:)))
        cropRotationGesture.delegate = self
        addGestureRecognizer(cropRotationGesture)
        self.cropRotationGesture = cropRotationGesture

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.updateDividerColor()
        }
    }

    private func updateDividerColor() {
        dividerLayer.strokeColor = canvasColor
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.92)
            .cgColor
    }

    private func ensureTileViews(count: Int) {
        while tileContainerViews.count < count {
            let containerView = UIView()
            containerView.clipsToBounds = true
            containerView.backgroundColor = canvasColor

            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = false
            imageView.backgroundColor = canvasColor

            let maskLayer = CAShapeLayer()
            containerView.layer.mask = maskLayer

            containerView.addSubview(imageView)
            addSubview(containerView)
            tileContainerViews.append(containerView)
            tileImageViews.append(imageView)
            tileMaskLayers.append(maskLayer)
        }

        for index in tileContainerViews.indices {
            tileContainerViews[index].isHidden = index >= count
            tileImageViews[index].isHidden = index >= count
        }
        bringDividerChromeToFront()
    }

    private func clearTileImages() {
        tileImageViews.forEach { $0.image = nil }
    }

    private func requestImages() {
        for (index, item) in items.enumerated() {
            guard tileImageViews.indices.contains(index) else {
                continue
            }

            switch item {
            case .uploaded(let image):
                tileImageViews[index].image = image
                updateImageFrame(at: index)
                applyCropTransform(at: index)
            case .routeMedia(let mediaItem):
                requestImage(for: mediaItem.asset, at: index, representedID: item.id)
            }
        }
    }

    private func requestMissingImages() {
        for (index, item) in items.enumerated() {
            guard tileImageViews.indices.contains(index),
                  tileImageViews[index].image == nil,
                  imageRequestTokens[index] == nil else {
                continue
            }

            switch item {
            case .uploaded(let image):
                tileImageViews[index].image = image
                updateImageFrame(at: index)
                applyCropTransform(at: index)
            case .routeMedia(let mediaItem):
                requestImage(for: mediaItem.asset, at: index, representedID: item.id)
            }
        }
    }

    private func requestImage(for asset: PHAsset, at index: Int, representedID: String) {
        let scale = max(UIScreen.main.scale, 2)
        let paths = tilePaths(in: bounds)
        let tileSize = paths.indices.contains(index) ? paths[index].bounds.size : bounds.size
        let minimumTargetLength: CGFloat = 320
        let maximumTargetLength: CGFloat = 2_048
        let targetSize = CGSize(
            width: min(max(tileSize.width * scale, minimumTargetLength), maximumTargetLength),
            height: min(max(tileSize.height * scale, minimumTargetLength), maximumTargetLength)
        )
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let requestToken = UUID()
        imageRequestTokens[index] = requestToken
        let requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                self?.handleImageResult(
                    image,
                    info: info,
                    asset: asset,
                    index: index,
                    representedID: representedID,
                    requestToken: requestToken
                )
            }
        }
        if imageRequestTokens[index] == requestToken {
            imageRequestIDs[index] = requestID
        }
    }

    private func handleImageResult(
        _ image: UIImage?,
        info: [AnyHashable: Any]?,
        asset: PHAsset,
        index: Int,
        representedID: String,
        requestToken: UUID
    ) {
        guard imageRequestTokens[index] == requestToken,
              representedItemIDs.indices.contains(index),
              representedItemIDs[index] == representedID,
              tileImageViews.indices.contains(index) else {
            return
        }

        let wasCancelled = (info?[PHImageCancelledKey] as? Bool) == true
        if wasCancelled {
            finishImageRequest(at: index, requestToken: requestToken)
            if tileImageViews[index].image == nil {
                scheduleImageRetry(for: asset, at: index, representedID: representedID)
            }
            return
        }

        if let image {
            tileImageViews[index].image = image
            updateImageFrame(at: index)
            applyCropTransform(at: index)
        }

        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
        let requestError = info?[PHImageErrorKey] as? Error
        guard requestError != nil || !isDegraded else {
            return
        }

        finishImageRequest(at: index, requestToken: requestToken)
        if image == nil, tileImageViews[index].image == nil {
            scheduleImageRetry(for: asset, at: index, representedID: representedID)
        }
    }

    private func finishImageRequest(at index: Int, requestToken: UUID) {
        guard imageRequestTokens[index] == requestToken else {
            return
        }
        imageRequestTokens.removeValue(forKey: index)
        imageRequestIDs.removeValue(forKey: index)
    }

    private func scheduleImageRetry(for asset: PHAsset, at index: Int, representedID: String) {
        let retryCount = imageRetryCounts[representedID, default: 0]
        guard retryCount < 2 else {
            return
        }
        imageRetryCounts[representedID] = retryCount + 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  representedItemIDs.indices.contains(index),
                  representedItemIDs[index] == representedID,
                  tileImageViews.indices.contains(index),
                  tileImageViews[index].image == nil,
                  imageRequestTokens[index] == nil else {
                return
            }
            requestImage(for: asset, at: index, representedID: representedID)
        }
    }

    private func cancelImageRequests() {
        let requestIDs = Array(imageRequestIDs.values)
        imageRequestTokens.removeAll()
        imageRequestIDs.removeAll()
        requestIDs.forEach { requestID in
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }

    private func updateLayoutPaths() {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let paths = tilePaths(in: bounds)
        for index in tileContainerViews.indices {
            guard index < paths.count else {
                tileContainerViews[index].isHidden = true
                tileImageViews[index].isHidden = true
                continue
            }

            let tilePath = paths[index]
            let tileFrame = tilePath.bounds
            let hasItem = items.indices.contains(index)
            tileContainerViews[index].isHidden = false
            tileContainerViews[index].frame = tileFrame
            tileImageViews[index].isHidden = !hasItem
            updateImageFrame(at: index)

            let maskPath = tilePath.copy() as? UIBezierPath ?? UIBezierPath()
            maskPath.apply(CGAffineTransform(translationX: -tileFrame.minX, y: -tileFrame.minY))
            tileMaskLayers[index].frame = CGRect(origin: .zero, size: tileFrame.size)
            tileMaskLayers[index].path = maskPath.cgPath
            if hasItem {
                applyCropTransform(at: index)
            } else {
                tileImageViews[index].transform = .identity
            }
        }

        let dividerPath = UIBezierPath()
        paths.forEach(dividerPath.append)
        dividerLayer.frame = bounds
        dividerLayer.path = dividerPath.cgPath
        updateCropSelectionPath(paths: paths)
        updateTileReorderTargetPath(paths: paths)
        updateDividerHandleFrames()

        CATransaction.commit()
    }

    private func updateCropSelectionPath(paths: [UIBezierPath]? = nil) {
        guard tileReorderSourceIndex == nil,
              let activeCropIndex,
              items.indices.contains(activeCropIndex) else {
            cropSelectionLayer.path = nil
            return
        }

        let resolvedPaths = paths ?? tilePaths(in: bounds)
        guard resolvedPaths.indices.contains(activeCropIndex) else {
            cropSelectionLayer.path = nil
            return
        }

        cropSelectionLayer.frame = bounds
        cropSelectionLayer.path = insetPathForSelection(resolvedPaths[activeCropIndex]).cgPath
    }

    private func insetPathForSelection(_ path: UIBezierPath) -> UIBezierPath {
        let pathBounds = path.bounds
        guard pathBounds.width > 4, pathBounds.height > 4 else {
            return path
        }

        let inset: CGFloat = 2.5
        let scaleX = max((pathBounds.width - inset * 2) / pathBounds.width, 0.01)
        let scaleY = max((pathBounds.height - inset * 2) / pathBounds.height, 0.01)
        let insetPath = path.copy() as? UIBezierPath ?? UIBezierPath()
        let transform = CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: scaleY,
            tx: pathBounds.midX * (1 - scaleX),
            ty: pathBounds.midY * (1 - scaleY)
        )
        insetPath.apply(transform)
        return insetPath
    }

    private func updateImageFrame(at index: Int) {
        guard tileImageViews.indices.contains(index),
              tileContainerViews.indices.contains(index) else {
            return
        }

        let tileSize = tileContainerViews[index].bounds.size
        guard tileSize.width > 0, tileSize.height > 0 else {
            return
        }

        let imageSize = tileImageViews[index].image?.size ?? tileSize
        let baseSize = aspectFillSize(for: imageSize, in: tileSize)
        tileImageViews[index].bounds = CGRect(origin: .zero, size: baseSize)
        tileImageViews[index].center = CGPoint(x: tileSize.width / 2, y: tileSize.height / 2)
        updateLivePhotoOverlayFramesIfNeeded(at: index)
    }

    private func cropAdjustment(at index: Int) -> CropAdjustment {
        guard items.indices.contains(index) else {
            return CropAdjustment()
        }
        return cropAdjustments[items[index].id] ?? CropAdjustment()
    }

    private func setCropAdjustment(_ adjustment: CropAdjustment, at index: Int) {
        guard items.indices.contains(index) else {
            return
        }
        cropAdjustments[items[index].id] = clampedCropAdjustment(adjustment)
        applyCropTransform(at: index)
    }

    private func applyCropTransform(at index: Int) {
        guard tileImageViews.indices.contains(index),
              tileContainerViews.indices.contains(index) else {
            return
        }

        let adjustment = clampedCropAdjustment(cropAdjustment(at: index))
        tileImageViews[index].transform = CGAffineTransform(
            translationX: adjustment.translation.x,
            y: adjustment.translation.y
        )
        .rotated(by: adjustment.rotation)
        .scaledBy(x: adjustment.scale, y: adjustment.scale)
        updateLivePhotoOverlayFramesIfNeeded(at: index)
    }

    private func livePhotoView(for index: Int) -> PHLivePhotoView {
        if let livePhotoView = livePhotoViews[index] {
            return livePhotoView
        }

        let livePhotoView = PHLivePhotoView()
        livePhotoView.contentMode = .scaleAspectFill
        livePhotoView.clipsToBounds = false
        livePhotoView.isMuted = false
        livePhotoView.isHidden = true
        livePhotoViews[index] = livePhotoView
        if tileContainerViews.indices.contains(index) {
            tileContainerViews[index].addSubview(livePhotoView)
        }
        return livePhotoView
    }

    private func livePhotoFreezeImageView(for index: Int) -> UIImageView {
        if let imageView = livePhotoFreezeImageViews[index] {
            return imageView
        }

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = false
        imageView.isHidden = true
        livePhotoFreezeImageViews[index] = imageView
        if tileContainerViews.indices.contains(index) {
            tileContainerViews[index].addSubview(imageView)
        }
        return imageView
    }

    private func updateLivePhotoOverlayFramesIfNeeded(at index: Int) {
        guard tileImageViews.indices.contains(index),
              tileContainerViews.indices.contains(index) else {
            return
        }

        [livePhotoViews[index], livePhotoFreezeImageViews[index]].forEach { overlayView in
            guard let overlayView,
                  overlayView.superview === tileContainerViews[index] else {
                return
            }

            overlayView.bounds = tileImageViews[index].bounds
            overlayView.center = tileImageViews[index].center
            overlayView.transform = tileImageViews[index].transform
        }
    }

    private func freezeLivePhoto(at index: Int, representedID: String) {
        guard activeLivePhotoItemIDs[index] == representedID else {
            return
        }

        livePhotoViews[index]?.stopPlayback()
        livePhotoViews[index]?.isHidden = true

        guard let freezeImageView = livePhotoFreezeImageViews[index],
              freezeImageView.image != nil else {
            return
        }

        freezeImageView.isHidden = false
        if tileContainerViews.indices.contains(index) {
            tileContainerViews[index].bringSubviewToFront(freezeImageView)
        }
    }

    private func clampedCropAdjustment(_ adjustment: CropAdjustment) -> CropAdjustment {
        var clamped = adjustment
        clamped.scale = min(max(clamped.scale, 1), 3)
        clamped.rotation = normalizedRotation(clamped.rotation)
        return clamped
    }

    private func aspectFillSize(for contentSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = max(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    private func normalizedRotation(_ rotation: CGFloat) -> CGFloat {
        let fullTurn = CGFloat.pi * 2
        let normalized = rotation.truncatingRemainder(dividingBy: fullTurn)
        if normalized > .pi {
            return normalized - fullTurn
        }
        if normalized < -.pi {
            return normalized + fullTurn
        }
        return normalized
    }

    private func bringDividerChromeToFront() {
        cropSelectionLayer.removeFromSuperlayer()
        if !isEditingChromeHidden {
            layer.addSublayer(cropSelectionLayer)
        }
        tileReorderTargetLayer.removeFromSuperlayer()
        if !isEditingChromeHidden {
            layer.addSublayer(tileReorderTargetLayer)
        }
        dividerLayer.removeFromSuperlayer()
        layer.addSublayer(dividerLayer)
        dividerHandleViews.forEach(bringSubviewToFront)
        if let tileReorderSnapshotView {
            bringSubviewToFront(tileReorderSnapshotView)
        }
    }

    private func updateDividerHandles(count: Int) {
        while dividerHandleViews.count < count {
            let handleView = makeDividerHandleView()
            addSubview(handleView)
            dividerHandleViews.append(handleView)
        }

        for (index, handleView) in dividerHandleViews.enumerated() {
            handleView.isHidden = isEditingChromeHidden || index >= count
        }
        bringDividerChromeToFront()
    }

    private func makeDividerHandleView() -> UIView {
        let handleView = UIView()
        handleView.backgroundColor = AppColors.movinnGreen
        handleView.layer.cornerRadius = 12
        handleView.layer.masksToBounds = true
        handleView.isUserInteractionEnabled = false

        let iconView = UIImageView()
        iconView.image = UIImage(
            systemName: "arrowshape.left.arrowshape.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        )
        iconView.tintColor = AppColors.solidForeground
        iconView.contentMode = .scaleAspectFit

        handleView.addSubview(iconView)
        iconView.snp.makeConstraints { make in 
            make.center.equalToSuperview()
            make.size.equalTo(15)
        }

        return handleView
    }

    private func updateDividerHandleFrames() {
        let centers = dividerHandleCenters()
        updateDividerHandles(count: centers.count)

        for (index, center) in centers.enumerated() {
            guard dividerHandleViews.indices.contains(index) else {
                continue
            }

            let size = CGSize(width: 36, height: 24)
            dividerHandleViews[index].bounds = CGRect(origin: .zero, size: size)
            dividerHandleViews[index].center = center
            dividerHandleViews[index].isHidden = isEditingChromeHidden
        }
    }

    private func adjustableDividers() -> [CGFloat] {
        layout.dividers
    }

    private func dividerHandleCenters() -> [CGPoint] {
        switch layout.kind {
        case .twoVertical, .twoHorizontal, .twoDiagonal,
             .threeVertical, .threeHorizontal, .threeDiagonal,
             .fourVertical, .fourHorizontal,
             .fiveHeroTop, .fiveHeroLeft, .fiveRows,
             .sixPortraitGrid, .sixLandscapeGrid, .sixCascade,
             .sevenHeroTop, .sevenHeroLeft, .sevenBalanced,
             .eightPortraitGrid, .eightLandscapeGrid, .eightBalanced,
             .nineGrid, .nineHeroTop, .nineHeroLeft:
            return adjustableDividers().compactMap(dividerHandleCenter)
        case .fourGrid:
            let xDivider = layout.dividers.first ?? 0.5
            let yDivider = layout.dividers.dropFirst().first ?? 0.5
            return [
                CGPoint(
                    x: bounds.minX + bounds.width * xDivider,
                    y: bounds.minY + bounds.height * yDivider
                )
            ]
        }
    }

    private func dividerHandleCenter(for divider: CGFloat) -> CGPoint? {
        switch layout.kind {
        case .twoVertical, .threeVertical, .fourVertical,
             .fiveHeroLeft, .sevenHeroLeft, .nineHeroLeft:
            return CGPoint(x: bounds.minX + bounds.width * divider, y: bounds.midY)
        case .twoHorizontal, .threeHorizontal, .fourHorizontal,
             .fiveHeroTop, .fiveRows,
             .sixPortraitGrid, .sixLandscapeGrid, .sixCascade,
             .sevenHeroTop, .sevenBalanced,
             .eightPortraitGrid, .eightLandscapeGrid, .eightBalanced,
             .nineGrid, .nineHeroTop:
            return CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * divider)
        case .twoDiagonal, .threeDiagonal:
            return diagonalSegment(in: bounds, constant: diagonalConstant(for: divider)).map { segment in
                CGPoint(
                    x: (segment.start.x + segment.end.x) / 2,
                    y: (segment.start.y + segment.end.y) / 2
                )
            }
        case .fourGrid:
            return nil
        }
    }

    private func tilePaths(in rect: CGRect) -> [UIBezierPath] {
        switch layout.kind {
        case .twoVertical:
            return verticalPaths(in: rect, dividers: layout.dividers)
        case .twoHorizontal:
            return horizontalPaths(in: rect, dividers: layout.dividers)
        case .twoDiagonal:
            return diagonalPaths(in: rect, dividers: layout.dividers)
        case .threeVertical:
            return verticalPaths(in: rect, dividers: layout.dividers)
        case .threeHorizontal:
            return horizontalPaths(in: rect, dividers: layout.dividers)
        case .threeDiagonal:
            return diagonalPaths(in: rect, dividers: layout.dividers)
        case .fourGrid:
            return gridFourPaths(in: rect, dividers: layout.dividers)
        case .fourVertical:
            return verticalPaths(in: rect, dividers: layout.dividers)
        case .fourHorizontal:
            return horizontalPaths(in: rect, dividers: layout.dividers)
        case .fiveHeroTop:
            return rowGroupPaths(in: rect, itemCounts: [1, 2, 2], dividers: layout.dividers)
        case .fiveHeroLeft:
            return columnGroupPaths(in: rect, itemCounts: [1, 2, 2], dividers: layout.dividers)
        case .fiveRows:
            return rowGroupPaths(in: rect, itemCounts: [2, 3], dividers: layout.dividers)
        case .sixPortraitGrid:
            return rowGroupPaths(in: rect, itemCounts: [2, 2, 2], dividers: layout.dividers)
        case .sixLandscapeGrid:
            return rowGroupPaths(in: rect, itemCounts: [3, 3], dividers: layout.dividers)
        case .sixCascade:
            return rowGroupPaths(in: rect, itemCounts: [1, 2, 3], dividers: layout.dividers)
        case .sevenHeroTop:
            return rowGroupPaths(in: rect, itemCounts: [1, 3, 3], dividers: layout.dividers)
        case .sevenHeroLeft:
            return columnGroupPaths(in: rect, itemCounts: [1, 3, 3], dividers: layout.dividers)
        case .sevenBalanced:
            return rowGroupPaths(in: rect, itemCounts: [2, 3, 2], dividers: layout.dividers)
        case .eightPortraitGrid:
            return rowGroupPaths(in: rect, itemCounts: [2, 2, 2, 2], dividers: layout.dividers)
        case .eightLandscapeGrid:
            return rowGroupPaths(in: rect, itemCounts: [4, 4], dividers: layout.dividers)
        case .eightBalanced:
            return rowGroupPaths(in: rect, itemCounts: [3, 2, 3], dividers: layout.dividers)
        case .nineGrid:
            return rowGroupPaths(in: rect, itemCounts: [3, 3, 3], dividers: layout.dividers)
        case .nineHeroTop:
            return rowGroupPaths(in: rect, itemCounts: [1, 4, 4], dividers: layout.dividers)
        case .nineHeroLeft:
            return columnGroupPaths(in: rect, itemCounts: [1, 4, 4], dividers: layout.dividers)
        }
    }

    private func verticalPaths(in rect: CGRect, dividers: [CGFloat]) -> [UIBezierPath] {
        let edges = ([0] + sortedDividers(dividers) + [1]).map { rect.minX + rect.width * $0 }
        return (0..<(edges.count - 1)).map { index in
            UIBezierPath(rect: CGRect(
                x: edges[index],
                y: rect.minY,
                width: edges[index + 1] - edges[index],
                height: rect.height
            ))
        }
    }

    private func horizontalPaths(in rect: CGRect, dividers: [CGFloat]) -> [UIBezierPath] {
        let edges = ([0] + sortedDividers(dividers) + [1]).map { rect.minY + rect.height * $0 }
        return (0..<(edges.count - 1)).map { index in
            UIBezierPath(rect: CGRect(
                x: rect.minX,
                y: edges[index],
                width: rect.width,
                height: edges[index + 1] - edges[index]
            ))
        }
    }

    private func rowGroupPaths(
        in rect: CGRect,
        itemCounts: [Int],
        dividers: [CGFloat]
    ) -> [UIBezierPath] {
        let rowEdges = sectionEdges(count: itemCounts.count, dividers: dividers).map {
            rect.minY + rect.height * $0
        }
        var paths: [UIBezierPath] = []

        for (rowIndex, itemCount) in itemCounts.enumerated() where itemCount > 0 {
            let itemWidth = rect.width / CGFloat(itemCount)
            for itemIndex in 0..<itemCount {
                paths.append(UIBezierPath(rect: CGRect(
                    x: rect.minX + CGFloat(itemIndex) * itemWidth,
                    y: rowEdges[rowIndex],
                    width: itemWidth,
                    height: rowEdges[rowIndex + 1] - rowEdges[rowIndex]
                )))
            }
        }

        return paths
    }

    private func columnGroupPaths(
        in rect: CGRect,
        itemCounts: [Int],
        dividers: [CGFloat]
    ) -> [UIBezierPath] {
        let columnEdges = sectionEdges(count: itemCounts.count, dividers: dividers).map {
            rect.minX + rect.width * $0
        }
        var paths: [UIBezierPath] = []

        for (columnIndex, itemCount) in itemCounts.enumerated() where itemCount > 0 {
            let itemHeight = rect.height / CGFloat(itemCount)
            for itemIndex in 0..<itemCount {
                paths.append(UIBezierPath(rect: CGRect(
                    x: columnEdges[columnIndex],
                    y: rect.minY + CGFloat(itemIndex) * itemHeight,
                    width: columnEdges[columnIndex + 1] - columnEdges[columnIndex],
                    height: itemHeight
                )))
            }
        }

        return paths
    }

    private func sectionEdges(count: Int, dividers: [CGFloat]) -> [CGFloat] {
        guard count > 1 else {
            return [0, 1]
        }

        let resolvedDividers: [CGFloat]
        if dividers.count == count - 1 {
            resolvedDividers = sortedDividers(dividers)
        } else {
            resolvedDividers = (1..<count).map { CGFloat($0) / CGFloat(count) }
        }
        return [0] + resolvedDividers + [1]
    }

    private func gridFourPaths(in rect: CGRect, dividers: [CGFloat]) -> [UIBezierPath] {
        let xDivider = min(max(dividers.first ?? 0.5, 0.18), 0.82)
        let yDivider = min(max(dividers.dropFirst().first ?? 0.5, 0.18), 0.82)
        let splitX = rect.minX + rect.width * xDivider
        let splitY = rect.minY + rect.height * yDivider
        return [
            UIBezierPath(rect: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: splitX - rect.minX,
                height: splitY - rect.minY
            )),
            UIBezierPath(rect: CGRect(
                x: rect.minX,
                y: splitY,
                width: splitX - rect.minX,
                height: rect.maxY - splitY
            )),
            UIBezierPath(rect: CGRect(
                x: splitX,
                y: rect.minY,
                width: rect.maxX - splitX,
                height: splitY - rect.minY
            )),
            UIBezierPath(rect: CGRect(
                x: splitX,
                y: splitY,
                width: rect.maxX - splitX,
                height: rect.maxY - splitY
            ))
        ]
    }

    private func diagonalPaths(in rect: CGRect, dividers: [CGFloat]) -> [UIBezierPath] {
        let polygon = rectPolygon(rect)
        let constants = sortedDividers(dividers).map(diagonalConstant)

        switch constants.count {
        case 1:
            return [
                bezierPath(from: clipPolygon(polygon, in: rect, constant: constants[0], keepsLowerSide: true)),
                bezierPath(from: clipPolygon(polygon, in: rect, constant: constants[0], keepsLowerSide: false))
            ]
        case 2:
            let lower = clipPolygon(polygon, in: rect, constant: constants[0], keepsLowerSide: true)
            let middleUpper = clipPolygon(polygon, in: rect, constant: constants[0], keepsLowerSide: false)
            let middle = clipPolygon(middleUpper, in: rect, constant: constants[1], keepsLowerSide: true)
            let upper = clipPolygon(polygon, in: rect, constant: constants[1], keepsLowerSide: false)
            return [bezierPath(from: lower), bezierPath(from: middle), bezierPath(from: upper)]
        default:
            return [UIBezierPath(rect: rect)]
        }
    }

    private func sortedDividers(_ dividers: [CGFloat]) -> [CGFloat] {
        dividers.map { min(max($0, 0), 1) }.sorted()
    }

    private func rectPolygon(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    private func bezierPath(from points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: firstPoint)
        points.dropFirst().forEach(path.addLine)
        path.close()
        return path
    }

    private func clipPolygon(
        _ polygon: [CGPoint],
        in rect: CGRect,
        constant: CGFloat,
        keepsLowerSide: Bool
    ) -> [CGPoint] {
        guard polygon.count > 1 else {
            return polygon
        }

        var output: [CGPoint] = []
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[index == polygon.startIndex ? polygon.index(before: polygon.endIndex) : polygon.index(before: index)]
            let currentInside = isPoint(current, in: rect, insideConstant: constant, keepsLowerSide: keepsLowerSide)
            let previousInside = isPoint(previous, in: rect, insideConstant: constant, keepsLowerSide: keepsLowerSide)

            if currentInside {
                if !previousInside {
                    output.append(diagonalIntersection(from: previous, to: current, in: rect, constant: constant))
                }
                output.append(current)
            } else if previousInside {
                output.append(diagonalIntersection(from: previous, to: current, in: rect, constant: constant))
            }
        }

        return output
    }

    private func isPoint(_ point: CGPoint, in rect: CGRect, insideConstant constant: CGFloat, keepsLowerSide: Bool) -> Bool {
        let value = diagonalValue(for: point, in: rect)
        return keepsLowerSide ? value <= constant : value >= constant
    }

    private func diagonalIntersection(from start: CGPoint, to end: CGPoint, in rect: CGRect, constant: CGFloat) -> CGPoint {
        let startValue = diagonalValue(for: start, in: rect)
        let endValue = diagonalValue(for: end, in: rect)
        let denominator = endValue - startValue
        guard abs(denominator) > CGFloat.ulpOfOne else {
            return start
        }

        let progress = (constant - startValue) / denominator
        return CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private func diagonalSegment(in rect: CGRect, constant: CGFloat) -> (start: CGPoint, end: CGPoint)? {
        let polygon = rectPolygon(rect)
        var points: [CGPoint] = []

        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[index == polygon.index(before: polygon.endIndex) ? polygon.startIndex : polygon.index(after: index)]
            let startValue = diagonalValue(for: start, in: rect)
            let endValue = diagonalValue(for: end, in: rect)

            if abs(startValue - constant) < 0.0001 {
                points.append(start)
            }

            if (startValue - constant) * (endValue - constant) < 0 {
                points.append(diagonalIntersection(from: start, to: end, in: rect, constant: constant))
            }
        }

        guard points.count >= 2 else {
            return nil
        }

        return (points[0], points[1])
    }

    private func diagonalValue(for point: CGPoint, in rect: CGRect) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else {
            return 0
        }

        return ((point.x - rect.minX) / rect.width) - ((point.y - rect.minY) / rect.height)
    }

    private func diagonalConstant(for divider: CGFloat) -> CGFloat {
        (divider - 0.5) * 1.6
    }

    private func divider(forDiagonalConstant constant: CGFloat) -> CGFloat {
        constant / 1.6 + 0.5
    }

    private func nearestDividerIndex(to point: CGPoint, maximumDistance: CGFloat) -> Int? {
        let adjustableDividers = adjustableDividers()
        guard !adjustableDividers.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let distances: [(Int, CGFloat)] = adjustableDividers.enumerated().map { index, divider in
            let distance: CGFloat
            switch layout.kind {
            case .twoVertical, .threeVertical, .fourVertical,
                 .fiveHeroLeft, .sevenHeroLeft, .nineHeroLeft:
                distance = abs(point.x - bounds.minX - bounds.width * divider)
            case .twoHorizontal, .threeHorizontal, .fourHorizontal,
                 .fiveHeroTop, .fiveRows,
                 .sixPortraitGrid, .sixLandscapeGrid, .sixCascade,
                 .sevenHeroTop, .sevenBalanced,
                 .eightPortraitGrid, .eightLandscapeGrid, .eightBalanced,
                 .nineGrid, .nineHeroTop:
                distance = abs(point.y - bounds.minY - bounds.height * divider)
            case .twoDiagonal, .threeDiagonal:
                let constant = diagonalConstant(for: divider)
                let gradientLength = sqrt((1 / bounds.width) * (1 / bounds.width) + (1 / bounds.height) * (1 / bounds.height))
                distance = abs(diagonalValue(for: point, in: bounds) - constant) / gradientLength
            case .fourGrid:
                let xDivider = layout.dividers.first ?? 0.5
                let yDivider = layout.dividers.dropFirst().first ?? 0.5
                let center = CGPoint(
                    x: bounds.minX + bounds.width * xDivider,
                    y: bounds.minY + bounds.height * yDivider
                )
                distance = hypot(point.x - center.x, point.y - center.y)
            }
            return (index, distance)
        }

        return distances.min(by: { $0.1 < $1.1 }).flatMap { nearest in
            nearest.1 <= maximumDistance ? nearest.0 : nil
        }
    }

    private func dividerHandleIndex(at point: CGPoint, hitSlop: CGFloat = 10) -> Int? {
        dividerHandleViews.enumerated().first { _, handleView in
            !handleView.isHidden
                && handleView.frame.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point)
        }?.offset
    }

    private func tileIndex(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else {
            return nil
        }

        let paths = tilePaths(in: bounds)
        return paths.indices.reversed().first { index in
            items.indices.contains(index) && paths[index].contains(point)
        }
    }

    private func beginTileReorder(at location: CGPoint) {
        guard tileReorderSourceIndex == nil,
              let activeCropIndex,
              tileIndex(at: location) == activeCropIndex,
              tileContainerViews.indices.contains(activeCropIndex),
              let snapshotView = tileContainerViews[activeCropIndex].snapshotView(afterScreenUpdates: false) else {
            return
        }

        let sourceFrame = tileContainerViews[activeCropIndex].frame
        tileReorderSourceIndex = activeCropIndex
        tileReorderTargetIndex = nil
        tileReorderTouchOffset = CGPoint(
            x: location.x - sourceFrame.midX,
            y: location.y - sourceFrame.midY
        )
        tileReorderSnapshotView = snapshotView

        snapshotView.frame = sourceFrame
        snapshotView.isUserInteractionEnabled = false
        snapshotView.layer.shadowColor = UIColor.black.cgColor
        snapshotView.layer.shadowOpacity = 0.28
        snapshotView.layer.shadowRadius = 10
        snapshotView.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(snapshotView)
        tileContainerViews[activeCropIndex].alpha = 0.22
        cropSelectionLayer.path = nil
        updateTileReorderTargetPath()
        bringSubviewToFront(snapshotView)

        tileReorderImpactFeedback.prepare()
        tileReorderSelectionFeedback.prepare()
        tileReorderImpactFeedback.impactOccurred()
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            snapshotView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        }
        onCropInteraction?()
    }

    private func updateTileReorder(at location: CGPoint) {
        guard let sourceIndex = tileReorderSourceIndex,
              let snapshotView = tileReorderSnapshotView else {
            return
        }

        snapshotView.center = CGPoint(
            x: location.x - tileReorderTouchOffset.x,
            y: location.y - tileReorderTouchOffset.y
        )
        let hoveredIndex = tileIndex(at: location)
        let targetIndex = hoveredIndex == sourceIndex ? nil : hoveredIndex
        if targetIndex != tileReorderTargetIndex {
            tileReorderTargetIndex = targetIndex
            updateTileReorderTargetPath()
            if targetIndex != nil {
                tileReorderSelectionFeedback.selectionChanged()
                tileReorderSelectionFeedback.prepare()
            }
        }
        bringSubviewToFront(snapshotView)
    }

    private func finishTileReorder(cancelled: Bool) {
        guard let sourceIndex = tileReorderSourceIndex else {
            resetTileReorderState()
            return
        }

        let destinationIndex = cancelled ? nil : tileReorderTargetIndex
        let paths = tilePaths(in: bounds)
        let destinationFrame = destinationIndex.flatMap { index in
            paths.indices.contains(index) ? paths[index].bounds : nil
        }
        guard let snapshotView = tileReorderSnapshotView else {
            completeTileReorder(from: sourceIndex, to: destinationIndex)
            return
        }

        let sourceFrame = paths.indices.contains(sourceIndex)
            ? paths[sourceIndex].bounds
            : tileContainerViews[sourceIndex].frame
        let targetFrame = destinationFrame ?? sourceFrame
        let scaleX = targetFrame.width / max(snapshotView.bounds.width, 1)
        let scaleY = targetFrame.height / max(snapshotView.bounds.height, 1)

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            snapshotView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            snapshotView.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            snapshotView.alpha = destinationIndex == nil ? 1 : 0.72
        } completion: { [weak self] _ in
            guard let self, tileReorderSourceIndex == sourceIndex else {
                return
            }
            completeTileReorder(from: sourceIndex, to: destinationIndex)
        }
    }

    private func completeTileReorder(from sourceIndex: Int, to destinationIndex: Int?) {
        resetTileReorderState()
        guard let destinationIndex,
              sourceIndex != destinationIndex,
              items.indices.contains(sourceIndex),
              items.indices.contains(destinationIndex) else {
            updateCropSelectionPath()
            return
        }

        activeCropIndex = destinationIndex
        onTileSwap?(sourceIndex, destinationIndex)
        updateCropSelectionPath()
        tileReorderImpactFeedback.impactOccurred(intensity: 0.82)
    }

    private func resetTileReorderState() {
        tileReorderSnapshotView?.layer.removeAllAnimations()
        tileReorderSnapshotView?.removeFromSuperview()
        tileReorderSnapshotView = nil
        tileContainerViews.forEach { $0.alpha = 1 }
        tileReorderSourceIndex = nil
        tileReorderTargetIndex = nil
        tileReorderTouchOffset = .zero
        tileReorderTargetLayer.path = nil
        tileReorderTargetLayer.isHidden = true
    }

    private func updateTileReorderTargetPath(paths: [UIBezierPath]? = nil) {
        guard !isEditingChromeHidden,
              let tileReorderTargetIndex else {
            tileReorderTargetLayer.path = nil
            tileReorderTargetLayer.isHidden = true
            return
        }

        let resolvedPaths = paths ?? tilePaths(in: bounds)
        guard resolvedPaths.indices.contains(tileReorderTargetIndex) else {
            tileReorderTargetLayer.path = nil
            tileReorderTargetLayer.isHidden = true
            return
        }

        tileReorderTargetLayer.frame = bounds
        tileReorderTargetLayer.path = insetPathForSelection(
            resolvedPaths[tileReorderTargetIndex]
        ).cgPath
        tileReorderTargetLayer.isHidden = false
        bringDividerChromeToFront()
    }

    @objc private func handleTileReorderLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            beginTileReorder(at: location)
        case .changed:
            updateTileReorder(at: location)
        case .ended:
            finishTileReorder(cancelled: false)
        case .cancelled, .failed:
            finishTileReorder(cancelled: true)
        default:
            break
        }
    }

    @objc private func handleCropDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else {
            return
        }

        let location = recognizer.location(in: self)
        guard dividerHandleIndex(at: location) == nil,
              let selectedIndex = tileIndex(at: location) else {
            return
        }

        activeCropIndex = selectedIndex
        updateCropSelectionPath()
        onCropInteraction?()
    }

    @objc private func handleCropCancelTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .recognized else {
            return
        }

        let location = recognizer.location(in: self)
        guard dividerHandleIndex(at: location) == nil else {
            return
        }

        let tappedIndex = tileIndex(at: location)
        guard activeCropIndex == nil || tappedIndex != nil else {
            clearCropSelection()
            onCanvasTap?()
            return
        }

        clearCropSelection()
        onCanvasTap?()
    }

    @objc private func handleCropPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let activeCropIndex else {
                return
            }
            onCropInteraction?()
            cropPanStartTranslation = cropAdjustment(at: activeCropIndex).translation
        case .changed:
            guard let activeCropIndex else {
                return
            }
            let translation = recognizer.translation(in: self)
            var adjustment = cropAdjustment(at: activeCropIndex)
            adjustment.translation = CGPoint(
                x: cropPanStartTranslation.x + translation.x,
                y: cropPanStartTranslation.y + translation.y
            )
            setCropAdjustment(adjustment, at: activeCropIndex)
        case .ended, .cancelled, .failed:
            cropPanStartTranslation = .zero
        default:
            break
        }
    }

    @objc private func handleCropPinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let activeCropIndex else {
                return
            }
            onCropInteraction?()
            cropPinchStartScale = cropAdjustment(at: activeCropIndex).scale
        case .changed:
            guard let activeCropIndex else {
                return
            }
            var adjustment = cropAdjustment(at: activeCropIndex)
            adjustment.scale = cropPinchStartScale * recognizer.scale
            setCropAdjustment(adjustment, at: activeCropIndex)
        case .ended, .cancelled, .failed:
            cropPinchStartScale = 1
        default:
            break
        }
    }

    @objc private func handleCropRotation(_ recognizer: UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let activeCropIndex else {
                return
            }
            onCropInteraction?()
            cropRotationStart = cropAdjustment(at: activeCropIndex).rotation
        case .changed:
            guard let activeCropIndex else {
                return
            }
            var adjustment = cropAdjustment(at: activeCropIndex)
            adjustment.rotation = cropRotationStart + recognizer.rotation
            setCropAdjustment(adjustment, at: activeCropIndex)
        case .ended, .cancelled, .failed:
            cropRotationStart = 0
        default:
            break
        }
    }

    @objc private func handleDividerPan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began:
            activeDividerIndex = dividerHandleIndex(at: location)
                ?? nearestDividerIndex(to: location, maximumDistance: 32)
            fallthrough
        case .changed:
            guard let activeDividerIndex else {
                return
            }

            layout.dividers = updatedDividers(moving: activeDividerIndex, to: location)
            updateLayoutPaths()
            onLayoutChanged?(layout)
        case .ended, .cancelled, .failed:
            activeDividerIndex = nil
        default:
            break
        }
    }

    private func updatedDividers(moving index: Int, to location: CGPoint) -> [CGFloat] {
        var dividers = layout.dividers
        guard dividers.indices.contains(index) else {
            return dividers
        }

        let proposedDivider: CGFloat
        switch layout.kind {
        case .twoVertical, .threeVertical, .fourVertical,
             .fiveHeroLeft, .sevenHeroLeft, .nineHeroLeft:
            proposedDivider = (location.x - bounds.minX) / max(bounds.width, 1)
        case .twoHorizontal, .threeHorizontal, .fourHorizontal,
             .fiveHeroTop, .fiveRows,
             .sixPortraitGrid, .sixLandscapeGrid, .sixCascade,
             .sevenHeroTop, .sevenBalanced,
             .eightPortraitGrid, .eightLandscapeGrid, .eightBalanced,
             .nineGrid, .nineHeroTop:
            proposedDivider = (location.y - bounds.minY) / max(bounds.height, 1)
        case .twoDiagonal, .threeDiagonal:
            proposedDivider = divider(forDiagonalConstant: diagonalValue(for: location, in: bounds))
        case .fourGrid:
            if dividers.count >= 2 {
                dividers[0] = min(max((location.x - bounds.minX) / max(bounds.width, 1), 0.18), 0.82)
                dividers[1] = min(max((location.y - bounds.minY) / max(bounds.height, 1), 0.18), 0.82)
            }
            return dividers
        }

        if dividers.count == 1 {
            dividers[index] = min(max(proposedDivider, 0.18), 0.82)
            return dividers
        }

        let minimumGap: CGFloat = dividers.count >= 3 ? 0.08 : 0.16
        let edgeInset: CGFloat = dividers.count >= 3 ? 0.08 : 0.12
        let lowerBound = index == 0 ? edgeInset : dividers[index - 1] + minimumGap
        let upperBound = index == dividers.count - 1 ? 1 - edgeInset : dividers[index + 1] - minimumGap
        dividers[index] = min(max(proposedDivider, lowerBound), upperBound)
        return dividers
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: self)

        if gestureRecognizer === dividerPanGesture {
            guard isDividerInteractionEnabled,
                  activeCropIndex == nil else {
                activeDividerIndex = nil
                return false
            }

            let touchedHandleIndex = dividerHandleIndex(at: location)
            activeDividerIndex = touchedHandleIndex
                ?? nearestDividerIndex(to: location, maximumDistance: 32)
            return activeDividerIndex != nil
        }

        if gestureRecognizer === cropDoubleTapGesture {
            return dividerHandleIndex(at: location) == nil
                && tileIndex(at: location) != nil
        }

        if gestureRecognizer === cropCancelTapGesture {
            return dividerHandleIndex(at: location) == nil
                && tileIndex(at: location) != nil
        }

        if gestureRecognizer === cropPanGesture {
            guard let activeCropIndex else {
                return false
            }
            return dividerHandleIndex(at: location) == nil
                && tileIndex(at: location) == activeCropIndex
        }

        if gestureRecognizer === tileReorderLongPressGesture {
            guard tileReorderSourceIndex == nil,
                  let activeCropIndex else {
                return false
            }
            return dividerHandleIndex(at: location) == nil
                && tileIndex(at: location) == activeCropIndex
        }

        if gestureRecognizer === cropPinchGesture {
            guard let activeCropIndex else {
                return false
            }
            return tileIndex(at: location) == activeCropIndex
        }

        if gestureRecognizer === cropRotationGesture {
            guard let activeCropIndex else {
                return false
            }
            return tileIndex(at: location) == activeCropIndex
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let gestureIsCrop = gestureRecognizer === cropPanGesture
            || gestureRecognizer === cropPinchGesture
            || gestureRecognizer === cropRotationGesture
        let otherGestureIsCrop = otherGestureRecognizer === cropPanGesture
            || otherGestureRecognizer === cropPinchGesture
            || otherGestureRecognizer === cropRotationGesture
        return gestureIsCrop && otherGestureIsCrop
    }
}
