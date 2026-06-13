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
    private var representedID: String?
    private var currentWorkout: TrackedWorkout?
    private var renderedSize: CGSize = .zero
    private var currentShowsMap = true

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
        currentShowsMap = true
        imageView.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let currentWorkout, renderedSize != contentView.bounds.size else {
            return
        }

        renderSnapshot(for: currentWorkout)
    }

    func configure(with workout: TrackedWorkout, columnCount: CGFloat, showsMap: Bool) {
        let isNewWorkout = representedID != workout.id
        let needsSnapshot = representedID != workout.id
            || currentShowsMap != showsMap
            || imageView.image == nil
            || renderedSize != contentView.bounds.size

        if isNewWorkout {
            imageView.image = nil
        }

        representedID = workout.id
        currentWorkout = workout
        currentShowsMap = showsMap
        updateBackgroundVisibility(showsMap: showsMap)

        if needsSnapshot {
            renderSnapshot(for: workout)
        }
    }

    private func renderSnapshot(for workout: TrackedWorkout) {
        let targetSize = contentView.bounds.size
        guard targetSize.width > 1, targetSize.height > 1 else {
            return
        }

        representedID = workout.id
        renderedSize = targetSize

        WorkoutRouteSnapshotRenderer.cachedSnapshot(
            for: workout,
            size: targetSize,
            showsMap: currentShowsMap,
            traitCollection: traitCollection
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard self?.representedID == workout.id else { return }
                self?.imageView.image = image
            }
        }
    }

    private func updateBackgroundVisibility(showsMap: Bool) {
        contentView.backgroundColor = showsMap ? .secondarySystemBackground : .clear
        imageView.backgroundColor = showsMap ? .tertiarySystemBackground : .clear
        backgroundColor = .clear
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .tertiarySystemBackground

        contentView.addSubview(imageView)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
