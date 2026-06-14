//
//  RouteMediaBrowserViewController+UICollectionViewDataSource.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension RouteMediaBrowserViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        mediaItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: RouteMediaBrowserCell.reuseIdentifier,
            for: indexPath
        )

        if let cell = cell as? RouteMediaBrowserCell {
            cell.configure(with: mediaItems[indexPath.item])
        }

        return cell
    }
}
