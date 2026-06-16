//
//  CoordinateRegionManager.swift
//  PTrack
//
//  Created by Codex on 2026/6/16.
//

import CoreLocation
import Foundation

struct CoordinateRegionResult: Equatable {
    let countryCode: String?
    let countryName: String?
    let provinceName: String?
    let cityName: String?
    let districtName: String?
    let adcode: Int?
    let isChina: Bool
    let isMainlandChina: Bool

    var title: String? {
        [
            districtName,
            cityName,
            provinceName,
            countryName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }
}

final class CoordinateRegionManager {
    static let shared = CoordinateRegionManager()

    private var chinaIndex: GeoBoundaryIndex?
    private var worldIndex: GeoBoundaryIndex?
    private let loadingLock = NSLock()

    private init() {}

    func region(for coordinate: CLLocationCoordinate2D) -> CoordinateRegionResult? {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        if Self.mightBeInChinaDataBounds(coordinate),
           let chinaRegion = chinaRegion(for: coordinate) {
            return chinaRegion
        }

        return worldRegion(for: coordinate)
    }

    func isCoordinateInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard CLLocationCoordinate2DIsValid(coordinate),
              Self.mightBeInChinaDataBounds(coordinate),
              let chinaRegion = chinaRegion(for: coordinate) else {
            return false
        }

        return chinaRegion.isMainlandChina
    }

    private func chinaRegion(for coordinate: CLLocationCoordinate2D) -> CoordinateRegionResult? {
        guard let feature = loadChinaIndex()?.feature(containing: coordinate),
              let adcode = feature.adcode else {
            return nil
        }

        let provinceCode = provinceCode(for: adcode, parentAdcode: feature.parentAdcode)
        let provinceName = Self.chinaProvinceNames[provinceCode]
        let isDirectAdmin = Self.directAdminProvinceCodes.contains(provinceCode)
        let level = feature.level
        let cityName: String?
        let districtName: String?

        switch level {
        case .district:
            cityName = isDirectAdmin ? provinceName : nil
            districtName = feature.name
        case .city:
            cityName = feature.name
            districtName = nil
        case .province:
            cityName = nil
            districtName = nil
        case .none:
            cityName = feature.name.isEmpty ? nil : feature.name
            districtName = nil
        }

        let isMainlandChina = adcode != 710000
        return CoordinateRegionResult(
            countryCode: "CN",
            countryName: Self.localizedChinaName(),
            provinceName: provinceName ?? (level == .province ? feature.name : nil),
            cityName: cityName,
            districtName: districtName,
            adcode: adcode,
            isChina: true,
            isMainlandChina: isMainlandChina
        )
    }

    private func worldRegion(for coordinate: CLLocationCoordinate2D) -> CoordinateRegionResult? {
        guard let feature = loadWorldIndex()?.feature(containing: coordinate) else {
            return nil
        }

        let countryCode = feature.countryCode
        let countryName = feature.localizedName
        let isChina = countryCode == "CN" || countryCode == "CHN" || feature.name == "China"

        return CoordinateRegionResult(
            countryCode: countryCode,
            countryName: countryName,
            provinceName: nil,
            cityName: nil,
            districtName: nil,
            adcode: nil,
            isChina: isChina,
            isMainlandChina: false
        )
    }

    private func loadChinaIndex() -> GeoBoundaryIndex? {
        loadingLock.lock()
        defer {
            loadingLock.unlock()
        }

        if let chinaIndex {
            return chinaIndex
        }

        let loadedIndex = GeoBoundaryIndex.load(
            resourceName: "china_detail",
            featureKind: .china
        )
        chinaIndex = loadedIndex
        return loadedIndex
    }

    private func loadWorldIndex() -> GeoBoundaryIndex? {
        loadingLock.lock()
        defer {
            loadingLock.unlock()
        }

        if let worldIndex {
            return worldIndex
        }

        let loadedIndex = GeoBoundaryIndex.load(
            resourceName: "world",
            featureKind: .world
        )
        worldIndex = loadedIndex
        return loadedIndex
    }

    private func provinceCode(for adcode: Int, parentAdcode: Int?) -> Int {
        let directProvinceCode = adcode / 10_000 * 10_000
        if Self.chinaProvinceNames[directProvinceCode] != nil {
            return directProvinceCode
        }

        if let parentAdcode {
            return parentAdcode / 10_000 * 10_000
        }

        return directProvinceCode
    }

