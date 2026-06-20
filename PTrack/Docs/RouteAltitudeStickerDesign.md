# Route Altitude Sticker Design

## 背景

Outbase 宣传图里的“3D 海拔数据贴纸”不是严格意义上的 3D 地图视图。它更像一种 2.5D 数据可视化贴纸：

- 使用轨迹的经纬度保留路线形态。
- 使用轨迹点的海拔信息把路线向上抬升。
- 从抬升后的路线向下绘制半透明幕布，形成“立体海拔墙”的视觉。
- 底部展示距离、爬升高度、移动时间等摘要数据。

这个效果和 Movinn 的产品定位很契合：它不是专业运动分析，也不是教练指导，而是把“移动轨迹本身”做成更有记忆感、更适合分享的视觉资产。

## 设计结论

推荐第一版使用 `CoreGraphics` 或 `CAShapeLayer` 实现，不推荐一开始使用 `SceneKit`。

原因：

- 目标是分享图贴纸，不是可交互 3D 地图。
- 当前宣传图效果本质上是 2D 画布上的伪 3D 投影。
- `CoreGraphics` 更轻，体积小，性能稳定，和现有分享图导出链路更容易结合。
- 贴纸可以直接渲染成 `UIImage`，后续放进分享页、照片导出、Live Photo 帧都更自然。

`SceneKit` 可以作为后续版本，用于实现真正可旋转的 3D 路线、相机环绕动画或更强的深度效果。但第一版不需要。

## 当前工程基础

当前工程已经具备这个功能所需的大部分数据和导出基础：

- `PTrack/Model/RouteCoordinate.swift`
  - 已有 `latitude`
  - 已有 `longitude`
  - 已有 `altitudeMeters`
  - 已有 `timestamp`

- `PTrack/Model/TrackedWorkout.swift`
  - `routeDetailCoordinates` 能提供详情页完整轨迹点。

- `PTrack/Model/RouteSampler.swift`
  - 已有路线降采样能力，可以控制贴纸绘制点数。

- `PTrack/View/WorkoutRouteDetailViewController.swift`
  - 已经会从路线点中提取海拔数据。
  - 已有 `RouteElevationSample` 相关逻辑。

- `PTrack/View/WorkoutRouteShareViewController.swift`
  - 已有分享页承载场景。

- `PTrack/View/WorkoutRouteShare/RouteShareLivePhotoExporter.swift`
  - 已有视频和 Live Photo 导出基础。

因此，这个功能的核心改动应该集中在“新增一个贴纸渲染模块”，而不是改造数据模型。

## 目标

第一版目标：

- 在轨迹分享场景中生成一张 2.5D 海拔贴纸。
- 使用路线真实经纬度生成路线形状。
- 使用路线海拔生成高度起伏。
- 绘制橙色或主题色立体幕布。
- 显示起点、终点、最高点等基础视觉标记。
- 输出为 `UIImage`，供分享页合成或导出使用。

非目标：

- 不做真实 3D 地形。
- 不接入 Mapbox、Cesium 或在线高程地图。
- 不做相机自由旋转。
- 不做道路匹配。
- 不做海拔有效性校验。
- 不把它设计成训练分析图表。

## 推荐命名

这个功能在产品层可以叫：

- 3D 海拔贴纸
- 海拔轨迹贴纸
- 立体路线贴纸
- 爬升轨迹贴纸

工程模块建议使用更准确的命名：

- `RouteAltitudeStickerView`
- `RouteAltitudeStickerRenderer`
- `RouteAltitudeStickerLayout`
- `RouteAltitudeStickerPoint`
- `RouteAltitudeStickerStyle`

避免在工程里直接叫 `Route3DMapView`，因为它并不是地图，也不是完整 3D 场景。

## 数据输入

输入数据建议保持非常简单：

```swift
struct RouteAltitudeStickerInput {
    let coordinates: [RouteCoordinate]
    let distanceText: String
    let ascentText: String
    let movingTimeText: String
    let title: String?
}
```

其中 `coordinates` 来自：

```swift
let coordinates = workout.routeDetailCoordinates
```

如果点数太多，先降采样：

```swift
let sampledCoordinates = RouteSampler.downsample(
    coordinates,
    limit: 500
)
```

建议第一版的点数上限：

- 分享图：300 到 600 个点。
- 高清导出：600 到 1000 个点。
- 动态视频帧：200 到 400 个点。

## 坐标处理流程

整个贴纸渲染可以拆成五步：

1. 清理路线点。
2. 经纬度转平面坐标。
3. 海拔归一化。
4. 伪 3D 投影。
5. 绘制路线和幕布。

