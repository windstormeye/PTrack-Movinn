//
//  ViewController+UICollectionViewDelegate.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension ViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < workouts.count else {
            return
        }

        let detailViewController = WorkoutRouteDetailViewController(workout: workouts[indexPath.item])
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            flushPendingWorkouts()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        flushPendingWorkouts()
    }
}
