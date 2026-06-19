# GPX Multi-File Merge Design

## 背景

后续希望支持把多段 GPX 轨迹合并成一条路线。

典型场景：

- 用户有两段活动轨迹 A 和 B。
- 希望 A 的终点直接连接到 B 的起点。
- 如果有更多段，则按顺序继续连接：A -> B -> C -> D。
- 即使 A 的终点和 B 的起点之间有空间间隔，也不做有效性验证，不做道路匹配，不做自动补路线，只把点按顺序拼起来。

这个功能的目标不是生成严格意义上的连续运动记录，而是让多个 GPX 文件可以被合并成一条 Movinn 路线，方便查看、导出和作为路书使用。

## 当前工程现状

### 单个 GPX 的解析

当前解析逻辑位于：

- `PTrack/Model/GPXRouteParser.swift`

`GPXRouteParser` 会解析：

- `<trkpt>`
- `<rtept>`
- `<ele>`
- `<time>`

并最终返回：

```swift
struct GPXParsedRoute {
    let title: String?
    let coordinates: [RouteCoordinate]
}
```

当前 parser 没有保留 `trkseg` 边界。只要 XML 中持续出现 `trkpt` 或 `rtept`，都会被追加到 `parsedPoints`，最后通过 `resolvedCoordinates()` 转成一维 `RouteCoordinate` 数组。

这意味着：

- 如果一个 GPX 文件内部有多个 `<trkseg>`，当前实现会自然拍平。
- 如果一个 GPX 文件内部有多个 `<trk>`，当前实现也会按 XML 出现顺序拍平。
- 拍平后，地图绘制时会把上一段终点和下一段起点直接连起来。

对于“直接合并，不做间隔验证”的目标，这个行为是有利的。

### 多个 GPX 的导入

当前多文件选择位于：

- `PTrack/View/RouteCollectionViewController.swift`

`presentGPXPicker()` 已经设置了：

```swift
documentPicker.allowsMultipleSelection = true
```

但 `importGPXFiles(at:)` 当前逻辑是逐个文件导入：

```swift
for url in urls {
    importedRoutes.append(try SharedRouteImportInbox.makeRoute(fromGPXAt: url))
}

if !importedRoutes.isEmpty {
    store.append(importedRoutes)
}
```

所以现在选择多个 GPX 的结果是生成多条独立路线，而不是合并成一条路线。

### 导出 GPX

当前导出逻辑位于：

- `PTrack/Model/GPXRouteExporter.swift`

导出器会把 `routeDetailCoordinates` 写成一个 `<trk>` 和一个 `<trkseg>`：

```xml
<trk>
  <name>...</name>
  <trkseg>
    <trkpt lat="..." lon="...">
      <ele>...</ele>
      <time>...</time>
    </trkpt>
  </trkseg>
</trk>
```

如果合并后的路线被保存为一维 `RouteCoordinate` 数组，当前 exporter 不需要特殊改造，也能导出成一条连续 GPX 轨迹。

## 结论

多段 GPX 合并可以用非常直接的方式实现：

1. 按指定顺序解析多个 GPX 文件。
2. 取出每个文件的 `coordinates`。
3. 按顺序 `append` 到一个数组里。
4. 用合并后的坐标数组创建一个新的 `TrackedWorkout`。
5. 保存到 `RouteCollectionStore`。

不需要做：

- 起终点距离校验。
- 时间连续性校验。
- 速度合理性校验。
- 路网匹配。
- 两段之间的插值补点。
- 两段之间的断线保留。

这种方案会让 A 的最后一个点和 B 的第一个点在地图上直接形成一条直线连接。

## 推荐行为

### 合并方式

推荐使用“拍平为一个 trkseg”的方式。

也就是合并后的数据在 Movinn 内部只是一条路线：

```swift
let mergedCoordinates = routeA.coordinates
    + routeB.coordinates
    + routeC.coordinates
```

合并后保存：

```swift
TrackedWorkout(
    routeCollectionID: UUID().uuidString,
    title: mergedTitle,
    sourceName: "GPX Merge",
    sourceURL: nil,
    importedAt: importedAt,
    coordinates: mergedCoordinates
)
```