### 1. 清理路线点

过滤无效点：

```swift
let validCoordinates = coordinates.filter { coordinate in
    coordinate.latitude.isFinite &&
    coordinate.longitude.isFinite
}
```

如果有效点少于 2 个，贴纸不可绘制。

海拔缺失时不应该直接失败。可以按以下策略处理：

1. 如果大部分点有海拔，用线性插值补齐缺失点。
2. 如果只有少量点有海拔，用最近有效海拔补齐。
3. 如果完全没有海拔，降级为平面立体路线，或者隐藏“3D 海拔贴纸”入口。

第一版建议：

- 有至少 2 个海拔点：插值补齐。
- 少于 2 个海拔点：不展示该贴纸模板。

### 2. 经纬度转平面坐标

使用 `MKMapPoint` 将经纬度转换为平面坐标：

```swift
let mapPoint = MKMapPoint(coordinate.coordinate)
```

然后计算所有点的包围盒：

```swift
let minX = points.map(\.x).min() ?? 0
let maxX = points.map(\.x).max() ?? 0
let minY = points.map(\.y).min() ?? 0
let maxY = points.map(\.y).max() ?? 0
```

把路线中心移动到原点附近：

```swift
let centerX = (minX + maxX) / 2
let centerY = (minY + maxY) / 2

let localX = mapPoint.x - centerX
let localZ = mapPoint.y - centerY
```

这里用 `localZ` 是为了表达“深度轴”，虽然最终仍然画在 2D 画布上。

### 3. 海拔归一化

贴纸的高度不应该直接使用真实海拔绝对值，而应该使用相对海拔：

```swift
let relativeAltitude = altitude - minAltitude
```

如果直接使用绝对海拔，比如从 3200m 到 4300m，会导致整条线整体被抬得很高，但视觉上真正重要的是路线内部的起伏。

推荐规则：

- `minAltitude` 作为地面基准。
- `maxAltitude - minAltitude` 作为高度范围。
- 如果高度范围很小，需要给一个最小视觉高度。
- 如果高度范围很大，需要限制最大视觉高度。

示例：

```swift
let altitudeRange = max(maxAltitude - minAltitude, 1)
let normalizedAltitude = (altitude - minAltitude) / altitudeRange
let visualHeight = normalizedAltitude * maxVisualHeight
```

注意：

- 几何抬升使用“相对海拔”。
- 文案里的“爬升高度”使用“累计爬升”，两者不是一个概念。

## 伪 3D 投影

Outbase 宣传图的核心是把平面路线投影成一个斜视角形态。

可以使用简单的等距投影：

```swift
screenX = originX + (localX - localZ) * angleScale
screenY = originY + (localX + localZ) * depthScale - visualHeight
```

其中：

- `localX`：路线点的横向坐标。
- `localZ`：路线点的深度坐标。
- `visualHeight`：该点的海拔视觉高度。
- `angleScale`：控制左右展开程度。
- `depthScale`：控制前后纵深压缩程度。

每个轨迹点会生成两个屏幕点：

```swift
struct RouteAltitudeStickerProjectedPoint {
    let top: CGPoint
    let base: CGPoint
    let altitude: Double
    let progress: Double
}
```

- `top` 是带海拔高度的路线点。
- `base` 是该点投影到地面后的点。

计算方式：

```swift
let base = project(localX: x, localZ: z, visualHeight: 0)
let top = project(localX: x, localZ: z, visualHeight: height)
```

后续所有视觉元素都围绕 `top` 和 `base` 绘制。

## 自动适配画布

投影后，需要把所有 `top` 和 `base` 点适配到贴纸区域内。

推荐流程：

1. 用初始参数投影一遍。
2. 计算所有投影点的 bounds。
3. 根据目标内容区域计算 scale。
4. 把点整体平移并缩放到目标区域。

目标内容区域不要占满整张分享图，应该给统计文字和品牌留空间。

例如竖版分享图：

```swift
let stickerRect = CGRect(
    x: 40,
    y: imageHeight * 0.36,
    width: imageWidth - 80,
    height: imageHeight * 0.34
)
```

这样上方可以放标题或模板背景，下方可以放数据摘要。

## 绘制层级

建议按下面顺序绘制。

### 1. 背景

背景不属于这个渲染器的核心职责，可以由分享模板负责。

如果贴纸自己也需要背景，可以提供可选配置：

- 透明背景。
- 深色渐变背景。
- 运动照片背景。
- 纯色卡片背景。

第一版建议贴纸背景透明，交给分享页模板合成。

### 2. 地面投影

使用 `base` 点绘制一条低透明度路线：

