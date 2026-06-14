//
//  RouteMediaBrowserViewController+UICollectionViewDelegateFlowLayout.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension RouteMediaBrowserViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        collectionView.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let index = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        updateTitle(for: min(max(index, 0), mediaItems.count - 1))
    }
}
