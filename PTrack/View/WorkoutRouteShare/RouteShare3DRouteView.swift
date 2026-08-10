//
//  RouteShare3DRouteView.swift
//  PTrack
//
//  Created by Codex on 2026/8/10.
//
//  分享页 3D 轨迹模块。概念参考 Any Distance RouteScene 与 guizang-sports-skill 的
//  Three.js 实现(仅借鉴思路与参数,代码为独立实现):
//  - 等距圆柱投影 + 海拔夸张,轨迹沿路径挤出为管状几何
//  - 单色或坡度渐变两种配色,轨迹下方带渐隐垂幕
//  - 发光圆点沿轨迹巡游,整体缓慢自转

import SceneKit
import UIKit

final class RouteShare3DRouteView: UIView {
    private enum Metrics {
        static let horizontalExtent: Float = 200
        static let minVerticalRange: Float = 20
        static let maxVerticalRange: Float = 50
        static let verticalExaggeration: Float = 6.5
        static let baseY: Float = -16
        static let routeLift: Float = 4
        static let maximumPointCount = 400
        static let tubeRadius: CGFloat = 0.85
        static let glowRadiusMultiplier: CGFloat = 2.0
        static let radialSegmentCount = 6
        static let spinDuration: TimeInterval = 22
        static let dotTravelDuration: TimeInterval = 18
        static let haloPulseDuration: TimeInterval = 0.9
        static let horizontalSmoothing: Float = 0.18
        static let verticalSmoothing: Float = 0.3
        static let slopeClampRange: ClosedRange<Double> = -0.16...0.18
        static let slopeSmoothingWindowMeters: Double = 45
        static let derivedSlopeWindowMeters: Double = 55
    }

    private struct SlopeColorStop {
        let slope: Double
        let color: (red: CGFloat, green: CGFloat, blue: CGFloat)
    }

    private static let slopeColorStops: [SlopeColorStop] = [
        SlopeColorStop(slope: -0.08, color: (0.28, 0.65, 0.78)),
        SlopeColorStop(slope: -0.03, color: (0.47, 0.83, 0.77)),
        SlopeColorStop(slope: 0, color: (0.95, 0.96, 0.87)),
        SlopeColorStop(slope: 0.03, color: (0.84, 1.0, 0.39)),
        SlopeColorStop(slope: 0.06, color: (1.0, 0.78, 0.34)),
        SlopeColorStop(slope: 0.1, color: (1.0, 0.42, 0.26))
    ]

    private let sceneView = SCNView()
    private let snapshotImageView = UIImageView()
    private var routeGroupNode: SCNNode?
    private var routeTubeNode: SCNNode?
    private var glowTubeNode: SCNNode?
    private var curtainNode: SCNNode?
    private var dotNode: SCNNode?
    private var dotHaloNode: SCNNode?
    private var projectedPoints: [SCNVector3] = []
    private var smoothedSlopes: [Double] = []
    private var arcProgress: [Float] = []
    private var dotKeyTimes: [NSNumber] = []
    private var cameraNode: SCNNode?
    private var exportRenderer: SCNRenderer?
    private var configuredRouteID: String?
    private var routeColor: UIColor = .white
    private var colorMode: RouteShare3DColorMode = .solid
    private var isSnapshotCaptureActive = false
    private var isExportAnimationControlActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    // MARK: - Public

    func configure(with workout: TrackedWorkout) {
        let routeID = workout.id
        guard configuredRouteID != routeID else {
            return
        }

        let coordinates = workout.routeDetailCoordinates
        guard coordinates.count > 1 else {
            return
        }

        configuredRouteID = routeID
        buildScene(with: coordinates)
    }

    func setRouteColor(_ color: UIColor) {
        routeColor = color
        refreshMaterials()
    }

    func setColorMode(_ mode: RouteShare3DColorMode) {
        guard colorMode != mode else {
            return
        }
        colorMode = mode
        applyColorMode()
    }

    func setAnimationsPaused(_ paused: Bool) {
        sceneView.isPlaying = !paused
        sceneView.scene?.isPaused = paused
    }