    private static func mightBeInChinaDataBounds(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude >= 72
            && coordinate.longitude <= 136
            && coordinate.latitude >= 3
            && coordinate.latitude <= 54
    }

    private static func localizedChinaName() -> String {
        switch AppLanguageStore.shared.language {
        case .chinese:
            return "中国"
        case .japanese:
            return "中国"
        case .korean:
            return "중국"
        case .english:
            return "China"
        }
    }

    private static let directAdminProvinceCodes: Set<Int> = [
        110000,
        120000,
        310000,
        500000
    ]

    private static let chinaProvinceNames: [Int: String] = [
        110000: "北京市",
        120000: "天津市",
        130000: "河北省",
        140000: "山西省",
        150000: "内蒙古自治区",
        210000: "辽宁省",
        220000: "吉林省",
        230000: "黑龙江省",
        310000: "上海市",
        320000: "江苏省",
        330000: "浙江省",
        340000: "安徽省",
        350000: "福建省",
        360000: "江西省",
        370000: "山东省",
        410000: "河南省",
        420000: "湖北省",
        430000: "湖南省",
        440000: "广东省",
        450000: "广西壮族自治区",
        460000: "海南省",
        500000: "重庆市",
        510000: "四川省",
        520000: "贵州省",
        530000: "云南省",
        540000: "西藏自治区",
        610000: "陕西省",
        620000: "甘肃省",
        630000: "青海省",
        640000: "宁夏回族自治区",
        650000: "新疆维吾尔自治区",
        710000: "台湾省",
        810000: "香港特别行政区",
        820000: "澳门特别行政区"
    ]
}

private enum GeoBoundaryFeatureKind {
    case china
    case world
}

private enum GeoAdministrativeLevel: Int {
    case province = 1
    case city = 2
    case district = 3

    init?(rawValue: String?) {
        switch rawValue {
        case "province":
            self = .province
        case "city":
            self = .city
        case "district":
            self = .district
        default:
            return nil
        }
    }
}

private struct GeoBoundaryIndex {
    let features: [GeoBoundaryFeature]

    static func load(
        resourceName: String,
        featureKind: GeoBoundaryFeatureKind
    ) -> GeoBoundaryIndex? {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "Data"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data) else {
            return nil
        }

        let features = collection.features.compactMap {
            GeoBoundaryFeature(feature: $0, featureKind: featureKind)
        }
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }

            return lhs.boundingBox.area < rhs.boundingBox.area
        }

        return GeoBoundaryIndex(features: features)
    }

    func feature(containing coordinate: CLLocationCoordinate2D) -> GeoBoundaryFeature? {
        let point = GeoPoint(
            longitude: coordinate.longitude,
            latitude: coordinate.latitude
        )

        return features.first { feature in
            feature.contains(point)
        }
    }
}

private struct GeoBoundaryFeature {
    let name: String
    let localizedNames: GeoLocalizedNames
    let level: GeoAdministrativeLevel?
    let adcode: Int?
    let parentAdcode: Int?
    let countryCode: String?
    let polygons: [GeoPolygon]
    let boundingBox: GeoBoundingBox
    let priority: Int

    init?(feature: GeoJSONFeature, featureKind: GeoBoundaryFeatureKind) {
        guard let geometry = feature.geometry,
              !geometry.polygons.isEmpty,
              let boundingBox = GeoBoundingBox(polygons: geometry.polygons) else {
            return nil
        }

        name = feature.properties.name ?? ""
        localizedNames = feature.properties.localizedNames
        level = GeoAdministrativeLevel(rawValue: feature.properties.level)
        adcode = feature.properties.adcode
        parentAdcode = feature.properties.parentAdcode
        countryCode = feature.properties.isoA2 ?? feature.properties.isoA3
        polygons = geometry.polygons
        self.boundingBox = boundingBox

        switch featureKind {
        case .china:
            priority = (level?.rawValue ?? 0) * 1_000 - Int(boundingBox.area.rounded())
        case .world:
            priority = 0
        }
    }

    func contains(_ point: GeoPoint) -> Bool {
        guard boundingBox.contains(point) else {
            return false
        }

        return polygons.contains { $0.contains(point) }
    }

    var localizedName: String? {
        localizedNames.localizedName(fallback: name)
    }
}

private struct GeoJSONFeatureCollection: Decodable {
    let features: [GeoJSONFeature]
}

private struct GeoJSONFeature: Decodable {
    let properties: GeoJSONProperties
    let geometry: GeoJSONGeometry?