```swift
context.setStrokeColor(style.shadowRouteColor.cgColor)
context.setLineWidth(style.baseLineWidth)
context.setAlpha(0.18)
context.addPath(basePath.cgPath)
context.strokePath()
```

这个投影能让用户理解路线在地面上的形状。

### 3. 半透明海拔幕布

对相邻点绘制四边形：

```swift
top[i] -> top[i + 1] -> base[i + 1] -> base[i]
```

填充半透明橙色：

```swift
context.setFillColor(style.curtainColor.withAlphaComponent(0.28).cgColor)
context.addPath(segmentCurtainPath.cgPath)
context.fillPath()
```

这是 Outbase 宣传图里最关键的视觉语言。

为了让层次更好，可以按路线顺序绘制所有幕布，并使用轻微透明度叠加。

### 4. 竖向高度线

每隔一定数量的点，从 `top` 到 `base` 画一条竖线：

```swift
for index in stride(from: 0, to: projectedPoints.count, by: verticalLineStride) {
    let point = projectedPoints[index]
    drawLine(from: point.top, to: point.base)
}
```

建议规则：

- 点数少于 100：每 4 个点画一条。
- 点数 100 到 400：每 8 到 12 个点画一条。
- 点数更多：固定最多 60 条竖线。

视觉参数：

- 宽度：1 到 2 pt。
- 透明度：0.18 到 0.35。
- 颜色：主色的浅色或同色高亮。

### 5. 顶部路线粗线

使用 `top` 点绘制主路线：

```swift
context.setStrokeColor(style.routeColor.cgColor)
context.setLineWidth(style.routeLineWidth)
context.setLineCap(.round)
context.setLineJoin(.round)
context.addPath(topPath.cgPath)
context.strokePath()
```

为了更接近宣传图，可以画两层：

1. 外层深橙色粗线。
2. 内层亮橙色细线。

示例：

```swift
draw(topPath, color: darkOrange, lineWidth: 8)
draw(topPath, color: brightOrange, lineWidth: 5)
```

### 6. 起点和终点

起点和终点可以使用白心圆加主题色描边：

```swift
drawMarker(at: projectedPoints.first?.top)
drawMarker(at: projectedPoints.last?.top)
```

为了避免视觉太乱，第一版可以只画终点，或者只画起终点。

### 7. 最高点

最高点是这个贴纸很有记忆感的标记。

```swift
let peakIndex = projectedPoints.indices.max {
    projectedPoints[$0].altitude < projectedPoints[$1].altitude
}
```

可以绘制：

- 小圆点。
- 小旗帜。
- “最高点 1234m”标签。

第一版建议只画小圆点，不画文字，避免和分享页文案抢注意力。

## 颜色和风格

参考 Outbase 宣传图，默认可以使用橙色体系：

```swift
struct RouteAltitudeStickerStyle {
    let routeColor: UIColor
    let routeInnerColor: UIColor
    let curtainColor: UIColor
    let verticalLineColor: UIColor
    let baseRouteColor: UIColor
    let markerFillColor: UIColor
    let markerStrokeColor: UIColor
}
```

推荐默认值：

- 主路线：`#FF6A00`
- 内层高亮：`#FF8A1C`
- 幕布：`#FF6A00`，alpha 0.25 到 0.35
- 竖线：`#FFB066`，alpha 0.25
- 地面投影：黑色或橙色，alpha 0.12 到 0.20
- 标记点：白色填充，橙色描边

Movinn 可以后续支持不同主题：

- 橙色攀爬风格。
- 白色极简风格。
- 荧光绿夜跑风格。
- 蓝色冷静地图风格。

但第一版只需要一个强识别样式。

## 渲染模块设计

建议拆成三个层次。

### RouteAltitudeStickerRenderer

负责纯渲染，输入数据和尺寸，输出图片：

```swift
enum RouteAltitudeStickerRenderer {
    static func image(
        input: RouteAltitudeStickerInput,
        size: CGSize,
        scale: CGFloat,
        style: RouteAltitudeStickerStyle
    ) -> UIImage?
}
```

优点：

- 不依赖 view 生命周期。
- 分享导出时可以直接使用。
- 后续视频逐帧渲染也方便。

### RouteAltitudeStickerView

负责在分享编辑页里预览：

```swift
final class RouteAltitudeStickerView: UIView {
    func configure(input: RouteAltitudeStickerInput, style: RouteAltitudeStickerStyle)
}
```

内部可以使用：

- `draw(_:)`
- 或者多个 `CAShapeLayer`

