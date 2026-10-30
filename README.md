# iMusic

原生 iPhone、iPad、macOS 离线音乐播放器。原生依赖使用 **Swift Package Manager**，Wi-Fi 上传网页使用 **npm** 管理 React／TypeScript／Vite 依赖，无需 CocoaPods。支持英文、简体中文和繁体中文，跟随系统或应用语言设置。

## 打开与运行

1. 安装 Node.js 22.12+，首次检出或前端锁文件变化后运行 `npm ci --prefix Web/WiFiUpload`。
2. 使用 Xcode 打开 `iMusic.xcodeproj`，等待 SPM 解析依赖及下载音频 XCFramework。首次构建如提示是否信任本地 `WiFiUploadBuild` 插件，选择信任。
3. Mac 选择 **iMusicMac** scheme；iPhone／iPad 选择 **iMusic**，再选择模拟器或开发签名设备。
4. 本地 Debug／Release 不携带 CloudKit、推送或 CarPlay entitlement，可独立开发。
5. 真机需要在 Signing 中选择自己的开发团队。可复制 `Config/Signing.example.xcconfig` 为被 Git 忽略的 `Config/Signing.local.xcconfig`。

正常 Build／Run／Archive 和 `swift test` 均通过 SwiftPM 插件构建 React 静态资源并打入 `iMusicKit` 资源包；无需手工复制 `dist`，运行时不需要 Node 或联网加载前端。前端开发和构建细节见 [Web/WiFiUpload/README.md](Web/WiFiUpload/README.md)。

已使用 Xcode 26.3、Swift 6.2.4 构建。最低系统为 iOS／iPadOS 17 和 macOS 14；依赖需要 Swift 6.1 或以上工具链。Xcode 工程已提交，通常无需安装工程生成工具。

### VS Code 代码跳转与引用

用 VS Code 打开项目根目录，安装并启用官方 **Swift** 扩展（`swiftlang.swift-vscode`）。如果曾全局禁用扩展，可在扩展页面选择 **Enable (Workspace)**。项目的 `.vscode/settings.json` 使用 `/Applications/Xcode.app` 中的工具链并开启后台索引；Xcode 安装在其他位置时需调整 `swift.path`。

`Sources/` 和 `Tests/` 由 SwiftPM 提供补全、定义跳转和引用索引。首次打开后等待后台索引完成；也可运行构建任务 **Swift: Build package and tests**。

`Apps/Shared/iMusicApp.swift` 属于 Xcode App 目标，需要额外连接构建信息：

```sh
brew install xcode-build-server
bash Scripts/configure_vscode_swift.sh macos
# 检查 UIKit 等 iOS 专用代码时切换：
bash Scripts/configure_vscode_swift.sh ios
```

也可通过 **Terminal → Run Task** 运行 **Swift: Refresh App index (macOS)** 或 **Swift: Refresh App index (iOS Simulator)**。脚本在 `Apps/buildServer.json` 生成当前机器的配置，并刷新 Xcode 构建索引；该文件不提交。修改 App 目标、增加文件或切换平台后重新运行对应任务，必要时执行 **Swift: Restart Language Server**。

macOS 默认索引只分析当前平台激活的条件编译分支。App 切换为 iOS 索引后可分析入口中的 UIKit 分支；包中的 iOS 专用代码也可在 Xcode 的 iOS scheme 中查看。

在符号上右键选择 **Go to Definition** 或 **Find All References**，也可在命令面板运行对应命令。VS Code 默认快捷键为 **F12** 和 **⇧F12**；本机启用了 IntelliJ 键位映射，当前实际快捷键为 **⌥⌘B**（定义）和 **⌥F7**（所有引用）。Mac 功能键可能需要同时按 **fn**。

## 源码组织