    private enum CodingKeys: String, CodingKey {
        case properties
        case geometry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        properties = (try? container.decode(GeoJSONProperties.self, forKey: .properties)) ?? GeoJSONProperties()
        geometry = try? container.decode(GeoJSONGeometry.self, forKey: .geometry)
    }
}

private struct GeoJSONProperties: Decodable {
    let name: String?
    let nameEnglish: String?
    let nameChinese: String?
    let nameJapanese: String?
    let nameKorean: String?
    let level: String?
    let adcode: Int?
    let parentAdcode: Int?
    let isoA2: String?
    let isoA3: String?

    var localizedNames: GeoLocalizedNames {
        GeoLocalizedNames(
            fallbackName: name,
            englishName: nameEnglish,
            chineseName: nameChinese,
            japaneseName: nameJapanese,
            koreanName: nameKorean
        )
    }
}

private struct GeoLocalizedNames {
    let fallbackName: String?
    let englishName: String?
    let chineseName: String?
    let japaneseName: String?
    let koreanName: String?

    func localizedName(fallback: String?) -> String? {
        switch AppLanguageStore.shared.language {
        case .chinese:
            return chineseName ?? englishName ?? fallbackName ?? fallback
        case .japanese:
            return japaneseName ?? englishName ?? fallbackName ?? fallback
        case .korean:
            return koreanName ?? englishName ?? fallbackName ?? fallback
        case .english:
            return englishName ?? fallbackName ?? fallback
        }
    }
}

private extension GeoJSONProperties {
    init() {
        name = nil
        nameEnglish = nil
        nameChinese = nil
        nameJapanese = nil
        nameKorean = nil
        level = nil
        adcode = nil
        parentAdcode = nil
        isoA2 = nil
        isoA3 = nil
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case nameEnglish = "name_en"
        case nameChinese = "name_zh"
        case nameJapanese = "name_ja"
        case nameKorean = "name_ko"
        case level
        case adcode
        case parent
        case isoA2 = "iso_a2"
        case isoA3 = "iso_a3"
    }

    private enum ParentCodingKeys: String, CodingKey {
        case adcode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameEnglish = try container.decodeIfPresent(String.self, forKey: .nameEnglish)
        nameChinese = try container.decodeIfPresent(String.self, forKey: .nameChinese)
        nameJapanese = try container.decodeIfPresent(String.self, forKey: .nameJapanese)
        nameKorean = try container.decodeIfPresent(String.self, forKey: .nameKorean)

        if let stringLevel = try? container.decodeIfPresent(String.self, forKey: .level) {
            level = stringLevel
        } else if let integerLevel = try? container.decodeIfPresent(Int.self, forKey: .level) {
            level = String(integerLevel)
        } else {
            level = nil
        }

        adcode = Self.flexibleIntValue(in: container, forKey: .adcode)
        isoA2 = try container.decodeIfPresent(String.self, forKey: .isoA2)
        isoA3 = try container.decodeIfPresent(String.self, forKey: .isoA3)

        if let parentContainer = try? container.nestedContainer(
            keyedBy: ParentCodingKeys.self,
            forKey: .parent
        ) {
            parentAdcode = Self.flexibleIntValue(in: parentContainer, forKey: .adcode)
        } else {
            parentAdcode = nil
        }
    }

    private static func flexibleIntValue<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let integerValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return integerValue
        }

        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        return nil
    }
}

private struct GeoJSONGeometry: Decodable {
    let polygons: [GeoPolygon]

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "Polygon":
            let coordinateGroups = try container.decode([[[Double]]].self, forKey: .coordinates)
            polygons = [GeoPolygon(rawRings: coordinateGroups)].compactMap { $0 }
        case "MultiPolygon":
            let coordinateGroups = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            polygons = coordinateGroups.compactMap(GeoPolygon.init(rawRings:))
        default:
            polygons = []
        }
    }
}

private struct GeoPolygon {
    let rings: [GeoRing]
    let boundingBox: GeoBoundingBox

    init?(rawRings: [[[Double]]]) {
        let rings = rawRings.compactMap(GeoRing.init(rawCoordinates:))
        guard !rings.isEmpty,
              let boundingBox = GeoBoundingBox(rings: rings) else {
            return nil
        }

        self.rings = rings
        self.boundingBox = boundingBox
    }