这样可以复用现有路线详情、热图、路书和 GPX 导出能力。

### 为什么不用多个 trkseg

GPX 语义上可以用多个 `<trkseg>` 表示多个轨迹段。但这个方案不适合当前目标：

- 多个 `trkseg` 通常表示中间有中断。
- 很多 App 渲染多个 `trkseg` 时不会把段和段之间连起来。
- 用户现在明确希望 A 终点连接 B 起点。
- 当前 Movinn 数据模型没有保留 route segment 边界。

因此后续如果目标是“视觉上合并成一条线”，应直接拍平为一条 `trkseg`。

## 文件顺序

多文件合并最重要的问题是顺序。

### 推荐 MVP

MVP 可以提供一个明确入口，例如：

- “合并导入 GPX”
- “选择多个 GPX 并合并”

默认顺序建议：

1. 如果所有文件都有起始时间，按每个文件第一条轨迹点时间升序排列。
2. 如果部分文件没有时间，按文件名升序排列。
3. 如果 UI 后续支持排序，则以用户手动排序为准。

### 为什么不完全依赖 UIDocumentPicker 返回顺序

`UIDocumentPickerViewController` 支持多选，但返回的 URL 数组不应该被产品语义强依赖成“用户选择顺序”。

如果用户心里有明确 A -> B -> C 的顺序，长期方案最好提供一个合并确认页，展示文件列表并允许拖拽排序。

### 推荐长期交互

长期更稳的 UI：

1. 用户选择多个 GPX。
2. 进入“合并确认”页面。
3. 页面列出每个文件：
   - 文件名
   - 路线标题
   - 起点时间
   - 点数
   - 起终点大致位置
4. 用户可以拖拽调整顺序。
5. 点击“合并为一条路线”。

这样可以避免文件选择器顺序不稳定带来的误合并。

## 时间戳策略

当前 `RouteCoordinate` 必须有 `timestamp`。

`GPXRouteParser` 如果没有读到 `<time>`，会用 `fallbackDate + index` 补时间：

```swift
timestamp: point.timestamp ?? fallbackDate.addingTimeInterval(TimeInterval(index))
```

多文件合并时需要注意：如果每个文件都用同一个 `fallbackDate` 解析，而文件本身又没有时间，那么每个文件都会从相同时间开始补 timestamp，合并后的时间可能重复或不单调。

推荐策略：

- 解析第一个文件时使用 `importedAt`。
- 解析第二个文件时使用 `importedAt + 已合并点数`。
- 解析第三个文件时继续累加。

伪代码：

```swift
var mergedCoordinates: [RouteCoordinate] = []

for file in orderedFiles {
    let fallbackDate = importedAt.addingTimeInterval(TimeInterval(mergedCoordinates.count))
    let parsedRoute = try GPXRouteParser.parse(data: data, fallbackDate: fallbackDate)
    mergedCoordinates.append(contentsOf: parsedRoute.coordinates)
}
```

这个策略不校验真实时间，只是让缺失时间的 GPX 在合并后拥有更合理的 fallback timestamp。

如果 GPX 文件本身带真实 `<time>`，则保留原始时间，不强行重写。

## 距离策略

当前 route collection 的距离计算位于：

- `TrackedWorkout.routeCollectionDistanceMeters(for:)`

它会按坐标顺序逐点累加距离：

```swift
for coordinate in coordinates.dropFirst() {
    totalDistance += location.distance(from: previousLocation)
}
```

因此合并后：

- A 内部距离会被计入。
- A 终点到 B 起点之间的直线距离也会被计入。
- B 内部距离会被计入。

这符合“直接合并，A 终点连接 B 起点”的方案。

如果未来产品希望“视觉连接但统计距离不包含中间跳线”，就需要保留 segment 边界或给连接边打标记。但当前需求明确不做严格有效性验证，因此 MVP 不需要处理。

## 推荐新增组件

可以新增一个轻量合并器：

```swift
struct GPXRouteMergeSource {
    let fileURL: URL
    let title: String?
    let coordinates: [RouteCoordinate]
}

enum GPXRouteMerger {
    static func mergedRoute(
        from fileURLs: [URL],
        importedAt: Date = Date(),
        order: GPXRouteMergeOrder = .startTimeThenFileName
    ) throws -> GPXMergedRoute
}

struct GPXMergedRoute {
    let title: String
    let coordinates: [RouteCoordinate]
    let sourceCount: Int
}
```