如果需要动态切换风格，`CAShapeLayer` 更方便。如果只是导出静态贴纸，`draw(_:)` 更简单。

第一版建议：

- 预览 view 用 `draw(_:)`。
- 导出图片复用同一套 layout 和 render 函数。

### RouteAltitudeStickerLayout

负责把 `RouteCoordinate` 转成投影点：

```swift
enum RouteAltitudeStickerLayout {
    static func projectedPoints(
        coordinates: [RouteCoordinate],
        in rect: CGRect,
        configuration: RouteAltitudeStickerLayoutConfiguration
    ) -> [RouteAltitudeStickerProjectedPoint]
}
```

这样渲染代码不会混入坐标转换逻辑。

## 核心类型草案

```swift
struct RouteAltitudeStickerLayoutConfiguration {
    let maxPointCount: Int
    let maxVisualHeightRatio: CGFloat
    let depthScale: CGFloat
    let angleScale: CGFloat
    let contentInsets: UIEdgeInsets
}

struct RouteAltitudeStickerProjectedPoint {
    let top: CGPoint
    let base: CGPoint
    let altitudeMeters: Double
    let progress: CGFloat
}

struct RouteAltitudeStickerStyle {
    let routeOuterColor: UIColor
    let routeInnerColor: UIColor
    let curtainColor: UIColor
    let verticalLineColor: UIColor
    let baseRouteColor: UIColor
    let markerFillColor: UIColor
    let markerStrokeColor: UIColor
    let routeOuterLineWidth: CGFloat
    let routeInnerLineWidth: CGFloat
    let verticalLineWidth: CGFloat
}
```

## 海拔缺失处理

不同来源的路线，海拔数据完整度不同。

推荐策略：

### 完整海拔

直接使用每个点的 `altitudeMeters`。

### 部分海拔缺失

使用线性插值：

```swift
for missingIndex in missingRange {
    let progress = Double(missingIndex - leftIndex) / Double(rightIndex - leftIndex)
    altitude = leftAltitude + (rightAltitude - leftAltitude) * progress
}
```

如果缺失点在开头或结尾：

- 开头缺失：使用第一个有效海拔。
- 结尾缺失：使用最后一个有效海拔。

### 完全没有海拔

第一版建议不展示该贴纸模板。

后续可以提供“平面立体贴纸”，但不要标注为海拔贴纸。

## 视觉高度控制

真实海拔范围不能直接映射到像素，否则不同路线差异会过大。

推荐使用相对高度加视觉限制：

```swift
let availableHeight = rect.height * 0.65
let maxVisualHeight = availableHeight * 0.75
let minVisualHeight: CGFloat = 24
```

如果海拔范围很小：

```swift
visualHeight = normalizedAltitude * max(maxVisualHeight, minVisualHeight)
```

如果海拔范围很大：

```swift
visualHeight = min(normalizedAltitude * maxVisualHeight, maxVisualHeight)
```

也可以加入非线性曲线，让低起伏路线更明显：

```swift
let eased = pow(normalizedAltitude, 0.85)
```

第一版建议不要做太复杂，先使用线性映射。

## 路线方向和构图

由于贴纸是视觉分享资产，不一定必须严格北向上。

可以考虑自动旋转路线，让它更好看：

1. 计算路线包围盒宽高。
2. 如果路线过于竖直，可以旋转一定角度。
3. 保证最终投影能最大化利用贴纸区域。

但第一版建议不要引入自动旋转，避免用户看到的路线方向和地图认知差异太大。

第一版策略：

- 保持原始地图方向。
- 使用等距投影制造斜视角。
- 通过适配 bounds 保证贴纸居中。

## 与分享页的结合

推荐把它作为分享页里的一个模板或贴纸组件：

- 模板名称：3D 海拔
- 入口位置：分享编辑页的模板选择区域
- 输出：`UIImage`

分享图结构可以是：

- 顶部：日期、地点或路线名称。
- 中部：3D 海拔贴纸。
- 底部：距离、爬升、移动时间。

如果当前分享页已有模块化布局，贴纸只需要暴露一张透明背景图片，由外层模板决定文字和背景。

## 视频和 Live Photo 扩展

第一版只做静态图。

后续如果要做动态效果，不一定要上 SceneKit，可以继续使用 2D 渲染逐帧生成：

### 路线生长动画

按 progress 截取 `topPath`：

- 0s：路线刚开始。
- 1s 到 2s：路线逐渐绘制完成。
- 2s 到 3s：幕布和数据淡入。

### 幕布上升动画

让每个点的高度从 0 动画到真实 `visualHeight`：

```swift
animatedHeight = visualHeight * animationProgress
```

