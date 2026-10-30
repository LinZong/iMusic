# 验证记录

验证日期：2026-10-30。环境：Apple Silicon Mac、macOS 15.7.4、Xcode 26.3 / Swift 6.2.4。本文件区分已实际验证的内容与需要真实设备、账号或授权的内容。

## 自动化

最近一次默认 `swift test`：**64 项测试，60 项通过、3 项硬件音频集成测试和 1 项性能测试按默认配置跳过，零失败**。播放协调逻辑使用不接触音频设备的测试引擎；生成的 PCM 与 UI 验收 WAV 均为静音，未使用或修改用户音乐。

| 范围 | 已检查的行为 |
| --- | --- |
| 时间轴 | 未知、零、非有限时长；比例边界；预览与真实播放位置分离 |
| 队列 | 重复歌曲独立条目、手动下一首、单曲循环、稳定随机顺序、历史 |
| 音频引擎（手动开启） | 实际媒体时钟、暂停、seek、变速；旧播放器回调隔离；预加载下一曲身份；默认不运行硬件测试 |
| 播放协调 | 暂停后 seek、保存位置、下载中暂停、迟到下载结果、空队列添加、恢复播放前提交未结束的进度预览、立即暂停优先于迟到回调、暂停后下一曲下载及中断恢复 |
| 资料库 | Unicode、搜索通配符、统一 Schema 与 FTS 触发器、原子 outbox、迟到确认、回收站 |
| 并发编辑 | 歌单并发新增与删除，按字段确定性合并 |
| 导入恢复 | 去重、损坏文件、原件保持不变、导入日志恢复、完整 Wi-Fi 上传恢复 |
| 备份 | 完整／轻量 ZIP、恢复校验、偏好恢复、排除账号与设备授权 |
| Wi-Fi | 配对认证、Unicode 文件名、流式上传内容一致、拒绝未配对上传；React 构建资源、MIME／CSP、静态路径限制与配置接口 |
| 永久删除 | 应用副本与来源分离、共享引用保留、批量事务、歌单／队列清理、旧同步与备份不复活、显式重新导入、启动补清理、符号链接边界、迟到下载失效 |
| 本地化 | 三语查找、地区匹配、英文单复数、多参数、Unicode、网页和旧偏好迁移 |
| 同步编码 | 一万条歌单压缩与往返解码，CloudKit 单记录预算 |

生成一万首歌曲记录的 SQLite 搜索，最近一次 P95 为 **9.27 ms**。这是本机数据库微基准，不能当作其他设备上的界面延迟保证。可通过 `IMUSIC_PERFORMANCE_TESTS=1 swift test --filter PerformanceTests` 重现。普通测试默认跳过性能测试与三个硬件音频集成测试；全部播放协调逻辑回归通过测试引擎执行，不需要声卡。手动设置 `IMUSIC_AUDIO_TESTS=1 swift test --filter AudioIntegrationTests` 才会启动真实音频引擎，素材仍为静音。CI 显式设置 `IMUSIC_AUDIO_TESTS=0` 和 `IMUSIC_SKIP_AUDIO_TESTS=1`。

本地化静态检查已通过：333 个键的三语覆盖、格式参数一致、生成资源同步，以及 Swift 源码文案扫描。Mac 英文、iPhone 简体中文、iPad 繁体中文已实际打开确认。

GitHub Actions 工作流位于 `.github/workflows/build.yml`：运行测试，以及 macOS、本地 iOS 和包含云／CarPlay 条件代码的 iOS 构建。工作流文件已提供，尚未在 GitHub 托管运行。

## 构建

本地 macOS arm64 ad-hoc 构建、iOS 通用模拟器构建、包含云／CarPlay 源码的 Full 模拟器构建及 arm64 iOS 设备目标均已成功编译。设备目标使用 `CODE_SIGNING_ALLOWED=NO`，不等同于已签名安装真机。

## 界面与回归

Mac 原生窗口已操作验证：空库首页、Unicode 文件导入及报告、迷你播放器、完整播放器、暂停、跳转到 30 秒和 36 秒后仍保持暂停、中文歌单创建、选曲和原生表格显示。测试曲总时长正确显示为 1:00，滑轨限制在可用宽度内。

