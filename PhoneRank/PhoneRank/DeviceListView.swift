import SwiftUI

enum ListMode { case phones, chips, favorites }

struct DeviceListView: View {
    let catalog: Catalog
    let mode: ListMode
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var platform = "android"
    @State private var brand = "all"
    @State private var category = "all"
    @State private var metric: SortMetric = .total
    @State private var showLimit = false
    private var isChip: Bool { mode == .chips }
    private var title: String { isChip ? "芯片资料库" : mode == .favorites ? "我的收藏" : "手机排行" }
    private var records: [DeviceRecord] {
        let all = isChip ? catalog.chips : catalog.phones
        let saved = mode == .favorites ? all.filter { library.favorites.contains($0.id) } : all
        return CatalogQuery.sorted(CatalogQuery.filter(saved, query: query, platform: isChip || mode == .favorites ? "all" : platform, brand: isChip ? "all" : brand, category: category), by: metric, isChip: isChip)
    }
    private var brands: [String] { Set(catalog.phones.map { $0.text("brand") }).sorted() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(isChip ? "搜索芯片、厂商、别名" : "搜索手机、品牌、芯片", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("清空搜索").frame(width: 44, height: 44)
                        }
                    }.padding(.horizontal, 12).frame(minHeight: 48)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("网上查成绩").font(.subheadline.bold())
                            HStack {
                                if let url = onlineURL(geekbench: true) { Link("Geekbench 搜索 ↗", destination: url) }
                                if let url = onlineURL(geekbench: false) { Link("安兔兔资料搜索 ↗", destination: url) }
                            }.font(.subheadline)
                            Text("打开网站查看；新增资料与成绩导入请在电脑后台审核后发布。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    filters
                    HStack {
                        Text("\(records.count) \(isChip ? "款芯片" : "款手机")").font(.subheadline)
                        Spacer()
                        Text(metric.title).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    if records.isEmpty {
                        ContentUnavailableView(mode == .favorites && query.isEmpty ? "还没有收藏" : "没有匹配结果", systemImage: mode == .favorites ? "heart" : "magnifyingglass", description: Text(mode == .favorites ? "在手机详情中点爱心，建立自己的选机清单。" : "试试其他关键词或筛选条件。"))
                    }
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, device in
                        Surface {
                            HStack(alignment: .top, spacing: 12) {
                                Text(String(format: "%02d", index + 1)).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary).frame(minWidth: 32)
                                NavigationLink {
                                    DeviceDetailView(device: device, isChip: isChip)
                                } label: {
                                    DeviceSummary(device: device, metric: metric, isChip: isChip)
                                }.buttonStyle(.plain)
                                if !isChip {
                                    Button {
                                        showLimit = !library.toggleComparison(device.id)
                                    } label: {
                                        Image(systemName: library.comparison.contains(device.id) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.title3).frame(width: 44, height: 44)
                                    }.accessibilityLabel(library.comparison.contains(device.id) ? "移出对比 \(device.name)" : "加入对比 \(device.name)")
                                }
                            }
                        }
                    }
                    Text("数据快照 · \(catalog.generatedAt)\n来源与统计口径可在详情中查看。")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical)
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $metric) {
                            ForEach(isChip ? SortMetric.chipMetrics : SortMetric.phoneMetrics) { Text($0.title).tag($0) }
                        }
                    } label: { Label("排序", systemImage: "arrow.up.arrow.down") }
                }
            }
            .alert("最多对比 3 款手机", isPresented: $showLimit) { Button("知道了", role: .cancel) {} } message: { Text("请先在对比页移除一款。") }
        }
    }

    private func onlineURL(geekbench: Bool) -> URL? {
        var components = URLComponents(string: geekbench ? "https://browser.geekbench.com/search" : "https://www.bing.com/search")
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        components?.queryItems = [URLQueryItem(name: "q", value: geekbench ? keyword : "site:antutu.com " + keyword)]
        return components?.url
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isChip ? "从芯片，读懂性能。" : mode == .favorites ? "把值得关注的，留下来。" : "性能有据，选机有数。")
                .font(.title2.bold()).padding(.top, 12)
            Text(isChip ? "手机 SoC 与 Apple A / M 系列分别标注，传闻信息独立提示。" : "离线浏览 · 多维排序 · 三机对比")
                .font(.subheadline).foregroundStyle(.secondary)
            if !isChip && mode != .favorites {
                Text(platform == "all" ? "混合浏览不代表跨平台性能排名；Android 与 iOS 安兔兔分数不直接比较。" : "统计均分仅供参考。不同版本、测试环境的分数不可直接比较。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 12) {
            if isChip {
                Picker("芯片类别", selection: $category) {
                    Text("全部").tag("all"); Text("手机 SoC").tag("phone")
                    Text("Apple A").tag("apple-a"); Text("Apple M").tag("apple-m")
                    Text("其他").tag("other")
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if mode != .favorites {
                    Picker("平台", selection: $platform) {
                        Text("Android").tag("android"); Text("iPhone").tag("ios"); Text("全部").tag("all")
                    }.pickerStyle(.segmented)
                }
                Menu {
                    Picker("品牌", selection: $brand) {
                        Text("全部品牌").tag("all")
                        ForEach(brands, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Label(brand == "all" ? "全部品牌" : brand, systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44)
                }.modifier(GlassControl()).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 8)
    }
}

struct DeviceSummary: View {
    let device: DeviceRecord
    let metric: SortMetric
    let isChip: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(device.name).font(.headline).foregroundStyle(.primary)
            Text(isChip ? "\(device.text("vendor")) · \(device.text("process"))" : device.text("soc.name"))
                .font(.caption).foregroundStyle(.secondary)
            if isChip { Text("\(device.text("status")) · \(device.text("appliesTo"))").font(.caption).foregroundStyle(.secondary) }
            Text(device.text(metric.path(isChip: isChip))).font(.title2.monospacedDigit().weight(.semibold)).foregroundStyle(.blue)
            if !isChip {
                Text("\(device.text("ram")) / \(device.text("storage")) · \(device.text("platform") == "ios" ? "iOS" : "Android")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}