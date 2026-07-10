//
//  RouteShareExportLoadingView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareExportLoadingView: UIVisualEffectView {
    private let panelView = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let progressLabel = UILabel()
    private var panelHeightConstraint: Constraint?
    private var displayedProgress = 0.0
    private var transitionGeneration = 0

    init() {
        super.init(effect: nil)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        effect = nil
        configureViews()
    }

    func show(text: String, progress: Double? = nil, in parentView: UIView) {
        transitionGeneration &+= 1
        loadingLabel.text = text
        displayedProgress = 0
        setProgress(progress, animated: false)
        layer.removeAllAnimations()
        progressView.layer.removeAllAnimations()
        isHidden = false
        parentView.bringSubviewToFront(self)
        activityIndicator.startAnimating()
        UIView.animate(withDuration: 0.16) {
            self.alpha = 1
        }
    }

    func update(progress: Double) {
        guard !isHidden else {
            return
        }

        setProgress(progress, animated: true)
    }

    func hide(completion: (() -> Void)? = nil) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        layer.removeAllAnimations()
        guard !isHidden else {
            completion?()
            return
        }

        UIView.animate(withDuration: 0.16) {
            self.alpha = 0
        } completion: { _ in
            guard self.transitionGeneration == generation else {
                return
            }
            self.activityIndicator.stopAnimating()
            self.setProgress(nil, animated: false)
            self.isHidden = true
            completion?()
        }
    }

    private func configureViews() {
        isHidden = true
        alpha = 0
        contentView.backgroundColor = UIColor.black.withAlphaComponent(0.1)

        panelView.backgroundColor = AppColors.background(alpha: 0.86)
        panelView.layer.cornerRadius = 8
        panelView.layer.cornerCurve = .continuous
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.16
        panelView.layer.shadowRadius = 14
        panelView.layer.shadowOffset = CGSize(width: 0, height: 6)

        activityIndicator.hidesWhenStopped = false
        activityIndicator.color = AppColors.solidForeground

        loadingLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        loadingLabel.textColor = AppColors.solidForeground
        loadingLabel.textAlignment = .center

        progressView.progressTintColor = AppColors.movinnGreen
        progressView.trackTintColor = AppColors.foreground(alpha: 0.14)
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        progressLabel.textColor = AppColors.foreground(alpha: 0.72)
        progressLabel.textAlignment = .center

        contentView.addSubview(panelView)
        panelView.addSubview(activityIndicator)
        panelView.addSubview(loadingLabel)
        panelView.addSubview(progressView)
        panelView.addSubview(progressLabel)

        panelView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(216)
            panelHeightConstraint = make.height.equalTo(112).constraint
        }

        activityIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(22)
        }

        loadingLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(activityIndicator.snp.bottom).offset(12)
        }

        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(loadingLabel.snp.bottom).offset(16)
            make.height.equalTo(4)
        }

        progressLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(progressView.snp.bottom).offset(8)
        }
    }

    private func setProgress(_ progress: Double?, animated: Bool) {
        let isDeterminate = progress != nil
        progressView.isHidden = !isDeterminate
        progressLabel.isHidden = !isDeterminate
        panelHeightConstraint?.update(offset: isDeterminate ? 150 : 112)

        guard let progress else {
            displayedProgress = 0
            progressView.setProgress(0, animated: false)
            progressLabel.text = nil
            return
        }

        let clampedProgress = max(displayedProgress, min(max(progress, 0), 1))
        displayedProgress = clampedProgress
        progressView.setProgress(Float(clampedProgress), animated: animated)
        progressLabel.text = "\(Int((clampedProgress * 100).rounded()))%"
    }
}
