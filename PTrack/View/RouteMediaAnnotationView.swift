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

final class RouteMediaAnnotation: NSObject, MKAnnotation {
    let mediaItem: RouteMediaItem
    let coordinate: CLLocationCoordinate2D

    init(mediaItem: RouteMediaItem) {
        self.mediaItem = mediaItem
        coordinate = mediaItem.coordinate
        super.init()
    }
}

final class RouteMediaAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteMediaAnnotationView"

    private let imageView = UIImageView()
    private let badgeView = UIImageView()
    private let bubbleLayer = CAShapeLayer()
    private static let imageManager = PHCachingImageManager()
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

    override func prepareForReuse() {
        super.prepareForReuse()
        if imageRequestID != PHInvalidImageRequestID {
            Self.imageManager.cancelImageRequest(imageRequestID)
            imageRequestID = PHInvalidImageRequestID
        }

        representedAssetID = nil
        imageView.image = nil
        badgeView.image = nil
        badgeView.isHidden = true
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
            targetSize: CGSize(width: 144, height: 144),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard self?.representedAssetID == mediaItem.id else {
                return
            }

            self?.imageView.image = image
        }
    }

    private func configureViews() {
        bounds = CGRect(x: 0, y: 0, width: 66, height: 76)
        centerOffset = CGPoint(x: 0, y: -38)
        displayPriority = .required
        collisionMode = .rectangle
        backgroundColor = .clear

        bubbleLayer.fillColor = UIColor.white.cgColor
        bubbleLayer.shadowColor = UIColor.black.cgColor
        bubbleLayer.shadowOpacity = 0.08
        bubbleLayer.shadowRadius = 4
        bubbleLayer.shadowOffset = CGSize(width: 0, height: 1)
        layer.insertSublayer(bubbleLayer, at: 0)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 9
        imageView.backgroundColor = .secondarySystemBackground

        badgeView.tintColor = .white
        badgeView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        badgeView.layer.cornerRadius = 9
        badgeView.contentMode = .center
        badgeView.isHidden = true

        addSubview(imageView)
        addSubview(badgeView)

        imageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(5)
            make.height.equalTo(56)
        }

        badgeView.snp.makeConstraints { make in
            make.trailing.bottom.equalTo(imageView).inset(4)
            make.size.equalTo(18)
        }
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
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: 66)
        let radius: CGFloat = 16
        let tailWidth: CGFloat = 18
        let tailHeight: CGFloat = 12
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
