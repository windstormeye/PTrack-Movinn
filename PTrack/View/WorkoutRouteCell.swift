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
    private let timeTagLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5))
    private let selectionCheckmarkEffectView = UIVisualEffectView(effect: nil)
    private let selectionCheckmarkIconView = UIImageView()
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
        contentView.alpha = 1
        timeTagLabel.text = nil
        timeTagLabel.isHidden = true
        selectionCheckmarkEffectView.isHidden = true
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
        showsNewBadge: Bool,
        timeTagText: String? = nil,
        showsSelectionCheckmark: Bool = false,
        isEnabled: Bool = true
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
        newBadgeLabel.text = AppLocalization.text(workout.isRouteCollectionSource ? .newRoute : .newActivity)
        setShowsNewBadge(showsNewBadge)
        configureTimeTag(timeTagText)
        contentView.alpha = isEnabled ? 1 : 0.32
        setShowsSelectionCheckmark(showsSelectionCheckmark, isEnabled: isEnabled)

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

    func setShowsSelectionCheckmark(
        _ showsSelectionCheckmark: Bool,
        isEnabled: Bool = true,
        animated: Bool = false
    ) {
        let isVisible = showsSelectionCheckmark && isEnabled
        let updateVisibility = {
            self.selectionCheckmarkEffectView.alpha = isVisible ? 1 : 0
            self.selectionCheckmarkEffectView.isHidden = !isVisible
            self.selectionCheckmarkIconView.tintAdjustmentMode = .normal
            self.selectionCheckmarkIconView.tintColor = self.selectionCheckmarkTintColor()
        }

        guard animated else {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                updateVisibility()
                CATransaction.commit()
            }
            return
        }

        if isVisible {
            selectionCheckmarkEffectView.isHidden = false
        }

        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            updateVisibility()
        } completion: { _ in
            self.selectionCheckmarkEffectView.isHidden = !isVisible
        }
    }

    private func selectionCheckmarkTintColor() -> UIColor {
        return AppColors.movinnGreen
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
        contentView.backgroundColor = .clear
        imageView.backgroundColor = .clear
        imageView.isHidden = !showsMap
        pathView.isHidden = showsMap
        backgroundColor = .clear
    }

    private func configureTimeTag(_ text: String?) {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        timeTagLabel.text = trimmedText
        timeTagLabel.isHidden = trimmedText?.isEmpty != false
    }

    private func configureViews() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .clear
        pathView.isHidden = true

        timeTagLabel.isHidden = true
        timeTagLabel.textColor = UIColor.black.withAlphaComponent(0.82)
        timeTagLabel.font = .systemFont(ofSize: 8, weight: .bold)
        timeTagLabel.backgroundColor = UIColor.white.withAlphaComponent(0.82)
        timeTagLabel.layer.cornerRadius = 5
        timeTagLabel.layer.masksToBounds = true
        timeTagLabel.layer.zPosition = 20
        timeTagLabel.isUserInteractionEnabled = false

        configureSelectionCheckmarkView()

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
        contentView.addSubview(timeTagLabel)
        contentView.addSubview(selectionCheckmarkEffectView)
        selectionCheckmarkEffectView.contentView.addSubview(selectionCheckmarkIconView)
        addSubview(newBadgeLabel)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        pathView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        timeTagLabel.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(6)
        }

        selectionCheckmarkEffectView.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(6)
            make.width.height.equalTo(26)
        }

        selectionCheckmarkIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(16)
        }
    }

    private func configureSelectionCheckmarkView() {
        selectionCheckmarkEffectView.isHidden = true
        selectionCheckmarkEffectView.layer.cornerRadius = 13
        selectionCheckmarkEffectView.layer.masksToBounds = true
        selectionCheckmarkEffectView.layer.zPosition = 20
        selectionCheckmarkEffectView.isUserInteractionEnabled = false

        selectionCheckmarkIconView.contentMode = .scaleAspectFit
        selectionCheckmarkIconView.tintAdjustmentMode = .normal
        selectionCheckmarkIconView.tintColor = selectionCheckmarkTintColor()
        selectionCheckmarkIconView.isUserInteractionEnabled = false

        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            effect.tintColor = UIColor.white.withAlphaComponent(0.06)
            selectionCheckmarkEffectView.effect = effect
            selectionCheckmarkEffectView.backgroundColor = .clear
            selectionCheckmarkEffectView.contentView.backgroundColor = .clear
            selectionCheckmarkIconView.image = UIImage(
                systemName: "checkmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            )
        } else {
            selectionCheckmarkEffectView.effect = nil
            selectionCheckmarkEffectView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
            selectionCheckmarkEffectView.contentView.backgroundColor = .clear
            selectionCheckmarkIconView.image = UIImage(
                systemName: "checkmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            )
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
