//
//  RouteShareExportLoadingView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareExportLoadingView: UIVisualEffectView {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        effect = UIBlurEffect(style: .systemThinMaterial)
        configureViews()
    }

    func show(text: String, in parentView: UIView) {
        loadingLabel.text = text
        isHidden = false
        parentView.bringSubviewToFront(self)
        activityIndicator.startAnimating()
        UIView.animate(withDuration: 0.16) {
            self.alpha = 1
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.16) {
            self.alpha = 0
        } completion: { _ in
            self.activityIndicator.stopAnimating()
            self.isHidden = true
        }
    }

    private func configureViews() {
        isHidden = true
        alpha = 0
        contentView.backgroundColor = AppColors.background(alpha: 0.28)

        let panelView = UIView()
        panelView.backgroundColor = AppColors.background(alpha: 0.92)
        panelView.layer.cornerRadius = 14
        panelView.layer.cornerCurve = .continuous
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.12
        panelView.layer.shadowRadius = 18
        panelView.layer.shadowOffset = CGSize(width: 0, height: 8)

        activityIndicator.hidesWhenStopped = false
        activityIndicator.color = AppColors.solidForeground

        loadingLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        loadingLabel.textColor = AppColors.solidForeground
        loadingLabel.textAlignment = .center

        contentView.addSubview(panelView)
        panelView.addSubview(activityIndicator)
        panelView.addSubview(loadingLabel)

        panelView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(176)
            make.height.equalTo(112)
        }

        activityIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(25)
        }

        loadingLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.top.equalTo(activityIndicator.snp.bottom).offset(14)
        }
    }
}
