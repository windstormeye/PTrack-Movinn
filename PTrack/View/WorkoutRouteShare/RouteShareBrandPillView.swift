//
//  RouteShareBrandPillView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareBrandPillView: UIView {
    static let preferredSize = CGSize(width: 76, height: 24)

    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    private func configureViews() {
        backgroundColor = UIColor.white.withAlphaComponent(0.86)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        iconImageView.image = UIImage(named: "Movinn_icon")
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 4
        iconImageView.layer.cornerCurve = .continuous

        nameLabel.attributedText = brandNameText()
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.78
        nameLabel.numberOfLines = 1

        addSubview(iconImageView)
        addSubview(nameLabel)

        iconImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(6)
            make.centerY.equalToSuperview()
            make.size.equalTo(15)
        }

        nameLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconImageView.snp.trailing).offset(4)
            make.trailing.equalToSuperview().inset(5)
            make.centerY.equalToSuperview()
        }
    }

    private func brandNameText() -> NSAttributedString {
        let name = "Movinn"
        let text = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: UIColor.black
            ]
        )
        text.addAttribute(
            .foregroundColor,
            value: AppColors.movinnGreen,
            range: NSRange(location: name.count - 1, length: 1)
        )
        return text
    }
}