iPhone 17 Pro / iOS 26.3 已实际启动验证首页、底部导航、播放器、恢复暂停位置，并核对从所选 30 秒位置继续播放。iPad Pro 11 英寸 / iPadOS 17.4 已实际启动验证竖屏布局与横屏侧栏切换。模拟器只使用从生成素材复制的 QA 资料库。

验收中修复了三个真实界面问题：多个 fileImporter 相互覆盖导致导入按钮无响应；iOS 场景配置重复返回 SwiftUI 代理导致递归白屏；辅助功能调整滑块没有拖动结束事件时，显示位置未提交到实际播放。已为第三项加入回归测试。必须验证实际启动、导入和跳转后的恢复播放，单纯通过编译不能证明这些入口正常。

## 发布前仍需真实环境验收

- iPhone／iPad 真机：锁屏和后台长时间播放、电话／耳机拔出、蓝牙、音频服务重置、设备重启后的资料库与保护文件访问。
- AirPlay：真实接收端、切换及断网恢复。模拟器与系统输出名称不能代替此项。
- CloudKit：使用自己的开发团队、容器与两个设备，验证离线编辑合并、资产补传、按需下载、账号切换及生产 schema。
- CarPlay：Apple 批准的音频 entitlement、正确签名及车辆／配套测试环境。源码可编译不代表已获得授权。
- 不同格式：目前真实解码集成测试使用 WAV；对 MP3、AAC/ALAC、FLAC、Vorbis、Opus 等还需以合法持有的格式样本完成听测和跨格式切换。
- 无缝播放：同格式预加载已覆盖自动测试，混合采样率和声道不承诺采样级无缝；需真实相邻曲目听测。
- 大资料库与极端条件：真实音乐素材、低存储空间、强制结束恢复、超过数 GB 的 ZIP 和慢速 iCloud 网络。

没有配置开发者团队、登录用户账号、上传音乐到外部服务或申请通知权限；没有发布、推送或上传源码。

## 回收站变更验收

新增 10 项回归测试全部通过。macOS arm64 ad-hoc 与 iOS 通用模拟器 Debug 均成功构建。本次没有操作真实资料库中的永久删除，也没有自动部署到用户真机。

iPhone 15 Pro / iOS 17.4 模拟器使用独立的 `iMusicTrashSwipeQA` 资料库和生成的静音 WAV。检查了歌曲行无独立 Restore 按钮，恢复／永久删除作为系统列表动作提供；通过这些动作打开删除确认弹窗，取消后两条记录保留，恢复测试歌曲后回收站数量从两首变为一首。界面动作通过辅助功能入口验收；物理文件清理由生成素材的自动化测试验证。

## React 上传页构建与验收（2026-10-30）

- SwiftPM 插件在 Xcode 与 `swift test` 中运行前端类型检查及 Vite 生产构建，macOS／iOS 模拟器 App 中均已确认存在带哈希的 JS／CSS 和 HTML。
- Swift 测试共 60 项，59 项通过，1 项性能测试按默认配置跳过；无失败。前端 Vitest 共 12 项通过，覆盖配对、三语、文件校验、上传进度、取消重试与过期令牌。
- Chrome 实际打开由生产 `WiFiUploadServer` 提供的打包页面，完成配对、选择和上传生成的 10.6 MB WAV 测试文件。Unicode 文件名、落盘字节 SHA-256 和完成标记均匹配；页面显示 Received。测试使用独立临时资料库，不写入用户资料库。
- 已检查桌面和窄屏页面；窄屏无横向溢出。真实设备上的局域网连通性及系统权限仍以对应设备验收为准。

## 单一初始 Schema 与重装验收（2026-10-30）

- `LibraryStore` 合并为单个 `initial-schema`，直接创建当前完整数据库结构，不再保留开发期的 v1／v2 升级步骤。
- Swift 测试共 61 项，60 项通过，1 项性能测试按默认配置跳过。新增检查覆盖首次建库、重新打开、设备标识保持，以及 FTS 插入／更新／删除触发器。
- macOS 和 iOS 模拟器构建成功。清理 Mac 旧应用资料库后安装到 `~/Applications/iMusic.app`；iPhone 17 Pro、iPhone 15 Pro、iPad Pro (11-inch) (4th generation) 三个已有安装的模拟器均执行卸载、重装和启动。
- 四处实际数据库均确认只有 `initial-schema` 登记，records 为 0，搜索维护触发器为 3 个。原先关闭的两个模拟器在验收后恢复关闭状态。

