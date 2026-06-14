//
//  RouteEndpointAnnotationView.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

final class RouteEndpointAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteEndpointAnnotationView"

    private let diameter: CGFloat = 18

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureBaseView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBaseView()
    }

    func configure(kind: RouteEndpointKind) {
        backgroundColor = kind == .start ? .systemGreen : .systemRed
    }

    private func configureBaseView() {
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .required

        layer.cornerRadius = diameter / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 3
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}
