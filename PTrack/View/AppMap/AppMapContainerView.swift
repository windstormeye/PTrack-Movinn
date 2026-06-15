//
//  AppMapContainerView.swift
//  PTrack
//
//  Created by Codex on 2026/6/15.
//

import MapKit
import SnapKit
import UIKit

final class AppMapContainerView: UIView {
    static let defaultBottomLogoAvoidanceOffset: CGFloat = 72

    let mapView = MKMapView()

    private let bottomLogoAvoidanceOffset: CGFloat

    init(bottomLogoAvoidanceOffset: CGFloat = AppMapContainerView.defaultBottomLogoAvoidanceOffset) {
        self.bottomLogoAvoidanceOffset = bottomLogoAvoidanceOffset
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        bottomLogoAvoidanceOffset = Self.defaultBottomLogoAvoidanceOffset
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        clipsToBounds = true
        addSubview(mapView)

        mapView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().offset(bottomLogoAvoidanceOffset)
        }
    }
}
