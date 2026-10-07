import SwiftUI

struct ComparisonView: View {
    let catalog: Catalog
    @Environment(LibraryStore.self) private var library
    private var devices: [DeviceRecord] { library.comparison.compactMap { id in catalog.phones.first { $0.id == id } } }
    var body: some View {
        NavigationStack {
            Group {
                if devices.isEmpty {
                    ContentUnavailableView("选出你的候选机型", systemImage: "rectangle.split.3x1", description: Text("在排行或详情中加入最多 3 款手机，逐项比较参数。"))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("同口径，才有可比性。不同平台安兔兔分数及不同 Geekbench 版本不可直接比较。")
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(devices) { device in
                                HStack {
                                    Text(device.name).font(.headline)
                                    Spacer()
                                    Button { library.toggleComparison(device.id) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                                        .accessibilityLabel("移除 \(device.name)")
                                }
                            }
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("参数").frame(width: 100, alignment: .leading)
                                        ForEach(devices) { Text($0.name).frame(width: 170, alignment: .leading) }
                                    }.font(.headline).padding(16)
                                    ForEach(SpecGroup.phone) { group in
                                        Text(group.title).font(.headline).padding(16)
                                        ForEach(group.fields) { field in
                                            HStack(alignment: .top, spacing: 12) {
                                                Text(field.title).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                                                ForEach(devices) { device in Text(device.text(field.path)).frame(width: 170, alignment: .leading) }
                                            }.font(.subheadline).padding(16)
                                            Divider()
                                        }
                                    }
                                }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                            }
                        }.padding(16)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground)).navigationTitle("机型对比")
            .toolbar {
                if !devices.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { Button("清空", role: .destructive) { library.clearComparison() } }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: devices.map(\.shareText).joined(separator: "\n\n")) }
                }
            }
        }
    }
}
