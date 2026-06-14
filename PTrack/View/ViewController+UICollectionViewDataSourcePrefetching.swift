//
//  ViewController+UICollectionViewDataSourcePrefetching.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension ViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        // Home cells render route-only thumbnails as vector layers, so there is nothing to prefetch.
    }
}
