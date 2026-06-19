//
//  RouteShareMetricsModuleView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareMetricsModuleView: UIView {
    let deleteButton = RouteShareModuleChrome.makeDeleteButton()

    private let distanceLabel = UILabel()
    private let durationLabel = UILabel()
    private let timeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(with workout: TrackedWorkout, color: UIColor) {
        distanceLabel.text = workout.distanceText
        durationLabel.text = workout.durationText
        timeLabel.text = workoutStartTimeText(for: workout)
        applyColor(color)
    }

    func updateLocalizedText(for workout: TrackedWorkout) {
        timeLabel.text = workoutStartTimeText(for: workout)
    }

    func applyColor(_ color: UIColor) {
        distanceLabel.textColor = color
        durationLabel.textColor = color.withAlphaComponent(0.92)
        timeLabel.textColor = color.withAlphaComponent(0.86)
        applyTextShadow(isVisible: !isEffectivelyBlack(color))
    }

    private func configureViews() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = false

        distanceLabel.font = .systemFont(ofSize: 38, weight: .heavy)
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.62
        distanceLabel.numberOfLines = 1

        durationLabel.font = .systemFont(ofSize: 18, weight: .bold)
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.7
        durationLabel.numberOfLines = 1

        timeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.7
        timeLabel.numberOfLines = 1
        timeLabel.clipsToBounds = false

        [distanceLabel, durationLabel, timeLabel].forEach { label in
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.36
            label.layer.shadowRadius = 6
            label.layer.shadowOffset = CGSize(width: 0, height: 2)
        }

        addSubview(distanceLabel)
        addSubview(durationLabel)
        addSubview(timeLabel)

        distanceLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(12)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        durationLabel.snp.makeConstraints { make in
            make.leading.equalTo(distanceLabel)
            make.top.equalTo(distanceLabel.snp.bottom).offset(2)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(distanceLabel)
            make.top.equalTo(durationLabel.snp.bottom).offset(6)
            make.trailing.equalToSuperview().inset(12)
            make.height.greaterThanOrEqualTo(18)
            make.bottom.lessThanOrEqualToSuperview().inset(8)
        }
    }

    private func applyTextShadow(isVisible: Bool) {
        [distanceLabel, durationLabel, timeLabel].forEach { label in
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = isVisible ? 0.36 : 0
            label.layer.shadowRadius = isVisible ? 6 : 0
            label.layer.shadowOffset = isVisible ? CGSize(width: 0, height: 2) : .zero
        }
    }

    private func isEffectivelyBlack(_ color: UIColor) -> Bool {
        let resolvedColor = color.resolvedColor(with: traitCollection)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if resolvedColor.getWhite(&white, alpha: &alpha) {
            return white < 0.08
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return max(red, green, blue) < 0.08
        }

        return false
    }

    private func workoutStartTimeText(for workout: TrackedWorkout) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return AppLocalization.format(.startTimeFormat, formatter.string(from: workout.startDate))
    }
}