## 默认构建与测试静音（2026-10-30）

- 去除测试素材中的 440 Hz 正弦波，全部生成 PCM 使用零采样；新增文件读取测试确认时长有效、采样全零。
- PlaybackCoordinator 接受 PlaybackEngine 注入；七个协调测试与回收站播放测试均使用不创建 AVAudioEngine 的确定性测试引擎，保留 seek、下载与迟到回调等断言，消除等待真实音频时钟的 sleep。
- 三个真实音频引擎测试默认由 setUp 跳过，仅在 `IMUSIC_AUDIO_TESTS=1` 且未设置 `IMUSIC_SKIP_AUDIO_TESTS=1` 时运行。App 正常播放仍使用真实 SFB 引擎。
- 默认测试 62 项：58 项通过、4 项跳过，零失败。硬件音频测试未在本轮开启。

## 系统强调色验收（2026-10-30）

已移除应用内 Accent Color 选择器、固定强调色资源及自定义导航／选择控件配色。macOS arm64 与 iOS 通用模拟器构建成功，两个包的 Info.plist 均不再声明 NSAccentColorName；项目生成脚本同样不设置固定强调色。默认测试 62 项，58 项通过、4 项按默认配置跳过，零失败；本地化检查覆盖 333 个键、3 种语言。

已原位更新已安装 Mac 应用和 iPhone 15 Pro / iOS 17.4 模拟器应用，保留资料库。实际确认设置页没有 Accent Color 入口，Mac 原生侧栏选中背景和图标采用系统强调色，iPhone 使用平台默认 Tab 样式与颜色。未修改系统外观设置。

## 页面内搜索验收（2026-10-30）

RootView 不再附加搜索框，AppModel 不再持有全局搜索词。SongListView 和 CollectionGrid 分别持有本页关键词、应用本页筛选与相应提示；歌单列表只搜索歌单名称，歌曲列表搜索当前列表内的歌曲信息，分类列表分别搜索歌手／专辑／流派。首页最近添加和分类数量不再受其他页面的搜索影响。查询无结果时显示包含本次关键词的系统搜索空状态。

macOS 和 iOS 模拟器构建通过，默认 64 项测试、60 项通过、4 项跳过、零失败；本地化检查覆盖 337 个键、3 种语言。iPhone 15 Pro / iOS 17.4 实际验证 Search Songs 与 Search Playlists 提示、输入不同关键词后的独立结果、切回歌曲页保留原关键词，以及 Home／Settings 没有搜索框。测试关键词已清除，应用更新保留资料库。

## 英文代码注释验收（2026-10-30）

已为所有 Swift 成员字段及 public／协议方法补充英文文档注释，包括私有存储字段、计算属性、SwiftUI 状态、公开初始化方法和测试替身字段。同一行的组合字段声明拆为独立声明，便于逐项说明。Swift 语法树审计覆盖 445 个字段、156 个 public／协议方法、20 个 public 初始化方法，未发现缺失。React 上传页的 10 个类型字段和 6 个导出函数／构造方法均有 JSDoc，并补充页面状态说明。

通过 Swift 可执行 token 对比（规范化组合字段和可选分号）及 TypeScript 语法树对比，确认仅增加注释和声明排版，没有更改运行逻辑。macOS arm64 与 iOS 通用模拟器构建成功，Swift 64 项测试中 60 项通过、4 项按默认配置跳过、零失败；前端 12 项测试通过，格式检查、本地化检查和 Git 空白检查通过。

## Now Playing 重新设计验收（2026-10-30）

已替换实心黑色圆盘为三键主控制，保留原来的 PlaybackCoordinator／PlaybackTimeline 和 SeekBar 行为。随机、循环、AirPlay、播放选项和队列独立分组；跳转、睡眠、A/B、均衡器和变速在原生菜单中可访问。按钮具备至少 44 pt 点击区域、按压反馈、禁用状态及本地化无障碍标签；持久模式同时带 selected trait，动画遵循 Reduce Motion。

