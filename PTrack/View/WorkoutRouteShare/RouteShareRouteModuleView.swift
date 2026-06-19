//
//  RouteShareRouteModuleView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareRouteModuleView: UIView {
    let pathView = WorkoutRoutePathView()
    let deleteButton = RouteShareModuleChrome.makeDeleteButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(with workout: TrackedWorkout, color: UIColor) {
        pathView.configure(with: workout)
        pathView.setStrokeColor(color)
        pathView.setLineWidth(2)
    }

    private func configureViews() {
        backgroundColor = .clear
        layer.cornerRadius = 8
        layer.masksToBounds = false

        addSubview(pathView)

        pathView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }
    }
}
