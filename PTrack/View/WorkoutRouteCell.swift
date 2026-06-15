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
    private let pathView = WorkoutRoutePathView()
    private let newBadgeLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 1.5, left: 4, bottom: 1.5, right: 4))
    private var representedID: String?
    private var currentWorkout: TrackedWorkout?
    private var renderedSize: CGSize = .zero
    private var currentShowsMap = true
    private var showsNewBadge = false

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
        setShowsNewBadge(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutNewBadgeLabel()

        guard currentShowsMap, let currentWorkout, renderedSize != contentView.bounds.size else {
            return
        }

        renderSnapshot(for: currentWorkout)
    }

    func configure(
        with workout: TrackedWorkout,
        columnCount: CGFloat,
        showsMap: Bool,
        showsNewBadge: Bool
    ) {
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
        newBadgeLabel.text = AppLocalization.text(.newActivity)
        setShowsNewBadge(showsNewBadge)

        guard showsMap else {
            imageView.image = nil
            renderedSize = .zero
            pathView.configure(with: workout)
            return
        }

        if needsSnapshot {
            renderSnapshot(for: workout)
        }
    }

    func setShowsNewBadge(_ showsNewBadge: Bool) {
        self.showsNewBadge = showsNewBadge
        newBadgeLabel.isHidden = !showsNewBadge
        layer.zPosition = showsNewBadge ? 10 : 0
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
        imageView.isHidden = !showsMap
        pathView.isHidden = showsMap
        backgroundColor = .clear
    }

    private func configureViews() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .tertiarySystemBackground
        pathView.isHidden = true

        newBadgeLabel.translatesAutoresizingMaskIntoConstraints = true
        newBadgeLabel.isHidden = true
        newBadgeLabel.text = AppLocalization.text(.newActivity)
        newBadgeLabel.textColor = UIColor.black.withAlphaComponent(0.86)
        newBadgeLabel.font = .systemFont(ofSize: 8, weight: .bold)
        newBadgeLabel.backgroundColor = AppColors.movinnGreen
        newBadgeLabel.layer.cornerRadius = 5
        newBadgeLabel.layer.masksToBounds = true
        newBadgeLabel.layer.zPosition = 21
        newBadgeLabel.isUserInteractionEnabled = false

        contentView.addSubview(imageView)
        contentView.addSubview(pathView)
        addSubview(newBadgeLabel)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        pathView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func layoutNewBadgeLabel() {
        let labelSize = newBadgeLabel.intrinsicContentSize
        newBadgeLabel.frame = CGRect(
            x: 0,
            y: -labelSize.height + 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }
}