实际检查 Mac 原生宽屏播放器、iPhone 15 Pro / iOS 17.4 浅色与深色横竖屏，以及 iPad Pro 11 英寸 / iPadOS 17.4 横竖屏。根据验收修正了 Mac sheet 默认窄宽度、低高度横屏底部信息溢出，以及 iPad 竖屏误用双栏的问题。检查最大辅助功能字号时切换为单列并正常换行；触摸滚动和滑块物理拖动不作为本次自动化界面验收通过项。进度协调回归测试通过，界面确认生成的静音曲目能够播放／暂停，菜单快进 10 秒后继续保持暂停，随机和循环的选中状态可被辅助功能读取。

macOS arm64 与 iOS 通用模拟器最终构建成功；Swift 64 项测试中 60 项通过、4 项按默认配置跳过、零失败。本地化检查覆盖 340 个键、3 种语言，英文成员／API 注释审计和 Git 空白检查通过。测试使用独立的 iMusicPlayerDesignQA 资料库与全零 PCM，不播放用户音乐；原有资料库保留，模拟器显示选项验收后恢复。

## View／ViewModel 拆分验收（2026-10-30）

移除 Features 聚合目录，按功能拆分 View 和 ViewModel。AppModel 改为无页面状态、非 Observable 的依赖组装入口；RootView 不包含页面主体、全局 sheet 实现或底部播放栏实现。RootViewModel 的导航选择按 scene 创建；搜索、表格选择、重命名／删除确认、编辑草稿、统计范围、均衡器与导出结果分别由对应 ViewModel 持有。ViewModel 不导入 SwiftUI，也不持有 AppModel／View／Binding；原生文件选择器和 NSSavePanel 只在 View 层呈现。

新增 7 项行为测试：页面搜索与选择隔离／共享资料库刷新、重复歌单条目的播放身份、编辑草稿保存语义、批量字段保留与 picker 选择隔离、scene 导航与播放器工具状态隔离、偏好重载、导出原子替换及结果隔离。默认 Swift 71 项测试中 67 项通过、4 项按配置跳过、零失败。测试注入不创建音频设备的 TestPlaybackEngine，实际界面使用独立 iMusicPlayerDesignQA 资料库；未播放用户歌曲、修改 Schema 或清理用户资料库。

macOS arm64 和 iOS 通用模拟器构建通过。实际检查 Mac sidebar 的 Home／All Songs／Settings 路由和 Now Playing 弹窗；iPhone 15 Pro / iOS 17.4 搜索 Morning 后仅保留 Morning Light，切换 Playlists 后返回仍保留关键词与结果，编辑标题为 Draft only 后取消，歌曲名称仍为 Morning Light；iPad Pro 11 英寸 / iPadOS 17.4 竖屏侧栏及横屏 All Songs 分栏可访问。英文语法树注释审计覆盖 511 个成员字段、155 个 public／协议方法、20 个 public 初始化方法，无缺失；340 个本地化键、3 种语言检查通过。完整拆分、状态所有权与新增页面规则见 Architecture.md。

## Swift 全仓格式化验收（2026-10-30）

使用 Xcode 26.3 自带 swift-format 6.2.3，对 85 个自有 Swift 文件统一格式，包括 Package.swift、App、包源码、测试、插件和图标生成脚本。原有 788 行超过 100 字符、最长 516 字符；格式化后所有物理行均不超过 100 字符。统一 4 空格缩进，拆开分号语句、长签名、参数和链式调用，重新排版英文注释。39 个长字面量转换为等值多行语法；SwiftParser／SwiftSyntax 比较全部 1,359 个字符串值和插值结构，零差异。App 入口类型按命名规则由 iMusicApp 改为 IMusicApp，应用显示名称、标识符和数据路径保持不变。

新增 `.swift-format` 和 `Scripts/swift_style.py`，全仓 lint 使用 `--strict`，另设无豁免的物理行宽检查；格式化重复执行结果一致，check 模式只读。通过临时源文件验证：formatter 本身无法拆分的长字符串会被行宽检查拒绝；多行本地化 key 缺少翻译时检查确实失败；空白、转义引号、反斜杠、Unicode 和续行均正确解码。VS Code 保存时格式化及全仓任务、GitHub Actions 检查已接入。

