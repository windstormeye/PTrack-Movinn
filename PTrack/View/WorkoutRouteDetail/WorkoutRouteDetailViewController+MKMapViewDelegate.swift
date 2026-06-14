//
//  WorkoutRouteDetailViewController+MKMapViewDelegate.swift
//  PTrack
//
//  Created by Codex on 2026/6/14.
//

import MapKit
import UIKit

extension WorkoutRouteDetailViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = workout.routeColor
        renderer.lineWidth = 4.5
        renderer.lineJoin = .round
        renderer.lineCap = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let replayAnnotation = annotation as? RouteReplayAnnotation {
            let identifier = RouteReplayAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteReplayAnnotationView
                ?? RouteReplayAnnotationView(annotation: replayAnnotation, reuseIdentifier: identifier)
            annotationView.annotation = replayAnnotation
            annotationView.configure(
                emoji: replayAnnotation.emoji,
                statusText: replayAnnotation.statusText,
                isFacingLeft: replayAnnotation.isFacingLeft
            )
            annotationView.superview?.bringSubviewToFront(annotationView)
            return annotationView
        }

        if let mediaAnnotation = annotation as? RouteMediaAnnotation {
            let identifier = RouteMediaAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteMediaAnnotationView
                ?? RouteMediaAnnotationView(annotation: mediaAnnotation, reuseIdentifier: identifier)
            annotationView.annotation = mediaAnnotation
            annotationView.configure(with: mediaAnnotation.mediaItem)
            return annotationView
        }

        guard let endpointAnnotation = annotation as? RouteEndpointAnnotation else {
            return nil
        }

        let identifier = RouteEndpointAnnotationView.reuseIdentifier
        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteEndpointAnnotationView
            ?? RouteEndpointAnnotationView(annotation: endpointAnnotation, reuseIdentifier: identifier)
        annotationView.annotation = endpointAnnotation
        annotationView.configure(kind: endpointAnnotation.kind)
        return annotationView
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        views
            .filter { $0.annotation is RouteReplayAnnotation }
            .forEach { $0.superview?.bringSubviewToFront($0) }
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: true)
        guard let mediaAnnotation = annotation as? RouteMediaAnnotation,
              let index = routeMediaItems.firstIndex(where: { $0.id == mediaAnnotation.mediaItem.id }) else {
            return
        }

        let browser = RouteMediaBrowserViewController(mediaItems: routeMediaItems, initialIndex: index)
        navigationController?.pushViewController(browser, animated: true)
    }
}