    /// 导出静态图前调用:把当前帧渲染成静态图覆盖 SCNView,
    /// 避免 drawHierarchy 抓取 Metal 图层时出现空白。
    func setSnapshotCaptureActive(_ active: Bool) {
        guard active != isSnapshotCaptureActive else {
            return
        }
        isSnapshotCaptureActive = active
        if active {
            guard sceneView.scene != nil, !sceneView.isHidden else {
                return
            }
            snapshotImageView.image = sceneView.snapshot()
            snapshotImageView.isHidden = false
            sceneView.isHidden = true
        } else {
            guard snapshotImageView.image != nil else {
                return
            }
            snapshotImageView.isHidden = true
            snapshotImageView.image = nil
            sceneView.isHidden = false
        }
    }

    // MARK: - Export Animation Control

    /// 进入逐帧导出模式:移除 CAAnimation,改为手动驱动旋转与圆点位置,
    /// 并创建离屏渲染器按导出分辨率出帧。
    func beginExportAnimationControl() {
        guard !isExportAnimationControlActive else {
            return
        }
        isExportAnimationControlActive = true
        routeGroupNode?.removeAllAnimations()
        dotNode?.removeAllAnimations()
        dotHaloNode?.removeAllAnimations()

        if let scene = sceneView.scene {
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = scene
            renderer.pointOfView = cameraNode
            exportRenderer = renderer
        }
    }

    /// 离屏渲染当前 3D 状态,背景透明,pixelSize 为目标像素尺寸。
    func renderExportFrame(pixelSize: CGSize) -> UIImage? {
        guard sceneView.scene != nil else {
            return nil
        }
        guard let exportRenderer,
              pixelSize.width >= 1,
              pixelSize.height >= 1 else {
            // 兜底:退回视图快照(分辨率与预览一致)。
            return sceneView.snapshot()
        }
        return exportRenderer.snapshot(
            atTime: 0,
            with: pixelSize,
            antialiasingMode: .multisampling4X
        )
    }

    /// progress ∈ [0, 1]:整体旋转 progress×360°,圆点走到弧长 progress 处。
    func setExportProgress(_ progress: Double, elapsedSeconds: TimeInterval) {
        let bounded = Float(min(max(progress, 0), 1))
        routeGroupNode?.rotation = SCNVector4(0, 1, 0, bounded * 2 * .pi)

        let position = position(atArcProgress: bounded)
        dotNode?.position = position
        dotHaloNode?.position = position

        let pulsePhase = (elapsedSeconds.truncatingRemainder(dividingBy: Metrics.haloPulseDuration))
            / Metrics.haloPulseDuration
        let scale = 1 + Float(pulsePhase) * 1.6
        dotHaloNode?.scale = SCNVector3(scale, scale, scale)
        dotHaloNode?.opacity = 0.5 * (1 - pulsePhase)
    }

    /// 退出逐帧导出模式,恢复预览动画。
    func endExportAnimationControl() {
        guard isExportAnimationControlActive else {
            return
        }
        isExportAnimationControlActive = false
        exportRenderer = nil
        routeGroupNode?.rotation = SCNVector4(0, 1, 0, 0)
        dotHaloNode?.scale = SCNVector3(1, 1, 1)
        dotHaloNode?.opacity = 1
        if let routeGroupNode {
            addSpinAnimation(to: routeGroupNode)
        }
        installDotAnimations()
    }

    /// 逐帧导出时刷新静态快照(需先 setSnapshotCaptureActive(true))。
    func refreshSnapshotForCapture() {
        guard isSnapshotCaptureActive, sceneView.scene != nil else {
            return
        }
        snapshotImageView.image = sceneView.snapshot()
    }

    private func position(atArcProgress progress: Float) -> SCNVector3 {
        guard projectedPoints.count > 1, arcProgress.count == projectedPoints.count else {
            return projectedPoints.first ?? SCNVector3(0, 0, 0)
        }
        if progress <= 0 {
            return projectedPoints[0]
        }
        if progress >= 1 {
            return projectedPoints[projectedPoints.count - 1]
        }

        var upperIndex = 1
        while upperIndex < arcProgress.count - 1, arcProgress[upperIndex] < progress {
            upperIndex += 1
        }
        let lowerIndex = upperIndex - 1
        let span = arcProgress[upperIndex] - arcProgress[lowerIndex]
        let amount = span > 0 ? (progress - arcProgress[lowerIndex]) / span : 0
        let start = projectedPoints[lowerIndex]
        let end = projectedPoints[upperIndex]
        return SCNVector3(
            start.x + (end.x - start.x) * amount,
            start.y + (end.y - start.y) * amount,
            start.z + (end.z - start.z) * amount
        )
    }

