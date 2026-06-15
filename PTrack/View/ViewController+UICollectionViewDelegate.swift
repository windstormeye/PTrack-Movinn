//
//  ViewController+UICollectionViewDelegate.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import UIKit

extension ViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updatePullRefreshTracking(for: scrollView)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < workouts.count else {
            return
        }

        let workout = workouts[indexPath.item]
        if newWorkoutBadgeStore.markSeen(workout),
           let cell = collectionView.cellForItem(at: indexPath) as? WorkoutRouteCell {
            cell.setShowsNewBadge(false)
        }

        let detailViewController = WorkoutRouteDetailViewController(workout: workout)
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        performPullRefreshIfNeeded()
        if !decelerate {
            flushPendingWorkouts()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishPullRefreshTracking()
        flushPendingWorkouts()
    }
}