macOS arm64 与 iOS 通用模拟器构建成功。默认 Swift 71 项测试中 67 项通过、4 项按配置跳过、零失败，明确关闭硬件音频测试。本地化检查覆盖 340 个键、3 种语言；英文注释审计仍覆盖 511 个成员字段、155 个 public／协议方法、20 个 public 初始化方法，无缺失。Git 空白检查通过。

## Wi-Fi Upload React 模块拆分验收（2026-10-30）

App.tsx 从 426 行缩减为 38 行，仅负责配置、语言、配对会话和页面组件的连接。界面拆为 layout、pairing、upload、shared 下的 10 个组件；四个 hooks 分别负责配置请求、页面语言、配对会话和串行上传。domain 保存配置契约、队列 occurrence 类型和纯文件校验；services 保存 fetch／XHR 协议及错误消息映射。组件和 domain 不依赖网络服务，协议地址、HTTP 202 接收语义、三语言文案、响应式样式和原生资源打包流程保持一致。Props、模型字段及导出函数保留英文 JSDoc。

原有 12 项前端测试通过，并增加 9 项：配置失败后重试、网络失败后继续、授权失效重新配对后保留队列并使用新 token、StrictMode 下重复选择同一文件后独立删除、配对前拒绝拖放、忽略 StrictMode 旧配置响应、配对重复请求及卸载取消、上传串行和编辑门禁、卸载上传后不误报会话错误。共 21 项前端测试全部通过，TypeScript 类型检查、Vite 生产构建、Prettier 与本地化检查通过。翻译源检查递归覆盖子目录中的 TS／TSX，避免组件拆分后漏查。

macOS arm64 与 iOS 通用模拟器构建成功，SwiftPM 插件自动构建并打包新模块资源。默认 Swift 71 项测试中 67 项通过、4 项按配置跳过、零失败，包括 React 资源清单、MIME／CSP、配置接口、配对和上传字节一致性测试；未启用硬件播放测试。Swift 全仓风格检查和 Git 空白检查通过。目录与状态所有权说明已同步到 Web/WiFiUpload/README.md 和 Architecture.md。

## macOS 音量控制与跨进程恢复验收（2026-10-30）

Now Playing 和独立 MiniPlayerWindow 新增共享 VolumeControl，使用小扬声器图标、原生细滑块与静音切换，不显示可见百分比，不使用选中底色；辅助功能仍有本地化 Volume、Mute、Unmute 标签与当前值。线性增益经 PlaybackCoordinator → PlaybackEngine → SFBPlaybackEngine 的 mainMixerNode.outputVolume 实际应用。当前音量和静音前音量变化后立即保存到本机资料库，播放器重建前会重新应用；不改变设备音量、播放／暂停意图、现有 audio 偏好或数据库 Schema。

新增 5 项测试覆盖边界与非有限值、独立重开数据库恢复音量及静音、切歌和音频恢复、静音不改变播放状态、本机设置不进入可移植偏好、异常已存值的安全恢复。Swift 76 项测试中 72 项通过、4 项按配置跳过、零失败；macOS arm64 与 iOS 通用模拟器构建成功。343 个本地化键、3 种语言、英文成员／API 注释、Swift 格式和 Git 空白检查通过。

实际更新已安装的 macOS App 并检查最终样式。用原生音量辅助动作从 100% 调到 95%，退出并确认旧 PID 消失，新进程打开后恢复 95%；随后静音、再次退出重开，仍为 0，取消静音恢复 95%。全过程未播放用户歌曲，播放位置保持暂停在 0:07；验收后恢复初始 100% 音量。最终界面没有数字百分比标签。

## 真实 M4A 内嵌封面验收（2026-10-30）

通过已安装 macOS App 的 Import Music 原生文件选择器，实际导入用户指定的
`Music/HIMEHINA/相対二等心/Resistance!.m4a`，结果为成功导入 1 首、重复 0 首。
该文件为 AAC、44.1 kHz、双声道、224.839 秒；标题与专辑均为 Resistance!，
歌手为鈴木ヒナ(HIMEHINA)，内含 1600 × 1600 JPEG 封面。

用 ffmpeg 无损提取内嵌图片，与应用 Artwork 目录保存的 355,270 字节文件逐项比对，
两者 SHA-256 均为 `2d1c1003a1225dcab5fde1ff82b21a0717b74620c5c12ac98d02c08a55225284`。
导入前后原音频及应用 Media 目录副本的 SHA-256 均为
`925e4beb70c108b66b097672314445de4e65d034466c93b1e87ac2fe50d1ef71`，原文件未被修改。

