//
//  RouteMediaBrowserCell.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import AVFoundation
import Photos
import PhotosUI
import SnapKit
import UIKit

protocol RouteMediaBrowserCellDelegate: AnyObject {
    func routeMediaBrowserCellDidRequestDismiss(_ cell: RouteMediaBrowserCell)
}

final class RouteMediaBrowserCell: UICollectionViewCell {
    static let reuseIdentifier = "RouteMediaBrowserCell"

    weak var delegate: RouteMediaBrowserCellDelegate?

    private let imageScrollView = UIScrollView()
    private let imageView = UIImageView()
    private let livePhotoView = PHLivePhotoView()
    private let liveBadgeView = UIView()
    private let liveBadgeImageView = UIImageView(image: UIImage(systemName: "livephoto"))
    private let liveBadgeLabel = UILabel()
    private let videoContainerView = UIView()
    private let videoStageView = UIView()
    private let videoControlsView = UIView()
    private let playButton = UIButton(type: .system)
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let cloudLoadingStackView = UIStackView()
    private let cloudLoadingIndicator = UIActivityIndicatorView(style: .large)
    private let cloudLoadingLabel = UILabel()
    private let imageManager = PHImageManager.default()

    private var representedAssetID: String?
    private var coverImageRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var livePhotoRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var videoRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerTimeObserver: Any?
    private var hidePlayButtonWorkItem: DispatchWorkItem?
    private var isSeekingVideo = false
    private var lastImageScrollSize: CGSize = .zero
    private var currentAssetPixelSize: CGSize = .zero
    private var mediaKind: MediaKind?
    private var hasResolvedPrimaryMedia = false

