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

final class RouteMediaBrowserCell: UICollectionViewCell {
    static let reuseIdentifier = "RouteMediaBrowserCell"

    private let imageView = UIImageView()
    private let livePhotoView = PHLivePhotoView()
    private let videoContainerView = UIView()
    private let playButton = UIButton(type: .system)
    private let imageManager = PHImageManager.default()

    private var representedAssetID: String?
    private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var livePhotoRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var videoRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequests()
        representedAssetID = nil
        imageView.image = nil
        livePhotoView.stopPlayback()
        livePhotoView.livePhoto = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playButton.isHidden = true
        playButton.alpha = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = videoContainerView.bounds
    }

    func configure(with mediaItem: RouteMediaItem) {
        representedAssetID = mediaItem.id
        imageView.isHidden = true
        livePhotoView.isHidden = true
        videoContainerView.isHidden = true
        playButton.isHidden = true

        if mediaItem.isVideo {
            configureVideo(with: mediaItem.asset)
        } else if mediaItem.isLivePhoto {
            configureLivePhoto(with: mediaItem.asset)
        } else {
            configureImage(with: mediaItem.asset)
        }
    }

    private func configureViews() {
        contentView.backgroundColor = .black

        imageView.contentMode = .scaleAspectFit
        livePhotoView.contentMode = .scaleAspectFit
        videoContainerView.backgroundColor = .black

        playButton.setImage(
            UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 58)),
            for: .normal
        )
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(toggleVideoPlayback), for: .touchUpInside)

        contentView.addSubview(imageView)
        contentView.addSubview(livePhotoView)
        contentView.addSubview(videoContainerView)
        contentView.addSubview(playButton)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        livePhotoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        videoContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(74)
        }
    }

    private func configureImage(with asset: PHAsset) {
        imageView.isHidden = false

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageRequestID = imageManager.requestImage(
            for: asset,
            targetSize: mediaTargetSize(),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            guard self?.representedAssetID == asset.localIdentifier else {
                return
            }

            self?.imageView.image = image
        }
    }

    private func configureLivePhoto(with asset: PHAsset) {
        livePhotoView.isHidden = false

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        livePhotoRequestID = imageManager.requestLivePhoto(
            for: asset,
            targetSize: mediaTargetSize(),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] livePhoto, _ in
            guard self?.representedAssetID == asset.localIdentifier else {
                return
            }

            self?.livePhotoView.livePhoto = livePhoto
            self?.livePhotoView.startPlayback(with: .hint)
        }
    }

    private func configureVideo(with asset: PHAsset) {
        videoContainerView.isHidden = false
        playButton.isHidden = false
        playButton.alpha = 1

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        videoRequestID = imageManager.requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
            DispatchQueue.main.async {
                guard self?.representedAssetID == asset.localIdentifier, let avAsset else {
                    return
                }

                let playerItem = AVPlayerItem(asset: avAsset)
                let player = AVPlayer(playerItem: playerItem)
                let playerLayer = AVPlayerLayer(player: player)
                playerLayer.videoGravity = .resizeAspect
                playerLayer.frame = self?.videoContainerView.bounds ?? .zero

                self?.playerLayer?.removeFromSuperlayer()
                self?.player = player
                self?.playerLayer = playerLayer
                self?.videoContainerView.layer.addSublayer(playerLayer)
            }
        }
    }

    @objc private func toggleVideoPlayback() {
        guard let player else {
            return
        }

        if player.timeControlStatus == .playing {
            player.pause()
            playButton.alpha = 1
        } else {
            player.play()
            playButton.alpha = 0.35
        }
    }

    private func cancelRequests() {
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
}