实际截图检查首页 Recently Added、All Songs 表格、Albums 网格、底部 MiniPlayer
及 Now Playing 大封面，均显示与原文件一致的蓝色背景人物封面，没有退回音符占位图。
为避免音频输出，将原来唯一的暂停队列项移出队列，再把 Resistance! 加入空队列，
依靠 enqueue 的暂停选择行为打开 Now Playing；整个验收未启动播放，曲目停在 0:00，
时长正确显示 3:44，音量维持原来的 100%。歌曲已保留在用户资料库，当前暂停曲目为 Resistance!。

本次仅完成 macOS 真实文件导入和界面验收，没有发现需要修改的封面显示逻辑；
没有据此宣称 iPhone／iPad 的真实文件界面已验收，也没有重复运行与本次无代码修改无关的构建和测试。

## iPhone 菜单破音定位与播放验收（2026-10-30）

在连接的 iPhone 17／iOS 26.5.1 上，由用户实际听测 Now Playing 右上角“…”菜单的
反复展开／收起。相同 Debug 安装包在 Xcode／LLDB 附加时复现，脱离调试器启动时消失。
仅关闭 Thread Performance Checker 不解决问题，原 Scheme 的诊断设置已完整恢复。
最初的变速旁路及 I/O 缓冲参数实验亦未解决此现象，实验代码已撤回，没有保留为所谓修复。

通过 Xcode 调试控制台启用临时 GDB remote packet 日志，捕获到内部 shared-library-event、
thread-creation 断点以及单线程 resume／step 往返；符号化和 breakpoint list -i 确认涉及
dyld 的 lldb_image_notifier、libsystem_pthread 的 start_wqthread／_pthread_wqthread／
_pthread_start。菜单操作期间的调试器内部暂停会连带影响实时音频，不能以延长应用缓冲
承诺进程被调试暂停时仍能连续供音。LLDB 的内部线程断点实现可对照
[LLVM PlatformDarwin 源码](https://lldb.llvm.org/cpp_reference/PlatformDarwin_8cpp_source.html)。

新增共享 iMusic Playback／iMusicMac Playback Scheme，仍采用相同 Debug 配置，Run 使用
PosixSpawn 且不附加 LLDB；iMusic／iMusicMac 保留断点调试及原有检查器。生成工程的 Ruby
脚本同时生成这两个方案，避免重建工程后丢失。已在 Xcode 选择 iMusic Playback，实际安装
并启动 iPhone 17，用户再次确认相同菜单开关“已无破音”。此结论不声称附加 LLDB 后消除了
调试器对进程的暂停，也不声称已经在 iPad／Mac 完成同场景听测。

同时修正三个实际的 UI／存储问题：100 ms 采样不再改写整个队列状态，持久化副本仍包含最新
时钟位置；五秒周期保存和收听事件编码／写入移到 GRDB 串行 writer，暂停后不空转写库；
原生菜单和歌曲表格的文件存在性判断改为读取后台资料库刷新发布的快照。封面占位符对菜单
快照阶段的零尺寸布局使用正数字号与最小缩略图尺寸，避免 CoreUI 报告零字号音符。

新增四项无硬件回归测试覆盖：时钟推进不触发队列观察者且保存最新位置、后台检查点与显式
保存的顺序、失败检查点对收听事件和会话的原子回滚、文件可用性快照的刷新语义。另增加一项
显式启用的静音硬件测试：UI 主 actor 连续忙碌 600 ms 时引擎媒体时钟仍正常推进；该测试
验证主线程独立性，不被用来冒充声音波形或 LLDB 场景验收。

默认 Swift 81 项测试中 76 项通过、5 项按默认配置跳过、零失败。macOS arm64 和签名 iOS
真机构建通过；343 个本地化键／3 种语言与英文声明注释审计通过。本次未修改数据库 Schema
或重置资料库，未将用户原有 HomeView 的未提交修改纳入本次提交。
本次修改的 Swift 文件严格格式检查及 100 字符行宽检查通过；全仓检查仅在上述用户原有
HomeView 注释块的缩进处报错，未擅自格式化或覆盖该未提交修改。
