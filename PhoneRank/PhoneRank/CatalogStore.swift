import Foundation
import Observation

@MainActor @Observable
final class CatalogStore {
    private(set) var catalog: Catalog?
    private(set) var updating = false
    private(set) var message = ""
    private var cacheURL: URL { URL.cachesDirectory.appending(path: "phone-catalog.json") }
    init() {
        catalog = try? Catalog.load()
        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(Catalog.self, from: data), Self.valid(cached) { catalog = cached }
    }
    static func valid(_ catalog: Catalog) -> Bool {
        !catalog.phones.isEmpty && catalog.phones.count <= 10000 && catalog.chips.count <= 10000 &&
        Set(catalog.phones.map(\.id)).count == catalog.phones.count && Set(catalog.chips.map(\.id)).count == catalog.chips.count
    }
    func update(baseURL: String) async {
        guard !updating else { return }
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { message = "请输入有效的服务器地址。"; return }
        if url.scheme == "http" {
            let host = url.host ?? ""
            let octets = host.split(separator: ".").compactMap { Int($0) }
            let privateIPv4 = host.split(separator: ".").count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } &&
                (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
            let local = host.hasSuffix(".local") || host == "localhost" || privateIPv4
            guard local else { message = "公网服务器必须使用 HTTPS。"; return }
        }
        updating = true
        defer { updating = false }
        do {
            var request = URLRequest(url: url.appending(path: "api/v1/catalog"))
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 10_000_000,
                  response.url?.host == url.host else { throw URLError(.badServerResponse) }
            let updated = try JSONDecoder().decode(Catalog.self, from: data)
            guard Self.valid(updated) else { throw URLError(.cannotParseResponse) }
            try data.write(to: cacheURL, options: .atomic)
            catalog = updated
            message = "已更新 · \(updated.generatedAt)"
        } catch { message = "更新失败，保留当前离线数据。请检查服务器地址、同一 Wi-Fi 和网络权限。" }
    }
}
