import SwiftUI

struct AboutView: View {
    let catalog: Catalog
    @Environment(LibraryStore.self) private var library
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            List {
                Section("手机性能排行") {
                    LabeledContent("数据快照", value: catalog.generatedAt)
                    LabeledContent("收录", value: "\(catalog.phones.count) 手机 / \(catalog.chips.count) 芯片")
                    Text("这是资料查询工具，不是跑分测试工具。原包数据尚未完成逐条独立核验。")
                }
                Section("统计口径") {
                    ForEach(Array(catalog.methodology.enumerated()), id: \.offset) { _, item in Text(item).font(.footnote) }
                }
                Section("来源") { ForEach(catalog.sources) { Link($0.label, destination: $0.url) } }
                Section("隐私") {
                    Text("收藏和对比保存在设备本地。不要求登录，不使用广告或分析 SDK。主动获取数据会连接你指定的服务器；点击来源会打开外部网站，其隐私规则由对应网站提供。")
                    NavigationLink("数据更新与隐私说明") { SyncSettingsView() }
                    Button("清除收藏与对比", role: .destructive) { confirmClear = true }
                }
            }.navigationTitle("关于")
                .confirmationDialog("清除本机收藏与对比？", isPresented: $confirmClear, titleVisibility: .visible) { Button("清除", role: .destructive) { library.clearLibrary() } }
        }
    }
}
