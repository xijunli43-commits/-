# 手机性能排行 · iOS + 本机管理后台

本工程保留原 PWA 的 182 款手机、80 款芯片与来源信息。iOS 部分采用 SwiftUI，目标 iOS 26+：原生液态玻璃导航、搜索筛选、多维排序、完整参数详情、三机对比、本地收藏、系统分享和手动服务器更新。后台已在 Windows 上实现，可管理草稿、审核外部成绩、发布数据及恢复旧值。

## 当前验证边界

- Python 服务与管理界面可在这台电脑运行；测试见 `backend/tests`。
- 已迁移原始数据，保留未查证标记和来源；没有逐条证明原包全部数据正确或获得再发布授权。
- 当前环境没有 Mac、Xcode、付费 Apple Developer 账号。Swift 源码尚未编译，模拟器/真机、截图、签名和上架尚未完成。
- 网页预览是原 PWA 加玻璃风格，不是 iOS 原生运行截图。原生效果以 Mac 构建后为准。

## 本机后台

双击 `backend/启动后台.cmd`，打开 <http://127.0.0.1:8765/>。如果虚拟环境缺失，启动脚本会先安装 `requirements.txt` 中固定版本。

后台默认只在本机监听，管理接口只允许 loopback 地址并验证会话 CSRF。没有公网发布、路由器端口映射、后台自动开机任务或防火墙规则修改。

1. 搜索手机或芯片，点“编辑”。支持分字段编辑与完整 JSON 编辑。
2. 保存进入草稿；应用仍读取上次发布版本。
3. “采集与审核”填写公开榜单/成绩页地址。也可导入自己保存的 HTML 文件。
4. 核对机型、内存配置、平台、GB6/GB7 版本和来源，逐条匹配到已有记录。
5. 确认后应用到草稿，再点“发布数据”。发布时保留历史快照。
6. 删除/编辑可在“修改历史”恢复旧值。导出草稿生成 JSON 备份。

数据保存在 `backend/data/catalog.sqlite3`；应用退出后数据保留。备份 SQLite 时先停止服务器，或使用 SQLite backup API；运行时不能只复制主库而遗漏 WAL 文件。

“导出草稿”是可读 JSON 备份。当前没有整库备份上传恢复按钮，历史页支持单记录恢复。HTML 导入仅解析文本，不执行外部脚本。

## 抓取范围与限制

- 安兔兔 Android、iOS 公开榜单。iOS 榜只导入 iPhone；不混入 iPad。CPU/GPU/MEM/UX/总分和统计月份按列提取，列数变化或月份缺失时停止导入。
- 安兔兔 SoC 入口仅在当前页面结构可识别时导入；无法识别时明确报错，不保证所有榜单布局通用。
- Geekbench 6/7 `/v6/cpu/数字`、`/v7/cpu/数字` 成绩详情。单次成绩不会被标为总体平均值；匹配芯片时样本数记为 1。
- 抓取只访问白名单 HTTPS 来源，遵守 robots.txt，设置间隔、超时和大小限制，不跟随重定向、不绕过验证码。robots 无法读取或禁止抓取时转为手动 HTML 导入。
- Geekbench 当前实测请求被 Cloudflare 阻挡，直接抓取不保证成功。HTML 解析已用测试样例验证，仍需用实际正常页面核验。
- 没有全站爬虫、自动定时任务或模糊匹配自动覆盖。规格参数并非跑分页都有，抓取只补充页面真实包含的成绩。

## 手机连接电脑服务器

如需同 Wi-Fi 下的 iPhone 读取，使用 `backend/启动局域网数据服务.cmd`。该模式监听所有网卡，只有只读数据接口对局域网开放；后台仍仅本机可访问。Windows 首次可能弹出防火墙提示，仅按需要允许专用网络。

在 iOS 应用“关于 → 数据更新”输入 `http://电脑局域网IP:8765` 并手动获取。不要在 iPhone 输入 `127.0.0.1`，它指向手机自身。

电脑休眠、关机或服务停止后无法获取新数据，但 iOS 仍保留离线缓存。App Store 正式公开版需要稳定的 HTTPS 服务和真实隐私政策/支持网址；本机服务不是全天在线的公网服务器。

## 在 Mac 构建 iOS

需要支持当前 iOS SDK 的 Xcode 26 或更新版本，以及 XcodeGen。

```sh
brew install xcodegen
cd PhoneRank
xcodegen generate
open PhoneRank.xcodeproj
```

在 Xcode 的 Signing & Capabilities 选择自己的 Team，修改唯一 Bundle Identifier。当前 `com.phonerank.local.PhoneRank` 仅为工程初始标识。运行测试时选择实际已安装的 iOS 26+ 模拟器。

```sh
xcodebuild -list -project PhoneRank.xcodeproj
xcodebuild -project PhoneRank.xcodeproj -scheme PhoneRank \
  -destination 'platform=iOS Simulator,name=你的模拟器名称' test
```

免费账号可按 Apple 的 Personal Team 限制进行真机测试；不能用它发布 App Store。付费会员、真实构建验证、数据权利核查完成后，参考 `release/AppStore-准备.md`。

## 方案依据与复用

复用原数据/PWA 的业务结构与本地网页预览；原生界面采用 Apple 标准 SwiftUI 控件、ShareLink、Observation、UserDefaults 和 URLSession。后台组合 Flask、SQLite、Waitress、Requests 和 Beautiful Soup；无需自己写 HTTP 服务、数据库引擎或 HTML tokenizer。

定制部分是手机/芯片 JSON 兼容模型、按版本保留成绩的解析适配器、草稿发布流程和机型人工匹配。审阅了 Geekbench Browser Python，但其聚合处理器数据接口不覆盖本项目手机成绩页审核流程，因此未增加该依赖或复制其代码。

参考链接与维护/许可评估见 `release/方案与验证.md`。运行依赖锁定在 `backend/requirements.txt`，iOS 无第三方运行依赖。

## GitHub 云端构建

已增加 `.github/workflows/ios-build.yml`。不需要自有 Mac，可在 GitHub 生成未签名的真机 IPA，再在 Windows 本地签名安装。操作见 `release/云端构建.md`。当前尚未连接远程仓库，也未运行真正的云端构建。
