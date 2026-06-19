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

    func selectionChromeRect() -> CGRect {
        layoutIfNeeded()
        let pathRect = pathView.renderedContentBounds()
            .map { pathView.convert($0, to: self) }
            ?? pathView.frame.insetBy(dx: 14, dy: 14)
        let rect = expandedRect(pathRect.insetBy(dx: -4, dy: -4), minimumSize: CGSize(width: 52, height: 52))
        let clippedRect = rect.intersection(bounds)
        return clippedRect.isNull || clippedRect.isEmpty ? bounds.insetBy(dx: 10, dy: 10) : clippedRect
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        selectionChromeRect().contains(point)
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

    private func expandedRect(_ rect: CGRect, minimumSize: CGSize) -> CGRect {
        var expandedRect = rect
        if expandedRect.width < minimumSize.width {
            expandedRect = expandedRect.insetBy(dx: -(minimumSize.width - expandedRect.width) / 2, dy: 0)
        }
        if expandedRect.height < minimumSize.height {
            expandedRect = expandedRect.insetBy(dx: 0, dy: -(minimumSize.height - expandedRect.height) / 2)
        }
        return expandedRect
    }
}