    private lazy var blankAreaTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleBlankAreaTap))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var imageDoubleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleImageDoubleTap(_:)))
        gesture.numberOfTapsRequired = 2
        gesture.delegate = self
        return gesture
    }()

    private lazy var imageSingleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleImageSingleTap))
        gesture.numberOfTapsRequired = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var livePhotoTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(playLivePhoto))
        gesture.delegate = self
        return gesture
    }()

    private lazy var videoTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(revealVideoPlaybackButton))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private enum MediaKind {
        case image
        case livePhoto
        case video
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    deinit {
        cancelRequests()
        removePlayerObservers()
        hidePlayButtonWorkItem?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequests()
        representedAssetID = nil
        currentAssetPixelSize = .zero
        mediaKind = nil
        hasResolvedPrimaryMedia = false
        imageView.image = nil
        resetImageZoom()
        livePhotoView.stopPlayback()
        livePhotoView.livePhoto = nil
        removePlayerObservers()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        progressSlider.value = 0
        currentTimeLabel.text = "0:00"
        durationLabel.text = "0:00"
        hidePlayButtonWorkItem?.cancel()
        hidePlayButtonWorkItem = nil
        playButton.isHidden = true
        playButton.alpha = 1
        videoControlsView.isHidden = true
        liveBadgeView.isHidden = true
        setCloudLoadingVisible(false)
    }

    func prepareForDismissal() {
        cancelRequests()
        representedAssetID = nil
        hasResolvedPrimaryMedia = false
        imageView.image = nil
        livePhotoView.stopPlayback()
        livePhotoView.livePhoto = nil
        removePlayerObservers()
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        hidePlayButtonWorkItem?.cancel()
        hidePlayButtonWorkItem = nil
        setCloudLoadingVisible(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = videoStageView.bounds
        updateImageLayoutIfNeeded()
    }

    func configure(with mediaItem: RouteMediaItem) {
        representedAssetID = mediaItem.id
        currentAssetPixelSize = CGSize(width: mediaItem.asset.pixelWidth, height: mediaItem.asset.pixelHeight)
        hasResolvedPrimaryMedia = false
        imageScrollView.isHidden = false
        livePhotoView.isHidden = true
        liveBadgeView.isHidden = true
        videoContainerView.isHidden = true
        videoControlsView.isHidden = true
        playButton.isHidden = true
        setCloudLoadingVisible(false)
        resetImageZoom()
        configureCoverImage(with: mediaItem.asset)

        if mediaItem.isVideo {
            mediaKind = .video
            setCloudLoadingVisible(true)
            configureVideo(with: mediaItem.asset)
        } else if mediaItem.isLivePhoto {
            mediaKind = .livePhoto
            setCloudLoadingVisible(true)
            configureLivePhoto(with: mediaItem.asset)
        } else {
            mediaKind = .image
            setCloudLoadingVisible(true)
            configureImage(with: mediaItem.asset)
        }
    }

    private func configureViews() {
        contentView.backgroundColor = .black

        imageScrollView.backgroundColor = .black
        imageScrollView.delegate = self
        imageScrollView.minimumZoomScale = 1
        imageScrollView.maximumZoomScale = 4
        imageScrollView.bouncesZoom = true
        imageScrollView.showsHorizontalScrollIndicator = false
        imageScrollView.showsVerticalScrollIndicator = false
        imageScrollView.contentInsetAdjustmentBehavior = .never
        imageScrollView.decelerationRate = .fast
        imageScrollView.isHidden = true

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.isMuted = false
        livePhotoView.isUserInteractionEnabled = true
        livePhotoView.isHidden = true
        videoContainerView.backgroundColor = .black
        videoContainerView.isHidden = true
        videoStageView.backgroundColor = .black

        liveBadgeView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        liveBadgeView.layer.cornerRadius = 15
        liveBadgeView.clipsToBounds = true
        liveBadgeView.isHidden = true
        liveBadgeImageView.tintColor = .white
        liveBadgeImageView.contentMode = .scaleAspectFit
        liveBadgeLabel.text = "LIVE"
        liveBadgeLabel.textColor = .white
        liveBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        videoControlsView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        videoControlsView.layer.cornerRadius = 18
        videoControlsView.clipsToBounds = true
        currentTimeLabel.text = "0:00"
        currentTimeLabel.textColor = .white
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        currentTimeLabel.textAlignment = .right
        durationLabel.text = "0:00"
        durationLabel.textColor = .white
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        durationLabel.textAlignment = .left
        videoControlsView.isHidden = true
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
        progressSlider.thumbTintColor = .white
        progressSlider.addTarget(self, action: #selector(beginSeekingVideo), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(updateVideoSeekPreview), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(finishSeekingVideo), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        playButton.setImage(
            UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 58)),
            for: .normal
        )
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        playButton.layer.cornerRadius = 37
        playButton.isHidden = true
        playButton.addTarget(self, action: #selector(toggleVideoPlayback), for: .touchUpInside)

        cloudLoadingStackView.axis = .vertical
        cloudLoadingStackView.alignment = .center
        cloudLoadingStackView.spacing = 10
        cloudLoadingStackView.isHidden = true
        cloudLoadingStackView.isUserInteractionEnabled = false
        cloudLoadingIndicator.color = .white
        cloudLoadingIndicator.hidesWhenStopped = true
        cloudLoadingLabel.text = "加载中"
        cloudLoadingLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        cloudLoadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        cloudLoadingLabel.textAlignment = .center
        cloudLoadingLabel.isUserInteractionEnabled = false

        imageSingleTapGesture.require(toFail: imageDoubleTapGesture)
        imageScrollView.addGestureRecognizer(imageSingleTapGesture)
        imageScrollView.addGestureRecognizer(imageDoubleTapGesture)
        livePhotoView.addGestureRecognizer(livePhotoTapGesture)
        videoContainerView.addGestureRecognizer(videoTapGesture)
        contentView.addGestureRecognizer(blankAreaTapGesture)

        imageScrollView.addSubview(imageView)
        contentView.addSubview(imageScrollView)
        contentView.addSubview(livePhotoView)
        contentView.addSubview(videoContainerView)
        videoContainerView.addSubview(videoStageView)
        videoContainerView.addSubview(videoControlsView)
        liveBadgeView.addSubview(liveBadgeImageView)
        liveBadgeView.addSubview(liveBadgeLabel)
        contentView.addSubview(liveBadgeView)
        contentView.addSubview(playButton)
        cloudLoadingStackView.addArrangedSubview(cloudLoadingIndicator)
        cloudLoadingStackView.addArrangedSubview(cloudLoadingLabel)
        contentView.addSubview(cloudLoadingStackView)
        videoControlsView.addSubview(currentTimeLabel)
        videoControlsView.addSubview(progressSlider)
        videoControlsView.addSubview(durationLabel)

        imageScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        livePhotoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        videoContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        videoStageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.lessThanOrEqualToSuperview()
            make.height.lessThanOrEqualToSuperview()
            make.height.equalToSuperview().priority(.high)
            make.width.equalTo(videoStageView.snp.height).multipliedBy(9.0 / 16.0)
        }

        videoControlsView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.bottom.equalTo(contentView.safeAreaLayoutGuide.snp.bottom).inset(24)
            make.height.equalTo(36)
        }

        currentTimeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(56)
        }

        durationLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(56)
        }

        progressSlider.snp.makeConstraints { make in
            make.leading.equalTo(currentTimeLabel.snp.trailing).offset(8)
            make.trailing.equalTo(durationLabel.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        liveBadgeView.snp.makeConstraints { make in
            make.top.equalTo(contentView.safeAreaLayoutGuide.snp.top).inset(16)
            make.trailing.equalToSuperview().inset(16)
            make.height.equalTo(30)
        }

        liveBadgeImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(16)
        }

        liveBadgeLabel.snp.makeConstraints { make in
            make.leading.equalTo(liveBadgeImageView.snp.trailing).offset(5)
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }

        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(74)
        }

        cloudLoadingStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func configureCoverImage(with asset: PHAsset) {
        if let cachedImage = RouteMediaThumbnailCache.image(for: asset.localIdentifier) {
            imageView.image = cachedImage
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        coverImageRequestID = imageManager.requestImage(
            for: asset,
            targetSize: coverTargetSize(),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self,
                      self.representedAssetID == asset.localIdentifier,
                      let image else {
                    return
                }

                RouteMediaThumbnailCache.store(image, for: asset.localIdentifier)

                if !self.hasResolvedPrimaryMedia {
                    self.imageView.image = image
                    self.updateImageLayoutIfNeeded()
                }
            }
        }
    }

    private func configureImage(with asset: PHAsset) {
        imageScrollView.isHidden = false
        updateImageLayoutIfNeeded()

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, error, _, _ in
            self?.handleCloudDownloadProgress(progress, error: error, for: asset)
        }

        imageRequestID = imageManager.requestImage(
            for: asset,
            targetSize: mediaTargetSize(),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            DispatchQueue.main.async {
                guard let self, self.representedAssetID == asset.localIdentifier else {
                    return
                }

                if let image {
                    self.hasResolvedPrimaryMedia = true
                    self.imageView.image = image
                }

                self.updateCloudLoadingAfterRequestResult(info: info, hasResolvedMedia: image != nil)
            }
        }
    }

    private func configureLivePhoto(with asset: PHAsset) {
        imageScrollView.isHidden = false
        livePhotoView.isHidden = true
        liveBadgeView.isHidden = false

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, error, _, _ in
            self?.handleCloudDownloadProgress(progress, error: error, for: asset)
        }

        livePhotoRequestID = imageManager.requestLivePhoto(
            for: asset,
            targetSize: mediaTargetSize(),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] livePhoto, info in
            DispatchQueue.main.async {
                guard let self, self.representedAssetID == asset.localIdentifier else {
                    return
                }

                if let livePhoto {
                    self.hasResolvedPrimaryMedia = true
                    self.livePhotoView.livePhoto = livePhoto
                    self.imageScrollView.isHidden = true
                    self.livePhotoView.isHidden = false
                }

                self.updateCloudLoadingAfterRequestResult(info: info, hasResolvedMedia: livePhoto != nil)
            }
        }
    }

    private func configureVideo(with asset: PHAsset) {
        imageScrollView.isHidden = false
        videoContainerView.isHidden = true
        videoControlsView.isHidden = true
        playButton.isHidden = true
        playButton.alpha = 1
        updatePlayButtonImage(isPlaying: false)

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, error, _, _ in
            self?.handleCloudDownloadProgress(progress, error: error, for: asset)
        }

        videoRequestID = imageManager.requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, info in
            DispatchQueue.main.async {
                guard let self, self.representedAssetID == asset.localIdentifier else {
                    return
                }

                self.updateCloudLoadingAfterRequestResult(info: info, hasResolvedMedia: avAsset != nil)

                guard let avAsset else {
                    return
                }

                self.hasResolvedPrimaryMedia = true
                self.imageScrollView.isHidden = true
                self.videoContainerView.isHidden = false
                self.videoControlsView.isHidden = false
                self.playButton.isHidden = false
                self.updateLayoutBeforeInstallingPlayerLayer()

                let playerItem = AVPlayerItem(asset: avAsset)
                let player = AVPlayer(playerItem: playerItem)
                let playerLayer = AVPlayerLayer(player: player)
                playerLayer.videoGravity = .resizeAspect
                playerLayer.frame = self.videoStageView.bounds

                self.removePlayerObservers()
                self.playerLayer?.removeFromSuperlayer()
                self.player = player
                self.playerLayer = playerLayer
                self.videoStageView.layer.insertSublayer(playerLayer, at: 0)
                self.installPlayerObservers(for: player, item: playerItem)
                self.updateVideoProgress(for: .zero)
                self.playButton.isHidden = false
                self.playButton.alpha = 1
                self.updatePlayButtonImage(isPlaying: false)
            }
        }
    }

    @objc private func toggleVideoPlayback() {
        guard let player else {
            return
        }

        if player.timeControlStatus == .playing {
            player.pause()
            hidePlayButtonWorkItem?.cancel()
            setPlayButtonVisible(true, animated: true)
            updatePlayButtonImage(isPlaying: false)
        } else {
            player.play()
            updatePlayButtonImage(isPlaying: true)
            setPlayButtonVisible(false, animated: true)
        }
    }

    @objc private func revealVideoPlaybackButton() {
        guard !videoContainerView.isHidden, let player else {
            return
        }

        if player.timeControlStatus == .playing {
            updatePlayButtonImage(isPlaying: true)
            setPlayButtonVisible(true, animated: true)
            schedulePlayButtonAutoHide()
        } else {
            updatePlayButtonImage(isPlaying: false)
            setPlayButtonVisible(true, animated: true)
        }
    }

    @objc private func beginSeekingVideo() {
        isSeekingVideo = true
        revealVideoPlaybackButton()
    }

    @objc private func updateVideoSeekPreview() {
        guard let player else {
            return
        }

        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration.isFinite, duration > 0 else {
            return
        }

        currentTimeLabel.text = formatTime(TimeInterval(progressSlider.value) * duration)
    }

    @objc private func finishSeekingVideo() {
        guard let player else {
            isSeekingVideo = false
            return
        }

        let duration = player.currentItem?.duration.seconds ?? 0
        guard duration.isFinite, duration > 0 else {
            isSeekingVideo = false
            return
        }

        let targetTime = CMTime(seconds: TimeInterval(progressSlider.value) * duration, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isSeekingVideo = false
                self?.updateVideoProgress(for: targetTime)
                if self?.player?.timeControlStatus == .playing {
                    self?.schedulePlayButtonAutoHide()
                }
            }
        }
    }

    @objc private func playLivePhoto() {
        guard !livePhotoView.isHidden, livePhotoView.livePhoto != nil else {
            return
        }

        livePhotoView.stopPlayback()
        livePhotoView.startPlayback(with: .full)
    }

    @objc private func handleImageDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !imageScrollView.isHidden else {
            return
        }

        if imageScrollView.zoomScale > imageScrollView.minimumZoomScale + 0.01 {
            imageScrollView.setZoomScale(imageScrollView.minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(imageScrollView.maximumZoomScale, 2.5)
        let point = gesture.location(in: imageView)
        let zoomSize = CGSize(
            width: imageScrollView.bounds.width / targetScale,
            height: imageScrollView.bounds.height / targetScale
        )
        let zoomRect = CGRect(
            x: point.x - zoomSize.width / 2,
            y: point.y - zoomSize.height / 2,
            width: zoomSize.width,
            height: zoomSize.height
        )
        imageScrollView.zoom(to: zoomRect, animated: true)
    }

    @objc private func handleImageSingleTap() {
        guard !imageScrollView.isHidden else {
            return
        }

        delegate?.routeMediaBrowserCellDidRequestDismiss(self)
    }

    @objc private func handleBlankAreaTap() {
        delegate?.routeMediaBrowserCellDidRequestDismiss(self)
    }

    private func installPlayerObservers(for player: AVPlayer, item: AVPlayerItem) {
        playerTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.updateVideoProgress(for: time)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(videoDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func removePlayerObservers() {
        if let playerTimeObserver, let player {
            player.removeTimeObserver(playerTimeObserver)
        }
        playerTimeObserver = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    @objc private func videoDidReachEnd() {
        player?.seek(to: .zero)
        player?.pause()
        updateVideoProgress(for: .zero)
        updatePlayButtonImage(isPlaying: false)
        setPlayButtonVisible(true, animated: true)
    }

    private func updateVideoProgress(for time: CMTime) {
        guard !isSeekingVideo else {
            return
        }

        let duration = player?.currentItem?.duration.seconds ?? 0
        let current = time.seconds
        guard duration.isFinite, duration > 0, current.isFinite else {
            progressSlider.value = 0
            currentTimeLabel.text = "0:00"
            durationLabel.text = "0:00"
            return
        }

        progressSlider.value = Float(min(max(current / duration, 0), 1))
        currentTimeLabel.text = formatTime(current)
        durationLabel.text = formatTime(duration)
    }

    private func updatePlayButtonImage(isPlaying: Bool) {
        let imageName = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playButton.setImage(
            UIImage(systemName: imageName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 58)),
            for: .normal
        )
    }

    private func setPlayButtonVisible(_ visible: Bool, animated: Bool) {
        hidePlayButtonWorkItem?.cancel()
        playButton.isHidden = false
        let updates = {
            self.playButton.alpha = visible ? 1 : 0
        }
        let completion: (Bool) -> Void = { _ in
            if !visible {
                self.playButton.isHidden = true
            }
        }

        if animated {
            UIView.animate(withDuration: 0.18, animations: updates, completion: completion)
        } else {
            updates()
            completion(true)
        }
    }

    private func schedulePlayButtonAutoHide() {
        hidePlayButtonWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.player?.timeControlStatus == .playing else {
                return
            }
            self?.setPlayButtonVisible(false, animated: true)
        }
        hidePlayButtonWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private func updateLayoutBeforeInstallingPlayerLayer() {
        contentView.layoutIfNeeded()
        videoContainerView.layoutIfNeeded()
        videoStageView.layoutIfNeeded()
    }

    private func handleCloudDownloadProgress(_ progress: Double, error: Error?, for asset: PHAsset) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.representedAssetID == asset.localIdentifier else {
                return
            }

            self.setCloudLoadingVisible(error == nil && progress < 1)
        }
    }

    private func updateCloudLoadingAfterRequestResult(info: [AnyHashable: Any]?, hasResolvedMedia: Bool) {
        if shouldShowCloudLoading(info: info, hasResolvedMedia: hasResolvedMedia) {
            setCloudLoadingVisible(true)
            return
        }

        if (hasResolvedMedia && !isDegradedResult(info)) || isFinalRequestResult(info) {
            setCloudLoadingVisible(false)
        }
    }

    private func shouldShowCloudLoading(info: [AnyHashable: Any]?, hasResolvedMedia: Bool) -> Bool {
        if isCancelledResult(info) || requestError(from: info) != nil {
            return false
        }

        guard isCloudResult(info) else {
            return false
        }

        return !hasResolvedMedia || isDegradedResult(info)
    }

    private func isFinalRequestResult(_ info: [AnyHashable: Any]?) -> Bool {
        if isCancelledResult(info) || requestError(from: info) != nil {
            return true
        }

        return !isDegradedResult(info)
    }

    private func isCloudResult(_ info: [AnyHashable: Any]?) -> Bool {
        infoBoolValue(info, for: PHImageResultIsInCloudKey)
    }

    private func isDegradedResult(_ info: [AnyHashable: Any]?) -> Bool {
        infoBoolValue(info, for: PHImageResultIsDegradedKey)
    }

    private func isCancelledResult(_ info: [AnyHashable: Any]?) -> Bool {
        infoBoolValue(info, for: PHImageCancelledKey)
    }

    private func requestError(from info: [AnyHashable: Any]?) -> Error? {
        info?[PHImageErrorKey] as? Error
    }

    private func infoBoolValue(_ info: [AnyHashable: Any]?, for key: String) -> Bool {
        if let value = info?[key] as? Bool {
            return value
        }

        if let value = info?[key] as? NSNumber {
            return value.boolValue
        }

        return false
    }

    private func setCloudLoadingVisible(_ isVisible: Bool) {
        cloudLoadingStackView.isHidden = !isVisible

        if isVisible {
            if mediaKind == .video {
                hidePlayButtonWorkItem?.cancel()
                playButton.isHidden = true
            }
            contentView.bringSubviewToFront(cloudLoadingStackView)
            cloudLoadingIndicator.startAnimating()
        } else {
            cloudLoadingIndicator.stopAnimating()
        }
    }

    private func resetImageZoom() {
        imageScrollView.setZoomScale(1, animated: false)
        imageScrollView.contentOffset = .zero
        imageView.transform = .identity
        lastImageScrollSize = .zero
        updateImageLayoutIfNeeded()
    }

    private func updateImageLayoutIfNeeded() {
        let size = imageScrollView.bounds.size
        guard size.width > 1, size.height > 1 else {
            return
        }

        if size != lastImageScrollSize {
            lastImageScrollSize = size
            imageScrollView.zoomScale = imageScrollView.minimumZoomScale
            imageScrollView.contentSize = size
            imageView.frame = CGRect(origin: .zero, size: size)
        }

        centerZoomedImageIfNeeded()
    }

    private func centerZoomedImageIfNeeded() {
        let boundsSize = imageScrollView.bounds.size
        var frame = imageView.frame

        frame.origin.x = frame.width < boundsSize.width ? (boundsSize.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < boundsSize.height ? (boundsSize.height - frame.height) / 2 : 0
        imageView.frame = frame
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func isBlackArea(at point: CGPoint) -> Bool {
        if !playButton.isHidden, playButton.frame.insetBy(dx: -12, dy: -12).contains(point) {
            return false
        }

        if !videoControlsView.isHidden {
            let controlsFrame = videoControlsView.convert(videoControlsView.bounds, to: contentView)
            if controlsFrame.insetBy(dx: -10, dy: -10).contains(point) {
                return false
            }
        }

        if !liveBadgeView.isHidden, liveBadgeView.frame.insetBy(dx: -10, dy: -10).contains(point) {
            return false
        }

        guard let contentRect = displayedMediaContentRect() else {
            return true
        }

        return !contentRect.insetBy(dx: -8, dy: -8).contains(point)
    }

    private func displayedMediaContentRect() -> CGRect? {
        switch mediaKind {
        case .image:
            return displayedImageContentRect()
        case .livePhoto:
            return displayedLivePhotoContentRect()
        case .video:
            return videoStageView.convert(videoStageView.bounds, to: contentView)
        case .none:
            return nil
        }
    }

    private func displayedImageContentRect() -> CGRect? {
        let contentSize = imageView.image?.size ?? currentAssetPixelSize
        guard let rect = aspectFitRect(for: contentSize, in: imageView.bounds) else {
            return nil
        }

        return imageView.convert(rect, to: contentView)
    }

    private func displayedLivePhotoContentRect() -> CGRect? {
        guard let rect = aspectFitRect(for: currentAssetPixelSize, in: livePhotoView.bounds) else {
            return nil
        }

        return livePhotoView.convert(rect, to: contentView)
    }

    private func aspectFitRect(for contentSize: CGSize, in bounds: CGRect) -> CGRect? {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let fittedSize = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func cancelRequests() {
        if coverImageRequestID != PHInvalidImageRequestID {
            imageManager.cancelImageRequest(coverImageRequestID)
            coverImageRequestID = PHInvalidImageRequestID
        }
        if imageRequestID != PHInvalidImageRequestID {
            imageManager.cancelImageRequest(imageRequestID)
            imageRequestID = PHInvalidImageRequestID
        }
        if livePhotoRequestID != PHInvalidImageRequestID {
            imageManager.cancelImageRequest(livePhotoRequestID)
            livePhotoRequestID = PHInvalidImageRequestID
        }
        if videoRequestID != PHInvalidImageRequestID {
            imageManager.cancelImageRequest(videoRequestID)
            videoRequestID = PHInvalidImageRequestID
        }
    }

    private func mediaTargetSize() -> CGSize {
        let scale = max(traitCollection.displayScale, 2)
        let size = contentView.bounds.size
        guard size.width > 1, size.height > 1 else {
            return CGSize(width: 1200, height: 1200)
        }

        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func coverTargetSize() -> CGSize {
        let scale = max(traitCollection.displayScale, 2)
        let longestSide = max(contentView.bounds.width, contentView.bounds.height)
        let targetSide = min(max(longestSide * scale * 0.45, 420), 900)
        return CGSize(width: targetSide, height: targetSide)
    }
}

extension RouteMediaBrowserCell: UIScrollViewDelegate, UIGestureRecognizerDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerZoomedImageIfNeeded()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: contentView)

        if gestureRecognizer === blankAreaTapGesture {
            return isBlackArea(at: point)
        }

        if gestureRecognizer === imageSingleTapGesture || gestureRecognizer === imageDoubleTapGesture {
            guard let contentRect = displayedImageContentRect() else {
                return false
            }
            return contentRect.insetBy(dx: -8, dy: -8).contains(point)
        }

        if gestureRecognizer === livePhotoTapGesture {
            guard let contentRect = displayedLivePhotoContentRect() else {
                return false
            }
            return contentRect.insetBy(dx: -8, dy: -8).contains(point)
        }

        if gestureRecognizer === videoTapGesture {
            guard let contentRect = displayedMediaContentRect() else {
                return false
            }
            return contentRect.insetBy(dx: -8, dy: -8).contains(point)
        }

        return true
    }
}
