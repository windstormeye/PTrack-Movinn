//
//  RouteShareToolBarView.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import SnapKit
import UIKit

final class RouteShareToolBarView: UIView {
    let colorButton = UIButton(type: .system)
    let aspectRatioButton = UIButton(type: .system)
    let mapStyleButton = UIButton(type: .system)
    let deleteButton = UIButton(type: .system)
    let addRouteButton = UIButton(type: .system)
    let addMetricsButton = UIButton(type: .system)

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    static func preferredWidth(for visibleButtonCount: Int) -> CGFloat {
        CGFloat(max(visibleButtonCount, 1)) * 62
    }

    func visibleButtonCount() -> Int {
        [
            colorButton,
            aspectRatioButton,
            mapStyleButton,
            deleteButton,
            addRouteButton,
            addMetricsButton
        ].filter { !$0.isHidden }.count
    }

    private func configureViews() {
        backgroundColor = UIColor(white: 0.94, alpha: 1)
        layer.cornerRadius = 18
        layer.masksToBounds = true

        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0

        addSubview(stackView)
        [
            colorButton,
            aspectRatioButton,
            mapStyleButton,
            deleteButton,
            addRouteButton,
            addMetricsButton
        ].forEach(stackView.addArrangedSubview)

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