这个效果会非常适合“每一次爬升都值得被展示”的产品表达。

### 相机轻微漂移

由于是 2D 投影，可以通过整体平移、缩放和轻微旋转制造动态感，不需要真 3D 相机。

这些帧可以接入现有 `RouteShareLivePhotoExporter` 的视频写入流程。

## 性能策略

### 降采样

不要用完整 GPS 点绘制贴纸。

建议：

- 静态图默认 500 点。
- 动态视频默认 300 点。
- 超长路线可以进一步降到 800 点以内。

### 合并相近点

投影后，如果相邻点屏幕距离过小，可以跳过：

```swift
if distance(projected[i].top, projected[lastKept].top) < 1 {
    continue
}
```

这样可以避免大量重叠线段。

### 避免逐段 layer

如果用 `CAShapeLayer`，不要每个幕布四边形一个 layer。

推荐：

- 主路线一个 layer。
- 地面投影一个 layer。
- 所有幕布合并成一个 `CGMutablePath`。
- 所有竖线合并成一个 `CGMutablePath`。

如果用 `draw(_:)`，直接在一次绘制里完成。

## 可能的实现文件

第一版可以新增：

- `PTrack/View/RouteAltitudeSticker/RouteAltitudeStickerRenderer.swift`
- `PTrack/View/RouteAltitudeSticker/RouteAltitudeStickerView.swift`
- `PTrack/View/RouteAltitudeSticker/RouteAltitudeStickerLayout.swift`
- `PTrack/View/RouteAltitudeSticker/RouteAltitudeStickerStyle.swift`

如果希望保持文件少一点，也可以先合并为：

- `PTrack/View/WorkoutRouteShare/RouteAltitudeStickerRenderer.swift`

后续复杂后再拆。

## MVP 实施步骤

### 第一步：纯渲染器

新增 `RouteAltitudeStickerRenderer`，输入路线点和尺寸，输出透明背景图片。

验收标准：

- 有海拔的路线能画出立体幕布。
- 起终点正常显示。
- 路线居中且不裁切。
- 没有海拔的路线返回 `nil`。

### 第二步：接入分享页预览

在分享页增加一个模板或模式，让用户选择“3D 海拔”。

验收标准：

- 能在分享预览中看到贴纸。
- 切换模板不会影响现有分享功能。
- 图片导出包含贴纸。

### 第三步：视觉打磨

增加：

- 双层路线描边。
- 竖向高度线。
- 最高点标记。
- 主题色配置。

验收标准：

- 弯曲路线可读。
- 长路线不糊成一团。
- 山地路线有明显起伏。
- 平缓路线不会夸张到失真。

### 第四步：动态扩展

如果后续要做 Live Photo 或视频：

- 路线生长。
- 幕布升起。
- 数据淡入。

验收标准：

- 动画帧率稳定。
- 导出耗时可接受。
- 和现有 Live Photo 导出链路兼容。

## 测试场景

需要准备几类路线测试：

- 爬升明显的山地路线。
- 海拔很平的城市跑步路线。
- 点数非常多的长距离路线。
- 只有少量点的短路线。
- 部分点缺失海拔的 GPX。
- 完全没有海拔的 GPX。
- 多段合并后有大间隔的路线。

重点检查：

- 贴纸是否裁切。
- 线路是否过密。
- 幕布是否反向或错位。
- 起点终点是否遮挡主路线。
- 海拔范围很小时是否仍然可读。
- 海拔范围很大时是否不会过度拉伸。

## 后续 SceneKit 版本

如果未来希望做真正的 3D 视图，可以再引入 `SceneKit`：

- 使用 `SCNView` 承载可旋转路线。
- 使用 `SCNGeometry` 构造 tube 或 ribbon。
- 使用 `SCNRenderer` 离屏导出图片或视频帧。
- 加入相机环绕动画。

但这应该是第二阶段，而不是第一阶段。

第一阶段的核心价值是快速做出 Outbase 宣传图这种“3D 海拔数据贴纸”效果，并且能稳定进入分享图导出链路。

## 总结

Movinn 的最佳落地路径是：

1. 把这个能力定义为“3D 海拔贴纸”，不是 3D 地图。
2. 使用 `CoreGraphics` 做 2.5D 投影绘制。
3. 复用现有 `RouteCoordinate.altitudeMeters` 和 `routeDetailCoordinates`。
4. 输出透明背景 `UIImage`，接入分享页模板。
5. 后续再扩展动态贴纸或 SceneKit 真 3D 版本。

这样实现成本低、包体影响小、性能可控，也更符合 Movinn “关注移动轨迹本身”的产品方向。
