//
//  RouteShareModuleChrome.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import UIKit

enum RouteShareModuleChrome {
    static func makeDeleteButton() -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        )
        configuration.baseForegroundColor = AppColors.solidForeground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        button.configuration = configuration
        button.backgroundColor = AppColors.solidBackground
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.isHidden = true
        return button
    }
}
