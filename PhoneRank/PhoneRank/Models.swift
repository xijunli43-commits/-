import Foundation

enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    var text: String {
        switch self {
        case .string(let value): return value.isEmpty ? "未查证" : value
        case .number(let value): return value.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let value): return value ? "支持" : "不支持"
        case .array(let values): return values.map(\.text).joined(separator: " / ")
        default: return "未查证"
        }
    }
    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var array: [JSONValue] { if case .array(let value) = self { return value }; return [] }
    subscript(key: String) -> JSONValue {
        if case .object(let value) = self { return value[key] ?? .null }
        return .null
    }
}

struct DeviceRecord: Decodable, Identifiable {
    let fields: [String: JSONValue]
    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }
    var id: String {
        if case .number(let value)? = fields["id"] { return String(Int(value)) }
        return fields["id"]?.text ?? ""
    }
    var name: String { text("name") }
    func value(_ path: String) -> JSONValue {
        path.split(separator: ".").reduce(JSONValue.object(fields)) { $0[String($1)] }
    }
    func text(_ path: String) -> String { value(path).text }
    func number(_ path: String) -> Double? { value(path).number }
    var sources: [Source] {
        value("sources").array.compactMap { Source(label: $0["label"].text, rawURL: $0["url"].text) }
    }
    var shareText: String {
        "\(name)\n安兔兔：\(text("antutu.total"))\n\(text("platform") == "ios" ? "iOS" : "Android") · 原始数据快照，跑分仅供参考\n" + sources.map { "\($0.label)：\($0.url.absoluteString)" }.joined(separator: "\n")
    }
}

struct Source: Decodable, Identifiable {
    let label: String
    let url: URL
    var id: String { label + url.absoluteString }
    init?(label: String, rawURL: String) {
        guard let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        self.label = label
        self.url = url
    }
}

struct Catalog: Decodable {
    let generatedAt: String
    let methodology: [String]
    let sources: [Source]
    let phones: [DeviceRecord]
    let chips: [DeviceRecord]
    static func load() throws -> Catalog {
        guard let url = Bundle(for: BundleMarker.self).url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }
}
private final class BundleMarker: NSObject {}

enum SortMetric: String, CaseIterable, Identifiable {
    case total, cpu, gpu, mem, ux, gb6Single, gb6Multi, gb7Single, gb7Multi, weight, battery, size, refresh, release, process
    var id: String { rawValue }
    var title: String {
        switch self {
        case .total: "安兔兔总分"
        case .cpu: "安兔兔 CPU"
        case .gpu: "安兔兔 GPU"
        case .mem: "安兔兔 MEM"
        case .ux: "安兔兔 UX"
        case .gb6Single: "GB6 单核"
        case .gb6Multi: "GB6 多核"
        case .gb7Single: "GB7 单核"
        case .gb7Multi: "GB7 多核"
        case .weight: "重量（轻→重）"
        case .battery: "电池容量"
        case .size: "屏幕尺寸"
        case .refresh: "刷新率"
        case .release: "发布时间（新→旧）"
        case .process: "工艺节点（小→大）"
        }
    }
    func path(isChip: Bool = false) -> String {
        switch self {
        case .total, .cpu, .gpu, .mem, .ux: "antutu.\(rawValue)"
        case .gb6Single: isChip ? "gb6.single" : "geekbench.gb6.single"
        case .gb6Multi: isChip ? "gb6.multi" : "geekbench.gb6.multi"
        case .gb7Single: isChip ? "gb7.single" : "geekbench.gb7.single"
        case .gb7Multi: isChip ? "gb7.multi" : "geekbench.gb7.multi"
        case .weight: "body.weight"
        case .battery: "battery.capacity"
        case .size: "display.size"
        case .refresh: "display.refresh"
        case .release: "releaseDate"
        case .process: "process"
        }
    }
    static var phoneMetrics: [SortMetric] { allCases.filter { $0 != .process && $0 != .release } }
    static var chipMetrics: [SortMetric] { [.total, .cpu, .gpu, .gb6Single, .gb6Multi, .gb7Single, .gb7Multi, .release, .process] }
    func score(_ device: DeviceRecord, isChip: Bool) -> Double? {
        let path = path(isChip: isChip)
        if let value = device.number(path) { return value }
        let text = device.text(path)
        if self == .release { return Double(text.replacingOccurrences(of: "-", with: "")) }
        if self == .size || self == .process,
           let range = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) { return Double(text[range]) }
        return nil
    }
}

enum CatalogQuery {
    static func filter(_ devices: [DeviceRecord], query: String, platform: String = "all", brand: String = "all", category: String = "all") -> [DeviceRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return devices.filter { device in
            (platform == "all" || device.text("platform") == platform) &&
            (brand == "all" || device.text("brand") == brand) &&
            (category == "all" || device.text("category") == category) &&
            (query.isEmpty || ["name", "brand", "vendor", "soc.name", "soc.alias"].contains { device.text($0).localizedCaseInsensitiveContains(query) })
        }
    }
    static func sorted(_ devices: [DeviceRecord], by metric: SortMetric, isChip: Bool = false) -> [DeviceRecord] {
        devices.sorted {
            let left = metric.score($0, isChip: isChip), right = metric.score($1, isChip: isChip)
            switch (left, right) {
            case let (l?, r?) where l != r: return metric == .weight || metric == .process ? l < r : l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }
}