`Sources/iMusicKit/View/` 与 `ViewModel/` 按 Navigation、Home、Library、Player、Editors、Import、Settings、Statistics、Shared 归类。每个页面持有自己的查询、选择与编辑状态；`Application/AppModel.swift` 仅负责依赖组装和启动。状态生命周期与依赖规则见 [架构说明](Docs/Architecture.md#界面与状态所有权)。

## 使用

- 点击“导入音乐”，多选音频；从“关联文件夹”导入目录，或在“Wi-Fi 传歌”页面查看浏览器地址和配对码。
- 支持 MP3、AAC/M4A、ALAC、FLAC、WAV、AIFF、Ogg Vorbis、Opus 等。具体以容器探测和解码结果为准。
- 音乐复制到 Application Support 内的托管资料库，保留原始文件名和原始标签，不移动或改写来源文件。
- 资料库提供歌曲、歌手、专辑、流派、收藏与歌单。Mac 表格可多选、排序、双击播放及批量编辑；歌单支持独立条目和重复歌曲。
- 底部播放栏进入当前播放；支持顺序、随机、列表循环、单曲循环、队列调整、±10 秒、变速、均衡器、A/B 和睡眠定时。
- iPhone／iPad 使用系统 AirPlay 选择器；Mac 跟随系统输出，通过声音设置切换 AirPlay 目标。
- 标签、图片和旧编码修复默认只修改 iMusic 覆盖信息。在线封面查询默认关闭，启用后仍由用户手动查询。
- 设置中可导出完整 ZIP 备份或轻量整理信息备份；恢复前会校验路径、大小和哈希，并保留逻辑快照。请将备份另存到应用之外。
- 删除歌曲或歌单进入回收站。iPhone／iPad 在回收站歌曲行左滑选择恢复或永久删除；Mac 使用右键菜单。永久删除需确认，只清理应用内无其他记录引用的音频与封面，导入来源文件和独立备份保留。不会自动清空回收站。

## 可选的 iCloud 与 CarPlay

完整功能代码随项目提供，启用需具备相应的开发者签名能力：

| Scheme | 功能与配置 |
| --- | --- |
| `iMusic` / `iMusicMac` | 独立本地构建 |
| `iMusic Cloud` / `iMusicMac Cloud` | CloudKit 私有数据库和后台同步 |
| `iMusic CarPlay` | CarPlay 音频界面，需 Apple 批准 entitlement |
| `iMusic Full` / `iMusicMac Full` | 云同步；iOS 同时启用 CarPlay；Archive 使用 FullRelease |

具体配置、CloudKit schema 和真机条件见 [Docs/Signing.md](Docs/Signing.md)。未配置容器的本地构建会明确禁用云开关，不会请求可见通知权限。

## 验证与开发

代码文档统一使用英文：Swift 的所有成员字段（包括私有、计算属性与界面状态）及 public 方法／初始化方法使用 `///`，协议 API 同样需要说明；React／TypeScript 类型字段和导出 API 使用 JSDoc。注释应解释用途、单位、状态约定和必要的副作用，新增或修改声明时同步维护。

```sh
swift test
npm test --prefix Web/WiFiUpload
IMUSIC_AUDIO_TESTS=1 swift test --filter AudioIntegrationTests
IMUSIC_PERFORMANCE_TESTS=1 swift test --filter PerformanceTests
xcodebuild -project iMusic.xcodeproj -scheme iMusicMac -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- build
xcodebuild -project iMusic.xcodeproj -scheme iMusic -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

默认 `swift test` 不启动真实播放引擎；播放协调逻辑使用可控的测试引擎，暂停、seek、下载和迟到回调等回归照常执行。三个依赖硬件音频时钟的集成测试需要显式设置 `IMUSIC_AUDIO_TESTS=1`，素材仍为全零静音 PCM；`IMUSIC_SKIP_AUDIO_TESTS=1` 可强制跳过硬件测试。构建与索引任务只编译，不执行播放。完整验收和已验证范围见 [Docs/Validation.md](Docs/Validation.md)。

- [架构与数据流](Docs/Architecture.md)
- [备份格式与恢复](Docs/BackupFormat.md)
- [签名与能力配置](Docs/Signing.md)
- [验证记录与真机清单](Docs/Validation.md)
- [多语言文案与扩展](Docs/Localization.md)

`Scripts/generate_project.rb` 可重建工程，需要 Ruby `xcodeproj` gem；`Scripts/generate_assets.swift` 生成项目自有图标。这两个脚本都不是运行应用的必要依赖。

## 边界

歌词、Watch、Siri／快捷指令、小组件、NAS 和跨设备播放接力按约定留待扩展。AirPlay 目标切换允许系统建立路由所需的停顿；不承诺离开网络后远端继续播放。iOS 文件夹扫描在启动／回到前台／手动扫描时执行，不承诺后台常驻监控。

自有代码采用 MIT；第三方组件保留各自许可证。见 [LICENSE](LICENSE) 和 [ThirdPartyNotices](ThirdPartyNotices)。音乐素材、用户资料库、证书和开发团队配置不随源码分发。