    func contains(_ point: GeoPoint) -> Bool {
        guard boundingBox.contains(point),
              let outerRing = rings.first,
              outerRing.contains(point) else {
            return false
        }

        return !rings.dropFirst().contains { $0.contains(point) }
    }
}

private struct GeoRing {
    let points: [GeoPoint]
    let boundingBox: GeoBoundingBox

    init?(rawCoordinates: [[Double]]) {
        let points = rawCoordinates.compactMap { rawCoordinate -> GeoPoint? in
            guard rawCoordinate.count >= 2 else {
                return nil
            }

            return GeoPoint(
                longitude: rawCoordinate[0],
                latitude: rawCoordinate[1]
            )
        }

        guard points.count >= 3,
              let boundingBox = GeoBoundingBox(points: points) else {
            return nil
        }

        self.points = points
        self.boundingBox = boundingBox
    }

    func contains(_ point: GeoPoint) -> Bool {
        guard boundingBox.contains(point) else {
            return false
        }

        var isInside = false
        var previousIndex = points.count - 1

        for currentIndex in points.indices {
            let current = points[currentIndex]
            let previous = points[previousIndex]

            if point.isOnSegment(from: previous, to: current) {
                return true
            }

            let latitudeIntersects = (current.latitude > point.latitude) != (previous.latitude > point.latitude)
            if latitudeIntersects {
                let longitudeAtLatitude = (previous.longitude - current.longitude)
                    * (point.latitude - current.latitude)
                    / (previous.latitude - current.latitude)
                    + current.longitude

                if point.longitude < longitudeAtLatitude {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }
}

private struct GeoPoint {
    let longitude: Double
    let latitude: Double

    func isOnSegment(from start: GeoPoint, to end: GeoPoint) -> Bool {
        let epsilon = 1e-10
        let crossProduct = (latitude - start.latitude) * (end.longitude - start.longitude)
            - (longitude - start.longitude) * (end.latitude - start.latitude)
        guard abs(crossProduct) <= epsilon else {
            return false
        }

        let minLongitude = min(start.longitude, end.longitude) - epsilon
        let maxLongitude = max(start.longitude, end.longitude) + epsilon
        let minLatitude = min(start.latitude, end.latitude) - epsilon
        let maxLatitude = max(start.latitude, end.latitude) + epsilon

        return longitude >= minLongitude
            && longitude <= maxLongitude
            && latitude >= minLatitude
            && latitude <= maxLatitude
    }
}

private struct GeoBoundingBox {
    let minLongitude: Double
    let minLatitude: Double
    let maxLongitude: Double
    let maxLatitude: Double

    var area: Double {
        max(maxLongitude - minLongitude, 0) * max(maxLatitude - minLatitude, 0)
    }

    init?(points: [GeoPoint]) {
        guard let firstPoint = points.first else {
            return nil
        }

        var minLongitude = firstPoint.longitude
        var minLatitude = firstPoint.latitude
        var maxLongitude = firstPoint.longitude
        var maxLatitude = firstPoint.latitude

        for point in points.dropFirst() {
            minLongitude = min(minLongitude, point.longitude)
            minLatitude = min(minLatitude, point.latitude)
            maxLongitude = max(maxLongitude, point.longitude)
            maxLatitude = max(maxLatitude, point.latitude)
        }

        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    init?(rings: [GeoRing]) {
        guard let firstBox = rings.first?.boundingBox else {
            return nil
        }

        self = rings.dropFirst().reduce(firstBox) { partialResult, ring in
            partialResult.union(ring.boundingBox)
        }
    }

    init?(polygons: [GeoPolygon]) {
        guard let firstBox = polygons.first?.boundingBox else {
            return nil
        }

        self = polygons.dropFirst().reduce(firstBox) { partialResult, polygon in
            partialResult.union(polygon.boundingBox)
        }
    }

    func contains(_ point: GeoPoint) -> Bool {
        point.longitude >= minLongitude
            && point.longitude <= maxLongitude
            && point.latitude >= minLatitude
            && point.latitude <= maxLatitude
    }

    private func union(_ other: GeoBoundingBox) -> GeoBoundingBox {
        GeoBoundingBox(
            minLongitude: min(minLongitude, other.minLongitude),
            minLatitude: min(minLatitude, other.minLatitude),
            maxLongitude: max(maxLongitude, other.maxLongitude),
            maxLatitude: max(maxLatitude, other.maxLatitude)
        )
    }

    private init(
        minLongitude: Double,
        minLatitude: Double,
        maxLongitude: Double,
        maxLatitude: Double
    ) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }
}
