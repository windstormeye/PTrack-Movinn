//
//  RouteSharePhotoCell.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import Photos
import SnapKit
import UIKit

final class RouteSharePhotoCell: UICollectionViewCell {
    static let reuseIdentifier = "RouteSharePhotoCell"
    private static let selectedBorderWidth: CGFloat = 3.5

    private let imageView = UIImageView()
    private let addIconView = UIImageView()
    private let liveIconView = UIImageView()
    private let disabledOverlayView = UIView()
    private var imageRequestID: PHImageRequestID?
    private var representedAssetIdentifier: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    deinit {
        cancelImageRequest()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelImageRequest()
        representedAssetIdentifier = nil
        imageView.image = nil
        addIconView.isHidden = true
        liveIconView.isHidden = true
        disabledOverlayView.isHidden = true
        contentView.layer.borderWidth = 0
    }

    private func cancelImageRequest() {
        if let imageRequestID {
            PHImageManager.default().cancelImageRequest(imageRequestID)
            self.imageRequestID = nil
        }
    }

    func configure(asset: PHAsset, isSelected: Bool) {
        applyImageStyle(isSelected: isSelected)
        liveIconView.isHidden = !asset.mediaSubtypes.contains(.photoLive)
        representedAssetIdentifier = asset.localIdentifier

        let scale = max(UIScreen.main.scale, 2)
        let targetSize = CGSize(width: 72 * scale, height: 72 * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageRequestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self,
                  representedAssetIdentifier == asset.localIdentifier else {
                return
            }
            imageView.image = image
        }
    }

    func configure(image: UIImage, isSelected: Bool) {
        applyImageStyle(isSelected: isSelected)
        liveIconView.isHidden = true
        imageView.image = image
    }

    func configureMap(isSelected: Bool) {
        contentView.backgroundColor = AppColors.shareActionBackground
        imageView.image = nil
        imageView.backgroundColor = .clear
        addIconView.image = UIImage(
            systemName: "map",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        )
        addIconView.isHidden = false
        liveIconView.isHidden = true
        contentView.layer.borderWidth = isSelected ? Self.selectedBorderWidth : 0
        contentView.layer.borderColor = AppColors.movinnGreen.cgColor
    }

    func configureCollage(isSelected: Bool) {
        contentView.backgroundColor = AppColors.shareActionBackground
        imageView.image = nil
        imageView.backgroundColor = .clear
        addIconView.image = UIImage(
            systemName: "square.grid.2x2",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        )
        addIconView.isHidden = false
        liveIconView.isHidden = true
        contentView.layer.borderWidth = isSelected ? Self.selectedBorderWidth : 0
        contentView.layer.borderColor = AppColors.movinnGreen.cgColor
    }

    func configureAdd() {
        contentView.backgroundColor = AppColors.shareActionBackground
        imageView.image = nil
        imageView.backgroundColor = .clear
        addIconView.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        addIconView.isHidden = false
        liveIconView.isHidden = true
        contentView.layer.borderWidth = 0
    }

    private func applyImageStyle(isSelected: Bool) {
        contentView.backgroundColor = .black
        imageView.backgroundColor = AppColors.placeholderBackground
        addIconView.isHidden = true
        contentView.layer.borderWidth = isSelected ? Self.selectedBorderWidth : 0
        contentView.layer.borderColor = AppColors.movinnGreen.cgColor
    }

    func setDisabled(_ disabled: Bool) {
        disabledOverlayView.isHidden = !disabled
    }

    func setSelectionHighlighted(_ highlighted: Bool) {
        contentView.layer.borderWidth = highlighted ? Self.selectedBorderWidth : 0
        contentView.layer.borderColor = AppColors.movinnGreen.cgColor
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.layer.cornerRadius = 7
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        addIconView.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        addIconView.tintColor = AppColors.solidForeground
        addIconView.contentMode = .scaleAspectFit

        liveIconView.image = UIImage(
            systemName: "livephoto",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        liveIconView.tintColor = .white
        liveIconView.contentMode = .scaleAspectFit
        liveIconView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        liveIconView.layer.cornerRadius = 7
        liveIconView.layer.masksToBounds = true
        liveIconView.isHidden = true

        disabledOverlayView.backgroundColor = AppColors.background(alpha: 0.58)
        disabledOverlayView.isUserInteractionEnabled = false
        disabledOverlayView.isHidden = true

        contentView.addSubview(imageView)
        contentView.addSubview(addIconView)
        contentView.addSubview(liveIconView)
        contentView.addSubview(disabledOverlayView)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        addIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(24)
        }

        liveIconView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(4)
            make.size.equalTo(14)
        }

        disabledOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
