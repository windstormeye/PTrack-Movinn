# GPX Custom Route Point Design

## 背景

Movinn 后续希望在轨迹详情页里支持用户添加自定义标签点，例如：

- 补水点
- 拍照点
- 休息点
- 风景点
- 危险点
- 自定义备注点

这些点本质上是用户对一条轨迹的私人标注。由于当前没有服务端，用户之间传递带标注的路线时，需要依赖文件传输。

GPX 已经是工程里现有的路线导入/导出格式，因此最自然的方案是在 GPX 文件中写入带 GPS 坐标的 Movinn 自定义字段。其他 App 不需要理解这些字段，Movinn 自己能完整解析即可。

## 当前工程现状

### GPX 导出

当前导出逻辑位于：

- `PTrack/Model/GPXRouteExporter.swift`
- `PTrack/View/WorkoutRouteDetailViewController.swift`

`GPXRouteExporter.data(routeName:coordinates:)` 现在会手写生成 GPX XML：

- `<metadata>`
- `<trk>`
- `<trkseg>`
- `<trkpt lat="..." lon="...">`
- `<ele>`
- `<time>`

导出入口在轨迹详情页中：

```swift
let routeName = AppLocalization.text(.gpxExportRouteName)
let coordinates = workout.routeDetailCoordinates
let fileName = GPXRouteExporter.suggestedFileName(routeName: routeName)

let data = try GPXRouteExporter.data(
    routeName: routeName,
    coordinates: coordinates
)
```

这说明当前导出结构很轻，新增自定义节点不需要替换底层库。

### GPX 导入

当前导入逻辑位于：

- `PTrack/Model/GPXRouteParser.swift`
- `PTrack/Manager/RouteCollectionStore.swift`

`GPXRouteParser` 基于 `XMLParser`，目前只解析：

- 路线标题：`<name>`
- 轨迹点：`<trkpt>`
- 路线点：`<rtept>`
- 海拔：`<ele>`
- 时间：`<time>`

导入 GPX 后会生成 `GPXParsedRoute`：

```swift
struct GPXParsedRoute {
    let title: String?
    let coordinates: [RouteCoordinate]
}
```

随后 `SharedRouteImportInbox.makeRoute(fromGPXAt:)` 会把它转成 `TrackedWorkout`：

```swift
return TrackedWorkout(
    routeCollectionID: UUID().uuidString,
    title: parsedRoute.title?.nilIfBlank ?? fallbackTitle,
    sourceName: "GPX",
    sourceURL: fileURL,
    importedAt: importedAt,
    coordinates: parsedRoute.coordinates
)
```

### 本地存储与 iCloud 同步

导入路线会被保存为 `TrackedWorkout` JSON：

- `RouteCollectionStore.save(_:)`
- `RouteCollectionCloudSyncStore.upsert(routes:)`

这点很关键：只要自定义标签点成为 `TrackedWorkout` 的可选 `Codable` 字段，本地缓存和 iCloud route collection 同步都可以顺带保留它。

Swift `Codable` 对新增可选字段比较友好，因此可以做成向后兼容的迁移。

## 结论

这个功能可以做，而且和现有工程结构匹配度很高。

推荐方案是：

- 用 GPX 标准 `<wpt>` 承载带 GPS 坐标的标签点。
- 用 Movinn 自定义 XML namespace 在 `<extensions>` 中保存完整语义。
- 在 Movinn 内部用 `RoutePointTag` 之类的模型保存这些点。
- 导出 GPX 时写入 `<wpt>`。
- 导入 GPX 时解析 `<wpt>` 和 `movinn:*` 扩展字段。

## 为什么推荐 wpt

GPX 里常见的点类型有三类：

- `<trkpt>`：轨迹运动过程中的连续点。
- `<rtept>`：路线规划中的路径点。
- `<wpt>`：独立航点或标记点。

Movinn 的补水点、拍照点、备注点不是连续轨迹的一部分，也不是路线本体的采样点，更像用户放在地图上的独立标记。因此更适合用 `<wpt>`。

这样还有一个兼容性收益：其他 App 即使不解析 Movinn 自定义字段，也可能至少把它显示成普通航点。

## 推荐 GPX 结构

