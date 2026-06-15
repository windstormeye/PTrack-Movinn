//
//  ViewController+UICollectionViewDataSourcePrefetching.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension ViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.item < workouts.count {
            WorkoutRoutePathView.prewarmSource(for: workouts[indexPath.item])
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.item < workouts.count {
            WorkoutRoutePathView.cancelPrewarmSource(for: workouts[indexPath.item])
        }
    }
}
