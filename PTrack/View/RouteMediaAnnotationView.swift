//
//  RouteMediaAnnotationView.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import MapKit
import Photos
import SnapKit
import UIKit

final class RouteMediaAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteMediaAnnotationView"

    private let imageView = UIImageView()
    private let badgeView = UIImageView()
    private let bubbleLayer = CAShapeLayer()
    private static let imageManager = PHCachingImageManager()
    private static let annotationSize = CGSize(width: 50, height: 58)
    private static let bodyHeight: CGFloat = 50
    private static let imageInset: CGFloat = 4
    private static let imageSide: CGFloat = 42
    private static let imageCornerRadius: CGFloat = 7
    private static let badgeSize: CGFloat = 14
    private var representedAssetID: String?
    private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
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

        representedAssetID = nil
        imageView.image = nil
        badgeView.image = nil
        badgeView.isHidden = true
    }

    private func cancelImageRequest() {
        if imageRequestID != PHInvalidImageRequestID {
            Self.imageManager.cancelImageRequest(imageRequestID)
            imageRequestID = PHInvalidImageRequestID
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bubbleLayer.frame = bounds
        let path = bubblePath(in: bounds).cgPath
        bubbleLayer.path = path
        bubbleLayer.shadowPath = path
    }

    func configure(with mediaItem: RouteMediaItem) {
        representedAssetID = mediaItem.id
        badgeView.image = badgeImage(for: mediaItem)
        badgeView.isHidden = badgeView.image == nil

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        imageRequestID = Self.imageManager.requestImage(
            for: mediaItem.asset,
            targetSize: CGSize(width: 132, height: 132),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard self?.representedAssetID == mediaItem.id else {
                    return
                }

                if let image {
                    RouteMediaThumbnailCache.store(image, for: mediaItem.id)
                }

                self?.imageView.image = image
            }
        }
    }

    private func configureViews() {
        bounds = CGRect(origin: .zero, size: Self.annotationSize)
        centerOffset = CGPoint(x: 0, y: -Self.annotationSize.height / 2)
        displayPriority = .required
        collisionMode = .rectangle
        backgroundColor = .clear

        updateBubbleColors()
        bubbleLayer.shadowColor = UIColor.black.cgColor
        bubbleLayer.shadowOpacity = 0.08
        bubbleLayer.shadowRadius = 4
        bubbleLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.insertSublayer(bubbleLayer, at: 0)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Self.imageCornerRadius
        imageView.backgroundColor = .secondarySystemBackground

        badgeView.tintColor = .black
        badgeView.backgroundColor = UIColor.white.withAlphaComponent(0.82)
        badgeView.layer.cornerRadius = Self.badgeSize / 2
        badgeView.contentMode = .center
        badgeView.isHidden = true

        addSubview(imageView)
        addSubview(badgeView)

        imageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(Self.imageInset)
            make.height.equalTo(Self.imageSide)
        }

        badgeView.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(imageView).inset(3)
            make.size.equalTo(Self.badgeSize)
        }

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.updateBubbleColors()
        }
    }

    private func updateBubbleColors() {
        bubbleLayer.fillColor = UIColor.white.cgColor
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.92)
    }

    private func badgeImage(for mediaItem: RouteMediaItem) -> UIImage? {
        let imageName: String?
        if mediaItem.isVideo {
            imageName = "play.fill"
        } else if mediaItem.isLivePhoto {
            imageName = "livephoto"
        } else {
            imageName = nil
        }

        guard let imageName else {
            return nil
        }

        return UIImage(
            systemName: imageName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
    }

    private func bubblePath(in rect: CGRect) -> UIBezierPath {
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: Self.bodyHeight)
        let radius: CGFloat = 12
        let tailWidth: CGFloat = 14
        let tailHeight: CGFloat = 8
        let tailCenterX = bodyRect.midX
        let tailLeftX = tailCenterX - tailWidth / 2
        let tailRightX = tailCenterX + tailWidth / 2
        let tailTipY = min(rect.maxY, bodyRect.maxY + tailHeight)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY))
        path.addLine(to: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
        path.addArc(
            withCenter: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.minY + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - radius))
        path.addArc(
            withCenter: CGPoint(x: bodyRect.maxX - radius, y: bodyRect.maxY - radius),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: tailRightX, y: bodyRect.maxY))
        path.addLine(to: CGPoint(x: tailCenterX, y: tailTipY))
        path.addLine(to: CGPoint(x: tailLeftX, y: bodyRect.maxY))
        path.addLine(to: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY))
        path.addArc(
            withCenter: CGPoint(x: bodyRect.minX + radius, y: bodyRect.maxY - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
        path.addArc(
            withCenter: CGPoint(x: bodyRect.minX + radius, y: bodyRect.minY + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }
}