示例：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx
  version="1.1"
  creator="Movinn"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:movinn="https://pj.studio/movinn/gpx/1">
  <metadata>
    <name>来自 Movinn 的路线</name>
    <time>2026-06-19T10:00:00Z</time>
  </metadata>

  <wpt lat="31.23041600" lon="121.47370100">
    <name>补水点</name>
    <type>hydration</type>
    <desc>便利店门口可以补水</desc>
    <extensions>
      <movinn:point
        id="4E0D8C08-1E8C-46F7-9DF8-9BB7155C0E22"
        kind="hydration"
        icon="drop"
        routeDistanceMeters="3250.50"
        createdAt="2026-06-19T10:00:00Z" />
    </extensions>
  </wpt>

  <wpt lat="31.23200000" lon="121.47600000">
    <name>拍照点</name>
    <type>photo</type>
    <extensions>
      <movinn:point
        id="9A3C7BA7-44FA-4E06-824C-43F3A1270DA3"
        kind="photo"
        icon="camera"
        routeDistanceMeters="4720.00"
        createdAt="2026-06-19T10:06:00Z" />
    </extensions>
  </wpt>

  <trk>
    <name>来自 Movinn 的路线</name>
    <trkseg>
      <trkpt lat="31.22800000" lon="121.47000000">
        <ele>12.00</ele>
        <time>2026-06-19T09:30:00Z</time>
      </trkpt>
      <trkpt lat="31.22900000" lon="121.47100000">
        <ele>13.00</ele>
        <time>2026-06-19T09:31:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>
```

## 推荐数据模型

后续可以新增模型：

```swift
struct RoutePointTag: Codable, Hashable {
    let id: String
    let kind: RoutePointTagKind
    let title: String
    let note: String?
    let latitude: Double
    let longitude: Double
    let routeDistanceMeters: Double?
    let createdAt: Date
    let iconName: String?
}

enum RoutePointTagKind: String, Codable, CaseIterable {
    case hydration
    case photo
    case rest
    case scenery
    case warning
    case custom
}
```

然后在 `TrackedWorkout` 中增加：

```swift
let routePointTags: [RoutePointTag]?
```

对于 `RouteCoordinate`，不建议直接把标签点塞进去。路线点和用户标签点是两种不同语义：

- `RouteCoordinate` 表示轨迹本体。
- `RoutePointTag` 表示用户对轨迹的标注。

保持分离后，导出、地图显示、编辑和同步都会更清晰。

## Parser 需要注意的问题

### 1. 当前 name 解析逻辑需要收紧

当前 `GPXRouteParserDelegate.didEndElement` 里：

```swift
case "name":
    if title == nil, currentPoint == nil, !value.isEmpty {
        title = value
    }
