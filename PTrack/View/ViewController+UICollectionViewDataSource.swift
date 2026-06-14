//
//  ViewController+UICollectionViewDataSource.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        workouts.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WorkoutRouteCell.reuseIdentifier,
            for: indexPath
        )

        if let cell = cell as? WorkoutRouteCell {
            cell.configure(with: workouts[indexPath.item], columnCount: columnCount, showsMap: false)
        }

        return cell
    }
}
