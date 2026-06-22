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

        var photoCount: Int {
            switch self {
            case .twoVertical, .twoHorizontal, .twoDiagonal:
                return 2
            case .threeVertical, .threeHorizontal, .threeDiagonal:
                return 3
            case .fourGrid, .fourVertical, .fourHorizontal:
                return 4
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
    private var imageRequestIDs: [PHImageRequestID] = []
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
    private var isEditingChromeHidden = false
    private let cropSelectionLayer = CAShapeLayer()
    private let dividerLayer = CAShapeLayer()
    private weak var dividerPanGesture: UIPanGestureRecognizer?
    private weak var cropDoubleTapGesture: UITapGestureRecognizer?
    private weak var cropCancelTapGesture: UITapGestureRecognizer?
    private weak var cropPanGesture: UIPanGestureRecognizer?
    private weak var cropPinchGesture: UIPinchGestureRecognizer?
    private weak var cropRotationGesture: UIRotationGestureRecognizer?
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
        let clampedItems = Array(items.prefix(4))
        let itemIDs = clampedItems.map(\.id)
        let needsImageReload = itemIDs != representedItemIDs
        let slotCount = max(layout.kind.photoCount, clampedItems.count)

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
            clearTileImages()
            requestImages()
        }

        updateLayoutPaths()
    }

    func clear() {
        cancelImageRequests()
        stopLivePhotoPlayback()
        items = []
        representedItemIDs = []
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
        isEditingChromeHidden = hidden
        cropSelectionLayer.isHidden = hidden
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
        activeCropIndex = nil
        updateCropSelectionPath()
    }

    func resetCropAdjustments() {
        activeCropIndex = nil
        cropAdjustments.removeAll()
        tileImageViews.indices.forEach { index in
            applyCropTransform(at: index)
        }
        updateCropSelectionPath()
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
        validPlaybacks.enumerated().forEach { index, playback in
            let tileIndex = playback.tileIndex
            let livePhotoView = livePhotoView(for: tileIndex)
            let freezeImageView = livePhotoFreezeImageView(for: tileIndex)

            activeLivePhotoItemIDs[tileIndex] = playback.representedID
            freezeImageView.image = playback.freezeImage
            freezeImageView.isHidden = true
            livePhotoView.stopPlayback()
            livePhotoView.livePhoto = playback.livePhoto
            livePhotoView.isMuted = index > 0
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
        backgroundColor = .white
        clipsToBounds = true

        cropSelectionLayer.fillColor = UIColor.clear.cgColor
        cropSelectionLayer.strokeColor = AppColors.movinnGreen.cgColor
        cropSelectionLayer.lineWidth = 2
        cropSelectionLayer.lineDashPattern = [6, 4]
        layer.addSublayer(cropSelectionLayer)

        dividerLayer.fillColor = UIColor.clear.cgColor
        dividerLayer.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
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

        let cropPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleCropPinch(_:)))
        cropPinchGesture.delegate = self
        addGestureRecognizer(cropPinchGesture)
        self.cropPinchGesture = cropPinchGesture

        let cropRotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleCropRotation(_:)))
        cropRotationGesture.delegate = self
        addGestureRecognizer(cropRotationGesture)
        self.cropRotationGesture = cropRotationGesture
    }

    private func ensureTileViews(count: Int) {
        while tileContainerViews.count < count {
            let containerView = UIView()
            containerView.clipsToBounds = true
            containerView.backgroundColor = .white

            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = false
            imageView.backgroundColor = .white

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
        let targetLength = max(bounds.width, bounds.height, 720) * scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetLength, height: targetLength),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self,
                  representedItemIDs.indices.contains(index),
                  representedItemIDs[index] == representedID,
                  tileImageViews.indices.contains(index) else {
                return
            }

            tileImageViews[index].image = image
            updateImageFrame(at: index)
            applyCropTransform(at: index)
        }
        imageRequestIDs.append(requestID)
    }

    private func cancelImageRequests() {
        imageRequestIDs.forEach { requestID in
            PHImageManager.default().cancelImageRequest(requestID)
        }
        imageRequestIDs.removeAll()
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
        updateDividerHandleFrames()

        CATransaction.commit()
    }

    private func updateCropSelectionPath(paths: [UIBezierPath]? = nil) {
        guard let activeCropIndex,
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
        dividerLayer.removeFromSuperlayer()
        layer.addSublayer(dividerLayer)
        dividerHandleViews.forEach(bringSubviewToFront)
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
        iconView.tintColor = .black
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
        case .twoVertical, .twoHorizontal, .twoDiagonal, .threeVertical, .threeHorizontal, .threeDiagonal, .fourVertical, .fourHorizontal:
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
        case .twoVertical, .threeVertical, .fourVertical:
            return CGPoint(x: bounds.minX + bounds.width * divider, y: bounds.midY)
        case .twoHorizontal, .threeHorizontal, .fourHorizontal:
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
            case .twoVertical, .threeVertical, .fourVertical:
                distance = abs(point.x - bounds.minX - bounds.width * divider)
            case .twoHorizontal, .threeHorizontal, .fourHorizontal:
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
        case .twoVertical, .threeVertical, .fourVertical:
            proposedDivider = (location.x - bounds.minX) / max(bounds.width, 1)
        case .twoHorizontal, .threeHorizontal, .fourHorizontal:
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