```

如果后续支持 `<wpt><name>补水点</name></wpt>`，这段逻辑可能误把第一个标签点名称当成路线标题。

需要改为根据 `elementStack` 判断上下文，例如：

- `gpx > metadata > name` 可以作为 route title。
- `gpx > trk > name` 可以作为 route title。
- `gpx > wpt > name` 应该写入当前 waypoint title。

### 2. XML namespace 不要影响解析

当前 `normalizedElementName(_:)` 会把 `movinn:point` 归一化成 `point`：

```swift
private func normalizedElementName(_ name: String) -> String {
    name.split(separator: ":").last.map(String.init) ?? name
}
```

这对解析自定义字段是有利的，但如果后续同名扩展变多，最好同时检查 `namespaceURI` 或 `qualifiedName`，避免把其他 App 的 `<foo:point>` 当成 Movinn 自定义点。

### 3. routeDistanceMeters 是辅助字段

`routeDistanceMeters` 可以让 UI 直接知道标签点大概在路线的哪个进度位置，但它不应该成为唯一依据。

导入时如果缺失或不可信，可以根据标签点坐标重新计算它到轨迹最近点的距离进度。

## Exporter 改造建议

把当前方法：

```swift
static func data(
    routeName: String,
    coordinates routeCoordinates: [RouteCoordinate]
) throws -> Data
```

扩展为：

```swift
static func data(
    routeName: String,
    coordinates routeCoordinates: [RouteCoordinate],
    routePointTags: [RoutePointTag] = []
) throws -> Data
```

导出顺序建议：

1. XML header
2. `<gpx>` root，增加 `xmlns:movinn`
3. `<metadata>`
4. 所有 `<wpt>`
5. `<trk>`
6. `</gpx>`

把 `<wpt>` 放在 `<trk>` 前面更常见，也方便流式读文件时先拿到标签点。

## Importer 改造建议

`GPXParsedRoute` 改为：

```swift
struct GPXParsedRoute {
    let title: String?
    let coordinates: [RouteCoordinate]
    let routePointTags: [RoutePointTag]
}
```

`GPXRouteParserDelegate` 增加：

- `currentWaypoint`
- `parsedWaypoints`
- waypoint 的 `name`
- waypoint 的 `desc`
- waypoint 的 `type`
- `movinn:point` 的 attributes

`SharedRouteImportInbox.makeRoute(fromGPXAt:)` 需要把解析出来的标签点传入 `TrackedWorkout` 的 route collection init。

## 详情页 UI 接入建议

工程里已有地图标注模式：

- `RouteMediaAnnotation`
- `RouteMediaAnnotationView`
- `WorkoutRouteDetailViewController+MKMapViewDelegate`

后续可以照这个模式新增：

- `RoutePointTagAnnotation`
- `RoutePointTagAnnotationView`

展示策略：

- 补水点：水滴图标
- 拍照点：相机图标
- 休息点：椅子或 pause 图标
- 风险点：感叹号图标
- 自定义点：圆点或 pin 图标

交互策略：

- 点按 annotation 显示编辑/查看面板。
- 长按地图或长按轨迹添加点。
- 添加点时自动吸附到最近轨迹点，并计算 `routeDistanceMeters`。

## 兼容性

### Movinn 到 Movinn

完整可控。

只要导出和导入都按 Movinn 自定义 namespace 处理，就能完整还原：

- 点类型
- 标题
- 备注
- 图标
- 坐标
- 轨迹进度
- 创建时间

### Movinn 到其他 App

部分兼容。

其他 App 大概率不理解 `movinn:*` 扩展字段，但可能显示 `<wpt>` 的：

- 坐标
- name
- desc
- type

也可能完全忽略 waypoint，这取决于对方 App。

### 其他 App 再导出回 Movinn

不可靠。

如果用户把 Movinn GPX 先导入别的 App，再从别的 App 重新导出，`extensions` 很可能被对方丢弃。

因此产品上应避免承诺“经过任意第三方 App 中转后仍保留标签点”。

## 安全与隐私

自定义标签点可能包含更敏感的位置，例如：

- 家附近的补给点
- 住处附近的起终点备注
- 私人拍照地点
- 自定义备注文字

如果后续提供 GPX 分享，需要考虑：

- 分享前是否提示包含自定义标签点。
- 是否提供“仅导出轨迹，不导出标签点”。
- 是否复用起终点隐私裁剪逻辑。
- 是否支持删除备注文字，只保留点类型。

## 测试要点

### 导出测试

- 没有标签点时，导出的 GPX 和当前行为一致。
- 有标签点时，GPX 中包含 `<wpt>`。
- 标签点标题、备注里的 XML 特殊字符会被正确 escape。
- `lat/lon/routeDistanceMeters` 使用 `en_US_POSIX` 格式，避免小数点受系统语言影响。

### 导入测试

- 可以导入 Movinn 自己导出的标签点。
- 可以导入没有 `extensions` 的普通 `<wpt>`。
- `<wpt><name>` 不会污染路线标题。
- `movinn:point` 缺少部分字段时不会导致整条 GPX 导入失败。
- 非 Movinn namespace 的扩展字段会被忽略。

### 回归测试

- 旧 GPX 仍能导入。
- 旧本地 route collection JSON 仍能 decode。
- Apple Health 和 Strava 来源的 `TrackedWorkout` 不受影响。
- iCloud route collection 同步可以保留标签点。

## 暂不实现时的记录

当前阶段暂不写自定义 GPX 文件功能，只保留这份设计结论。

后续真正开始实现时，建议优先顺序是：

1. 新增 `RoutePointTag` 模型。
2. 给 `TrackedWorkout` 增加可选 `routePointTags`。
3. 改造 GPX exporter，先做到 Movinn 标签点导出。
4. 改造 GPX parser，支持 Movinn 标签点导入。
5. 在轨迹详情页显示标签点 annotation。
6. 再做添加、编辑、删除标签点的 UI。

这样可以先把文件协议和数据链路打通，再逐步补齐完整编辑体验。