也可以先不抽象类型，直接在 `SharedRouteImportInbox` 或 `RouteCollectionViewController` 内部实现一个私有方法。但考虑到分享扩展、文档选择器导入、未来批量工具都可能复用，单独放 `GPXRouteMerger` 更干净。

## 推荐导入 API

在 `SharedRouteImportInbox` 附近增加：

```swift
static func makeMergedRoute(
    fromGPXAt fileURLs: [URL],
    importedAt: Date = Date()
) throws -> TrackedWorkout
```

内部流程：

```swift
let mergedRoute = try GPXRouteMerger.mergedRoute(
    from: fileURLs,
    importedAt: importedAt
)

return TrackedWorkout(
    routeCollectionID: UUID().uuidString,
    title: mergedRoute.title,
    sourceName: "GPX Merge",
    sourceURL: nil,
    importedAt: importedAt,
    coordinates: mergedRoute.coordinates
)
```

## RouteCollectionViewController 接入建议

现有多选导入会生成多条路线。不要直接改掉这个行为，否则用户无法一次导入多条独立 GPX。

建议提供两个入口：

1. “导入 GPX”
   - 保持现有行为。
   - 选择多个文件时导入多条路线。

2. “合并导入 GPX”
   - 新增入口。
   - 选择多个文件时合并成一条路线。

这样产品语义更清楚，也不会破坏现有用户预期。

## 合并标题

推荐默认标题：

- 如果只有两个文件：`A + B`
- 如果超过两个文件：`A 等 N 段`
- 如果没有标题：`合并路线`

其中 `A/B` 优先使用 GPX 内部标题，其次使用文件名。

也可以在合并确认页允许用户手动修改。

## 错误处理

虽然不做起终点间隔验证，但仍然需要最基础的文件解析错误处理：

- 文件不是有效 XML：失败。
- 没有可用轨迹点：失败。
- 所有文件都失败：显示错误。
- 部分文件失败：MVP 建议整体失败，避免用户以为所有文件都已合并。

这里的“不要做有效性验证”应理解为不要验证两段是否真的连续，不是完全忽略文件损坏。

## 和自定义标签点的关系

如果未来同时支持 GPX 自定义标签点：

- 合并时可以把每个文件的 `routePointTags` 一起 append。
- 每个标签点的 `routeDistanceMeters` 需要重新计算或增加偏移。
- 如果标签点只存经纬度，合并时可以不处理，导入后按坐标显示即可。

推荐先实现纯轨迹点合并，再处理标签点合并。

## 测试要点

### 基础合并

- A + B 合并后只有一条 route collection 路线。
- 合并后坐标数量等于 A 点数 + B 点数。
- 地图上 A 终点和 B 起点之间出现直接连线。
- 导出合并路线后，GPX 是一个 `<trk>` 和一个 `<trkseg>`。

### 多段合并

- A + B + C 按顺序合并。
- 每一段之间都直接连线。
- 不因为 A/B/C 之间距离很远而失败。

### 时间戳

- 带真实 `<time>` 的 GPX 保留原时间。
- 不带 `<time>` 的 GPX 合并后 fallback timestamp 尽量单调。
- 不因为时间倒序而失败。

### 现有行为回归

- 普通“导入 GPX”多选仍然导入多条独立路线。
- 单个 GPX 导入行为不变。
- 路线详情页展示、热图、路书、GPX 导出都能正常使用合并路线。

## 暂不实现时的记录

当前阶段只保留设计结论，不实现多文件合并功能。

后续实现建议顺序：

1. 新增 `GPXRouteMerger`。
2. 新增 `SharedRouteImportInbox.makeMergedRoute(fromGPXAt:)`。
3. 在路线收藏页增加“合并导入 GPX”入口。
4. MVP 先按时间或文件名排序。
5. 后续再做合并确认页和手动排序。

这条路线能最大程度复用现有 GPX parser、route collection 存储、地图展示和 GPX exporter，改动范围较小。
