import SwiftUI

struct DeviceDetailView: View {
    let device: DeviceRecord
    let isChip: Bool
    @Environment(LibraryStore.self) private var library
    @State private var showLimit = false
    private var groups: [SpecGroup] { isChip ? SpecGroup.chip : SpecGroup.phone }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(device.name).font(.largeTitle.bold()).padding(.top, 8)
                Text(isChip ? "\(device.text("vendor")) · \(device.text("status"))" : "\(device.text("brand")) · \(device.text("platform"))")
                    .foregroundStyle(.secondary)
                if !isChip {
                    Button {
                        showLimit = !library.toggleComparison(device.id)
                    } label: {
                        Label(library.comparison.contains(device.id) ? "移出对比" : "加入对比", systemImage: "rectangle.split.3x1")
                    }.buttonStyle(.glass).controlSize(.large)
                }
                Text("分数来自原始数据快照，GB6 / GB7 与 Android / iOS 安兔兔不能直接混比。未查证字段保持原标注。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(groups) { group in
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title).font(.headline)
                            ForEach(group.fields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.title).font(.caption).foregroundStyle(.secondary)
                                    Text(device.text(field.path)).font(.body).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                if !device.value("features").array.isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("功能特性").font(.headline)
                            ForEach(Array(device.value("features").array.enumerated()), id: \.offset) { _, feature in Text("• " + feature.text) }
                        }
                    }
                }
                if device.text("notes") != "未查证" { Text(device.text("notes")).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                SourceList(sources: device.sources)
                ForEach(isChip ? ["gb6", "gb7"] : ["geekbench.gb6", "geekbench.gb7"], id: \.self) { path in
                    let sourceURLs = device.value(path + ".sources").array.compactMap { Source(label: $0.text, rawURL: $0.text) }
                    if !sourceURLs.isEmpty { SourceList(sources: sourceURLs) }
                }
            }.padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("参数详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isChip {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { library.toggleFavorite(device.id) } label: { Image(systemName: library.favorites.contains(device.id) ? "heart.fill" : "heart") }
                        .accessibilityLabel(library.favorites.contains(device.id) ? "取消收藏" : "收藏手机")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { ShareLink(item: device.shareText) }
        }
        .alert("最多对比 3 款手机", isPresented: $showLimit) { Button("知道了", role: .cancel) {} }
    }
}

struct SourceList: View {
    let sources: [Source]
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text("数据来源").font(.headline)
                if sources.isEmpty { Text("未查证").foregroundStyle(.secondary) }
                ForEach(sources) { source in
                    Link(destination: source.url) { Label(source.label, systemImage: "arrow.up.right.square").frame(minHeight: 44, alignment: .leading) }
                }
            }
        }
    }
}
