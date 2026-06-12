//
//  WorkoutRouteCell.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import SnapKit
import UIKit

final class WorkoutRouteCell: UICollectionViewCell {
    static let reuseIdentifier = "WorkoutRouteCell"

    private let imageView = UIImageView()
    private let infoContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let symbolView = UIImageView()
    private let distanceLabel = UILabel()
    private let dateContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let dateLabel = UILabel()
    private var representedID: String?
    private var currentWorkout: TrackedWorkout?
    private var renderedSize: CGSize = .zero

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
        representedID = nil
        currentWorkout = nil
        renderedSize = .zero
        imageView.image = nil
        symbolView.image = nil
        distanceLabel.text = nil
        dateLabel.text = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let currentWorkout, renderedSize != contentView.bounds.size else {
            return
        }

        renderSnapshot(for: currentWorkout)
    }

    func configure(with workout: TrackedWorkout) {
        symbolView.image = UIImage(systemName: workout.symbolName)
        distanceLabel.text = workout.distanceText
        dateLabel.text = workout.dateText
        representedID = workout.id
        currentWorkout = workout

        renderSnapshot(for: workout)
    }

    private func renderSnapshot(for workout: TrackedWorkout) {
        let targetSize = contentView.bounds.size
        guard targetSize.width > 1, targetSize.height > 1 else {
            return
        }

        representedID = workout.id
        renderedSize = targetSize
        imageView.image = nil

        WorkoutRouteSnapshotRenderer.cachedSnapshot(
            for: workout,
            size: targetSize,
            traitCollection: traitCollection
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard self?.representedID == workout.id else { return }
                self?.imageView.image = image
            }
        }
    }

    private func configureViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .tertiarySystemBackground

        infoContainer.layer.cornerRadius = 8
        infoContainer.layer.masksToBounds = true

        symbolView.tintColor = .label
        symbolView.contentMode = .scaleAspectFit

        distanceLabel.font = .preferredFont(forTextStyle: .headline)
        distanceLabel.textColor = .label
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.72

        dateContainer.layer.cornerRadius = 8
        dateContainer.layer.masksToBounds = true

        dateLabel.font = .preferredFont(forTextStyle: .caption1)
        dateLabel.textColor = .label

        contentView.addSubview(imageView)
        contentView.addSubview(infoContainer)
        contentView.addSubview(dateContainer)
        infoContainer.contentView.addSubview(symbolView)
        infoContainer.contentView.addSubview(distanceLabel)
        dateContainer.contentView.addSubview(dateLabel)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        infoContainer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.bottom.equalToSuperview().inset(8)
            make.height.equalTo(34)
        }

        symbolView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(9)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }

        distanceLabel.snp.makeConstraints { make in
            make.leading.equalTo(symbolView.snp.trailing).offset(6)
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }

        dateContainer.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.trailing.equalToSuperview().inset(8)
            make.height.equalTo(28)
        }

        dateLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(9)
            make.centerY.equalToSuperview()
        }
    }
}
