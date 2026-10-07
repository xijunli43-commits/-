import Foundation

struct SpecField: Identifiable {
    let title: String
    let path: String
    var id: String { path }
}
struct SpecGroup: Identifiable {
    let title: String
    let fields: [SpecField]
    var id: String { title }
    init(_ title: String, _ fields: [(String, String)]) {
        self.title = title
        self.fields = fields.map { SpecField(title: $0.0, path: $0.1) }
    }
    static let phone = [
        SpecGroup("基本信息", [("品牌", "brand"), ("平台", "platform"), ("发布", "releaseDate"), ("内存", "ram"), ("存储", "storage")]),
        SpecGroup("安兔兔", [("总分", "antutu.total"), ("CPU", "antutu.cpu"), ("GPU", "antutu.gpu"), ("MEM", "antutu.mem"), ("UX", "antutu.ux"), ("统计期间", "antutu.period")]),
        SpecGroup("Geekbench 6", [("单核", "geekbench.gb6.single"), ("多核", "geekbench.gb6.multi")]),
        SpecGroup("Geekbench 7", [("单核", "geekbench.gb7.single"), ("多核", "geekbench.gb7.multi")]),
        SpecGroup("芯片", [("名称", "soc.name"), ("别名", "soc.alias"), ("厂商", "soc.vendor"), ("工艺", "soc.process"), ("核心", "soc.cores"), ("GPU", "soc.gpu")]),
        SpecGroup("机身", [("高度 / mm", "body.height"), ("宽度 / mm", "body.width"), ("厚度 / mm", "body.thickness"), ("重量 / g", "body.weight"), ("边框", "body.frame"), ("后盖", "body.back"), ("防护", "body.ip")]),
        SpecGroup("屏幕", [("尺寸 / 英寸", "display.size"), ("技术", "display.tech"), ("分辨率", "display.resolution"), ("PPI", "display.ppi"), ("刷新率 / Hz", "display.refresh"), ("亮度", "display.brightness"), ("形态", "display.shape")]),
        SpecGroup("相机", [("主摄", "camera.main"), ("超广角", "camera.ultrawide"), ("长焦", "camera.tele"), ("前摄", "camera.front"), ("特性", "camera.features")]),
        SpecGroup("电池与充电", [("容量 / mAh", "battery.capacity"), ("有线 / W", "battery.wired"), ("无线 / W", "battery.wireless"), ("反向充电", "battery.reverse")]),
        SpecGroup("声音与触感", [("扬声器", "audio.speakers"), ("布局", "audio.layout"), ("音频特性", "audio.features"), ("耳机接口", "audio.jack"), ("马达", "haptics.motor"), ("触感详情", "haptics.detail")])
    ]
    static let chip = [
        SpecGroup("基本信息", [("厂商", "vendor"), ("类别", "category"), ("适用设备", "appliesTo"), ("状态", "status"), ("发布", "releaseDate"), ("工艺", "process")]),
        SpecGroup("CPU / GPU", [("CPU 核心", "cpu.cores"), ("架构", "cpu.arch"), ("频率 / GHz", "cpu.freqGHz"), ("GPU 核心", "gpu.cores"), ("光追", "gpu.raytracing"), ("GPU 特性", "gpu.features"), ("NPU", "npu"), ("缓存", "cache")]),
        SpecGroup("内存", [("带宽 / GB/s", "memory.bandwidthGBs"), ("最大内存 / GB", "memory.maxGB"), ("类型", "memory.type")]),
        SpecGroup("安兔兔", [("总分", "antutu.total"), ("CPU", "antutu.cpu"), ("GPU", "antutu.gpu")]),
        SpecGroup("Geekbench 6", [("单核", "gb6.single"), ("多核", "gb6.multi"), ("样本数", "gb6.samples")]),
        SpecGroup("Geekbench 7", [("单核", "gb7.single"), ("多核", "gb7.multi"), ("样本数", "gb7.samples")]),
        SpecGroup("代表设备", [("设备", "devices")])
    ]
}
