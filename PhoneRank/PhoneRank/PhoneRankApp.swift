import SwiftUI

@main
struct PhoneRankApp: App {
    @State private var library = LibraryStore()
    @State private var catalog = CatalogStore()
    var body: some Scene {
        WindowGroup {
            if let data = catalog.catalog {
                RootView(catalog: data).environment(library).environment(catalog)
            } else {
                ContentUnavailableView("数据无法读取", systemImage: "exclamationmark.triangle", description: Text("应用内的数据文件缺失或损坏，请重新安装。"))
            }
        }
    }
}

struct RootView: View {
    let catalog: Catalog
    var body: some View {
        TabView {
            Tab("排行", systemImage: "chart.bar.xaxis") { DeviceListView(catalog: catalog, mode: .phones) }
            Tab("芯片", systemImage: "cpu") { DeviceListView(catalog: catalog, mode: .chips) }
            Tab("收藏", systemImage: "heart") { DeviceListView(catalog: catalog, mode: .favorites) }
            Tab("对比", systemImage: "rectangle.split.3x1") { ComparisonView(catalog: catalog) }
            Tab("关于", systemImage: "info.circle") { AboutView(catalog: catalog) }
        }
        .tint(.blue)
    }
}

struct GlassControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(.background, in: Capsule()).overlay(Capsule().stroke(.secondary.opacity(0.25))) }
        else { content.glassEffect(.regular.interactive(), in: Capsule()) }
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
