import SwiftUI

struct SyncSettingsView: View {
    @Environment(CatalogStore.self) private var store
    @AppStorage("catalogServerURL") private var server = ""
    var body: some View {
        Form {
            Section("数据服务器") {
                TextField("例如 http://192.168.1.10:8765", text: $server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Text("在电脑后台发布后，连接同一 Wi-Fi 并填写电脑的局域网地址。电脑服务器需要以局域网模式启动；本机 127.0.0.1 地址无法在 iPhone 上连接。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(store.updating ? "更新中…" : "获取已发布数据") { Task { await store.update(baseURL: server) } }.disabled(store.updating || server.isEmpty)
                if !store.message.isEmpty { Text(store.message).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
            }
            Section("隐私说明") {
                Text("默认离线使用。仅当你主动获取数据时向指定服务器发送网络请求，服务器能看到设备的网络地址。收藏和对比不会上传。不集成广告、追踪或分析服务。")
                Text("服务器停止或电脑关机时，仍可浏览已缓存的数据。公开 App Store 版本应使用稳定的 HTTPS 数据服务器，并填写真实的支持与隐私政策网址。")
            }
        }.navigationTitle("数据更新")
    }
}