    // MARK: - Setup

    private func configureViews() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        sceneView.isPlaying = true
        sceneView.rendersContinuously = true
        addSubview(sceneView)

        snapshotImageView.contentMode = .scaleAspectFit
        snapshotImageView.isHidden = true
        addSubview(snapshotImageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        snapshotImageView.frame = bounds
    }

    // MARK: - Scene Building

    private func buildScene(with coordinates: [RouteCoordinate]) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let sampled = downsample(coordinates, maximumCount: Metrics.maximumPointCount)
        let projection = project(sampled)
        projectedPoints = projection.points
        smoothedSlopes = smoothSlopes(
            rawSlopes(for: sampled, distances: projection.distances),
            distances: projection.distances
        )

        let groupNode = SCNNode()
        scene.rootNode.addChildNode(groupNode)
        routeGroupNode = groupNode

        addTubes(to: groupNode)
        addCurtain(to: groupNode)
        addDot(to: groupNode)
        addCamera(to: scene.rootNode)
        addSpinAnimation(to: groupNode)

        sceneView.scene = scene
        applyColorMode()
    }

    private func downsample(_ coordinates: [RouteCoordinate], maximumCount: Int) -> [RouteCoordinate] {
        guard coordinates.count > maximumCount else {
            return coordinates
        }
        let stride = Swift.max(1, coordinates.count / maximumCount)
        var sampled: [RouteCoordinate] = []
        sampled.reserveCapacity(maximumCount + 1)
        var index = 0
        while index < coordinates.count {
            sampled.append(coordinates[index])
            index += stride
        }
        if let last = coordinates.last, sampled.last?.timestamp != last.timestamp {
            sampled.append(last)
        }
        return sampled
    }

    private func project(_ coordinates: [RouteCoordinate]) -> (points: [SCNVector3], distances: [Double]) {
        let earthRadius = 6_371_000.0
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let centerLatitude = ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2
        let centerLongitude = ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        let cosLatitude = cos(centerLatitude * .pi / 180)

        let altitudes = coordinates.map { $0.altitudeMeters ?? 0 }
        let minAltitude = altitudes.min() ?? 0
        let maxAltitude = altitudes.max() ?? 0
        let altitudeRange = maxAltitude - minAltitude

        var rawPoints: [(x: Double, z: Double, altitude: Double)] = []
        rawPoints.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            let x = earthRadius * (coordinate.longitude - centerLongitude) * .pi / 180 * cosLatitude
            let z = -earthRadius * (coordinate.latitude - centerLatitude) * .pi / 180
            rawPoints.append((x, z, coordinate.altitudeMeters ?? 0))
        }

        var distances: [Double] = [0]
        distances.reserveCapacity(rawPoints.count)
        for index in 1..<rawPoints.count {
            let dx = rawPoints[index].x - rawPoints[index - 1].x
            let dz = rawPoints[index].z - rawPoints[index - 1].z
            distances.append(distances[index - 1] + (dx * dx + dz * dz).squareRoot())
        }

        let minX = rawPoints.map(\.x).min() ?? 0
        let maxX = rawPoints.map(\.x).max() ?? 0
        let minZ = rawPoints.map(\.z).min() ?? 0
        let maxZ = rawPoints.map(\.z).max() ?? 0
        let horizontalScale = Double(Metrics.horizontalExtent) / Swift.max(maxX - minX, maxZ - minZ, 1)
        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2

        let verticalScale: Double
        if altitudeRange > 0 {
            let renderedRange = Swift.min(
                Swift.max(altitudeRange * horizontalScale * Double(Metrics.verticalExaggeration), Double(Metrics.minVerticalRange)),
                Double(Metrics.maxVerticalRange)
            )
            verticalScale = renderedRange / altitudeRange
        } else {
            verticalScale = 0
        }

        var points: [SCNVector3] = []
        points.reserveCapacity(rawPoints.count)
        var previous: SCNVector3?
        for raw in rawPoints {
            var point = SCNVector3(
                Float((raw.x - centerX) * horizontalScale),
                Metrics.routeLift + Float((raw.altitude - minAltitude) * verticalScale),
                Float((raw.z - centerZ) * horizontalScale)
            )
            if let previousPoint = previous {
                point.x = point.x * (1 - Metrics.horizontalSmoothing) + previousPoint.x * Metrics.horizontalSmoothing
                point.y = point.y * (1 - Metrics.verticalSmoothing) + previousPoint.y * Metrics.verticalSmoothing
                point.z = point.z * (1 - Metrics.horizontalSmoothing) + previousPoint.z * Metrics.horizontalSmoothing
            }
            points.append(point)
            previous = point
        }
        return (points, distances)
    }

    // MARK: - Slopes

    private func rawSlopes(for coordinates: [RouteCoordinate], distances: [Double]) -> [Double] {
        let recordedGrades = coordinates.map(\.gradeRatio)
        let finiteGradeCount = recordedGrades.compactMap { $0 }.filter(\.isFinite).count
        if finiteGradeCount >= coordinates.count / 2 {
            return recordedGrades.map { grade in
                guard let grade, grade.isFinite else {
                    return 0
                }
                return grade.clamped(to: Metrics.slopeClampRange)
            }
        }

        // 无设备坡度时按海拔差推导,窗口取约 55 m 抑制 GPS 高程抖动。
        let altitudes = coordinates.map { $0.altitudeMeters ?? 0 }
        var slopes: [Double] = []
        slopes.reserveCapacity(coordinates.count)
        for index in 0..<coordinates.count {
            var left = index
            var right = index
            while left > 0, distances[index] - distances[left] < Metrics.derivedSlopeWindowMeters {
                left -= 1
            }
            while right < coordinates.count - 1, distances[right] - distances[index] < Metrics.derivedSlopeWindowMeters {
                right += 1
            }
            let run = Swift.max(distances[right] - distances[left], 1)
            slopes.append(((altitudes[right] - altitudes[left]) / run).clamped(to: Metrics.slopeClampRange))
        }
        return slopes
    }

    private func smoothSlopes(_ slopes: [Double], distances: [Double]) -> [Double] {
        guard slopes.count > 2 else {
            return slopes
        }
        var smoothed: [Double] = []
        smoothed.reserveCapacity(slopes.count)
        for index in 0..<slopes.count {
            var weightedSlope = 0.0
            var totalWeight = 0.0
            var sample = index
            while sample >= 0, distances[index] - distances[sample] <= Metrics.slopeSmoothingWindowMeters {
                let weight = 1 - (distances[index] - distances[sample]) / Metrics.slopeSmoothingWindowMeters
                weightedSlope += slopes[sample] * weight
                totalWeight += weight
                sample -= 1
            }
            sample = index + 1
            while sample < slopes.count, distances[sample] - distances[index] <= Metrics.slopeSmoothingWindowMeters {
                let weight = 1 - (distances[sample] - distances[index]) / Metrics.slopeSmoothingWindowMeters
                weightedSlope += slopes[sample] * weight
                totalWeight += weight
                sample += 1
            }
            smoothed.append(totalWeight > 0 ? weightedSlope / totalWeight : slopes[index])
        }
        return smoothed
    }

    private static func color(forSlope slope: Double) -> UIColor {
        let stops = slopeColorStops
        let bounded = slope.clamped(to: stops[0].slope...stops[stops.count - 1].slope)
        for index in 1..<stops.count where bounded <= stops[index].slope {
            let start = stops[index - 1]
            let end = stops[index]
            let span = Swift.max(end.slope - start.slope, 0.000_1)
            let rawProgress = (bounded - start.slope) / span
            let progress = CGFloat(rawProgress * rawProgress * (3 - 2 * rawProgress))
            return UIColor(
                red: start.color.red + (end.color.red - start.color.red) * progress,
                green: start.color.green + (end.color.green - start.color.green) * progress,
                blue: start.color.blue + (end.color.blue - start.color.blue) * progress,
                alpha: 1
            )
        }
        let last = stops[stops.count - 1]
        return UIColor(red: last.color.red, green: last.color.green, blue: last.color.blue, alpha: 1)
    }

    // MARK: - Nodes

    private func addTubes(to groupNode: SCNNode) {
        guard projectedPoints.count > 1 else {
            return
        }

        let routeGeometry = Self.makeTubeGeometry(
            points: projectedPoints,
            radius: Metrics.tubeRadius,
            radialSegments: Metrics.radialSegmentCount,
            vertexColors: nil
        )
        let routeNode = SCNNode(geometry: routeGeometry)
        groupNode.addChildNode(routeNode)
        routeTubeNode = routeNode

        let glowGeometry = Self.makeTubeGeometry(
            points: projectedPoints,
            radius: Metrics.tubeRadius * Metrics.glowRadiusMultiplier,
            radialSegments: Metrics.radialSegmentCount,
            vertexColors: nil
        )
        let glowNode = SCNNode(geometry: glowGeometry)
        glowNode.castsShadow = false
        groupNode.addChildNode(glowNode)
        glowTubeNode = glowNode
    }

    private func addCurtain(to groupNode: SCNNode) {
        guard projectedPoints.count > 1 else {
            return
        }
        let curtainGeometry = Self.makeCurtainGeometry(points: projectedPoints, baseY: Metrics.baseY)
        let node = SCNNode(geometry: curtainGeometry)
        node.castsShadow = false
        groupNode.addChildNode(node)
        curtainNode = node
    }

    private func addDot(to groupNode: SCNNode) {
        guard projectedPoints.count > 1 else {
            return
        }

        let dotGeometry = SCNSphere(radius: 2.4)
        let dotMaterial = SCNMaterial()
        dotMaterial.lightingModel = .constant
        dotMaterial.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.39, alpha: 1)
        dotGeometry.materials = [dotMaterial]
        let dot = SCNNode(geometry: dotGeometry)
        dot.castsShadow = false
        dot.position = projectedPoints[0]
        groupNode.addChildNode(dot)
        dotNode = dot

        let haloGeometry = SCNSphere(radius: 2.4)
        let haloMaterial = SCNMaterial()
        haloMaterial.lightingModel = .constant
        haloMaterial.diffuse.contents = UIColor(red: 1, green: 0.94, blue: 0.72, alpha: 1)
        haloMaterial.blendMode = .add
        haloMaterial.writesToDepthBuffer = false
        haloGeometry.materials = [haloMaterial]
        let halo = SCNNode(geometry: haloGeometry)
        halo.castsShadow = false
        halo.position = projectedPoints[0]
        groupNode.addChildNode(halo)
        dotHaloNode = halo

        var cumulative: Float = 0
        var runningLengths: [Float] = [0]
        for index in 1..<projectedPoints.count {
            cumulative += projectedPoints[index].distance(to: projectedPoints[index - 1])
            runningLengths.append(cumulative)
        }
        arcProgress = runningLengths.map { cumulative > 0 ? $0 / cumulative : 0 }
        dotKeyTimes = arcProgress.map { NSNumber(value: $0) }

        installDotAnimations()
    }

    private func installDotAnimations() {
        guard let dotNode, let dotHaloNode, projectedPoints.count > 1 else {
            return
        }

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.values = projectedPoints.map { NSValue(scnVector3: $0) }
        travel.keyTimes = dotKeyTimes
        travel.duration = Metrics.dotTravelDuration
        travel.repeatCount = .greatestFiniteMagnitude
        travel.calculationMode = .linear
        dotNode.addAnimation(travel, forKey: "travel")
        dotHaloNode.addAnimation(travel, forKey: "travel")

        let haloScale = CABasicAnimation(keyPath: "scale")
        haloScale.fromValue = NSValue(scnVector3: SCNVector3(1, 1, 1))
        haloScale.toValue = NSValue(scnVector3: SCNVector3(2.6, 2.6, 2.6))
        haloScale.duration = Metrics.haloPulseDuration
        haloScale.repeatCount = .greatestFiniteMagnitude
        dotHaloNode.addAnimation(haloScale, forKey: "pulse-scale")

        let haloOpacity = CABasicAnimation(keyPath: "opacity")
        haloOpacity.fromValue = 0.5
        haloOpacity.toValue = 0.001
        haloOpacity.duration = Metrics.haloPulseDuration
        haloOpacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        haloOpacity.repeatCount = .greatestFiniteMagnitude
        dotHaloNode.addAnimation(haloOpacity, forKey: "pulse-opacity")
    }

    private func addCamera(to rootNode: SCNNode) {
        let camera = SCNCamera()
        camera.fieldOfView = 36
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(10, 150, 340)

        let targetNode = SCNNode()
        targetNode.position = SCNVector3(0, 4, 0)
        rootNode.addChildNode(targetNode)
        cameraNode.constraints = [SCNLookAtConstraint(target: targetNode)]
        rootNode.addChildNode(cameraNode)
        self.cameraNode = cameraNode
    }

    private func addSpinAnimation(to groupNode: SCNNode) {
        let spin = CABasicAnimation(keyPath: "rotation")
        spin.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        spin.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 2 * Float.pi))
        spin.duration = Metrics.spinDuration
        spin.repeatCount = .greatestFiniteMagnitude
        groupNode.addAnimation(spin, forKey: "spin")
    }

    // MARK: - Color Mode

    private func applyColorMode() {
        guard let routeTubeNode, let glowTubeNode, let curtainNode else {
            return
        }

        let colors: [UIColor]? = colorMode == .slope
            ? smoothedSlopes.map(Self.color(forSlope:))
            : nil
        routeTubeNode.geometry = Self.makeTubeGeometry(
            points: projectedPoints,
            radius: Metrics.tubeRadius,
            radialSegments: Metrics.radialSegmentCount,
            vertexColors: colors
        )
        glowTubeNode.geometry = Self.makeTubeGeometry(
            points: projectedPoints,
            radius: Metrics.tubeRadius * Metrics.glowRadiusMultiplier,
            radialSegments: Metrics.radialSegmentCount,
            vertexColors: colors
        )
        curtainNode.geometry = Self.makeCurtainGeometry(
            points: projectedPoints,
            baseY: Metrics.baseY,
            vertexColors: colors
        )
        if let material = curtainNode.geometry?.firstMaterial {
            material.transparent.contents = Self.makeCurtainFadeImage()
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
        }
        refreshMaterials()
    }

    private func refreshMaterials() {
        // 纯色模式下顶点色为空,diffuse 直接决定颜色;坡度模式顶点色 × 白色 diffuse。
        let baseColor = colorMode == .solid ? routeColor : UIColor.white
        if let material = routeTubeNode?.geometry?.firstMaterial {
            material.lightingModel = .constant
            material.diffuse.contents = baseColor
        }
        if let material = glowTubeNode?.geometry?.firstMaterial {
            material.lightingModel = .constant
            material.diffuse.contents = baseColor
            material.transparency = 0.12
            material.blendMode = .add
            material.writesToDepthBuffer = false
        }
        if let material = curtainNode?.geometry?.firstMaterial {
            material.lightingModel = .constant
            material.diffuse.contents = colorMode == .solid
                ? routeColor.withAlphaComponent(0.9)
                : UIColor.white
        }
    }

    // MARK: - Geometry Builders

    private static func makeTubeGeometry(
        points: [SCNVector3],
        radius: CGFloat,
        radialSegments: Int,
        vertexColors: [UIColor]?
    ) -> SCNGeometry {
        precondition(points.count > 1)

        // 平行传输标架:沿路径推进法向量,避免管壁扭转。
        var tangents: [SCNVector3] = []
        tangents.reserveCapacity(points.count)
        for index in 0..<points.count {
            let previous = points[Swift.max(index - 1, 0)]
            let next = points[Swift.min(index + 1, points.count - 1)]
            tangents.append((next - previous).normalized())
        }

        var normal = tangents[0].anyPerpendicular()
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [SCNVector3] = []
        let ringVertexCount = radialSegments + 1
        vertices.reserveCapacity(points.count * ringVertexCount)
        normals.reserveCapacity(points.count * ringVertexCount)

        for index in 0..<points.count {
            let tangent = tangents[index]
            normal = (normal - tangent * normal.dot(tangent)).normalized()
            let binormal = tangent.cross(normal)
            var colorVector = SCNVector3(1, 1, 1)
            if let vertexColors {
                let sourceColor = vertexColors[Swift.min(index, vertexColors.count - 1)]
                var red: CGFloat = 1
                var green: CGFloat = 1
                var blue: CGFloat = 1
                sourceColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
                colorVector = SCNVector3(Float(red), Float(green), Float(blue))
            }
            for radial in 0...radialSegments {
                let angle = Float(radial) / Float(radialSegments) * 2 * .pi
                let direction = normal * cos(angle) + binormal * sin(angle)
                vertices.append(points[index] + direction * Float(radius))
                normals.append(direction)
                colors.append(colorVector)
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity((points.count - 1) * radialSegments * 6)
        for segment in 0..<(points.count - 1) {
            for radial in 0..<radialSegments {
                let a = Int32(segment * ringVertexCount + radial)
                let b = Int32(segment * ringVertexCount + radial + 1)
                let c = Int32((segment + 1) * ringVertexCount + radial)
                let d = Int32((segment + 1) * ringVertexCount + radial + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        var sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals)
        ]
        if vertexColors != nil {
            sources.append(makeColorSource(colors))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]
        return geometry
    }

    private static func makeCurtainGeometry(
        points: [SCNVector3],
        baseY: Float,
        vertexColors: [UIColor]? = nil
    ) -> SCNGeometry {
        precondition(points.count > 1)

        var vertices: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        var colors: [SCNVector3] = []
        vertices.reserveCapacity(points.count * 2)

        for index in 0..<points.count {
            let top = points[index]
            vertices.append(top)
            vertices.append(SCNVector3(top.x, baseY, top.z))
            let u = CGFloat(index) / CGFloat(points.count - 1)
            textureCoordinates.append(CGPoint(x: u, y: 0))
            textureCoordinates.append(CGPoint(x: u, y: 1))
            var colorVector = SCNVector3(1, 1, 1)
            if let vertexColors {
                let sourceColor = vertexColors[Swift.min(index, vertexColors.count - 1)]
                var red: CGFloat = 1
                var green: CGFloat = 1
                var blue: CGFloat = 1
                sourceColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
                colorVector = SCNVector3(Float(red), Float(green), Float(blue))
            }
            colors.append(colorVector)
            colors.append(colorVector * 0.24)
        }

        var indices: [Int32] = []
        indices.reserveCapacity((points.count - 1) * 6)
        for segment in 0..<(points.count - 1) {
            let a = Int32(segment * 2)
            let b = Int32(segment * 2 + 1)
            let c = Int32(segment * 2 + 2)
            let d = Int32(segment * 2 + 3)
            indices.append(contentsOf: [a, b, c, c, b, d])
        }

        var sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(textureCoordinates: textureCoordinates)
        ]
        if vertexColors != nil {
            sources.append(makeColorSource(colors))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.transparent.contents = makeCurtainFadeImage()
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    private static func makeColorSource(_ colors: [SCNVector3]) -> SCNGeometrySource {
        let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(
            data: data,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )
    }

    private static func makeCurtainFadeImage() -> UIImage {
        let size = CGSize(width: 1, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let gradientColors = [
                UIColor(white: 1, alpha: 0.42).cgColor,
                UIColor(white: 1, alpha: 0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors,
                locations: [0, 1]
            ) else {
                return
            }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}

// MARK: - Vector Helpers

private extension SCNVector3 {
    static func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
    }

    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        SCNVector3(left.x - right.x, left.y - right.y, left.z - right.z)
    }

    static func * (vector: SCNVector3, scalar: Float) -> SCNVector3 {
        SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    }

    func dot(_ other: SCNVector3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: SCNVector3) -> SCNVector3 {
        SCNVector3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    func length() -> Float {
        (x * x + y * y + z * z).squareRoot()
    }

    func normalized() -> SCNVector3 {
        let magnitude = length()
        guard magnitude > 0.000_001 else {
            return SCNVector3(0, 1, 0)
        }
        return self * (1 / magnitude)
    }

    func distance(to other: SCNVector3) -> Float {
        (self - other).length()
    }

    func anyPerpendicular() -> SCNVector3 {
        let reference = abs(y) < 0.99 ? SCNVector3(0, 1, 0) : SCNVector3(1, 0, 0)
        return cross(reference).normalized()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
