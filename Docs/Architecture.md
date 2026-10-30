# 架构

## 依赖与边界

两个原生应用目标共享本地 SPM 产品 `iMusicKit`。包内按 Application、Domain、Library、Playback、Import、Sync、Platform、View、ViewModel 分层。第三方版本由根目录及 Xcode 工作区的 `Package.resolved` 锁定。AppModel 只在启动时组装依赖、连接平台回调并执行一次性恢复；页面不再绑定 AppModel。View 绑定相应的 ViewModel，不直接操作 SQL 或音频节点。

- Domain：纯值类型 Track、Playlist、QueueEntry、PlaybackSession、PlaybackTimeline、字段版本、歌手解析。
- Library：GRDB/SQLite WAL、统一初始 Schema、FTS5 与 CJK 子串查询、托管文件、备份、标签覆盖、在线封面。
- Playback：唯一进程级播放会话、SFBAudioEngine 适配、预加载、音效、睡眠、音频时钟和进度预览。
- Import：actor 串行导入、分块复制、SHA-256、恢复日志、文件夹书签、增量扫描、局域网上传。
- Sync：元数据与大文件分区；CKSyncEngine、版本合并、持久化 outbox、按需资产下载。
- Platform：锁屏／控制中心、音频中断／路由变化、CoreAudio 输出名称、CarPlay 系统模板。
- Application：进程级依赖组装与启动，不保存搜索、选择、编辑草稿或弹窗开关。
- View：按功能归类的 SwiftUI 页面、组件和平台呈现适配。
- ViewModel：同样按功能归类的可观察页面状态、查询结果、编辑草稿与交互操作。

## 界面与状态所有权

```text
Sources/iMusicKit/
├── Application/AppModel.swift        # composition and startup
├── Domain/                          # values, routes, search matching
├── View/
│   ├── Navigation/                  # Root, Destination, presentations, footer
│   ├── Home/                        # Home
│   ├── Library/                     # songs, collections, duplicates
│   ├── Player/                      # full/mini player, queue, EQ, seek, AirPlay
│   ├── Editors/                     # track, bulk, playlist, song picker
│   ├── Import/                      # Wi-Fi, import report, export
│   ├── Settings/                    # settings and Home layout
│   ├── Statistics/                  # listening charts
│   └── Shared/                      # artwork, song row, song actions, search modifier
└── ViewModel/
    ├── Navigation/                  # scene navigation and cross-feature presentation
    ├── Home/, Library/, Player/      # page state and derived results
    ├── Editors/                     # independent editable copies
    ├── Import/, Settings/, Statistics/
    └── Shared/                      # library snapshot/actions and operation status
```

| 边界 | 所有者及职责 | 生命周期 |
| --- | --- | --- |
| 依赖组装 | AppModel：创建存储、导入器、音频、云和 feature models；连接系统媒体及云回调 | 应用进程 |
| 资料库 | LibraryViewModel：共享记录快照、刷新代次保护、歌曲／歌单事务、回收站和重复项操作 | 应用进程 |
| 播放 | PlaybackCoordinator：唯一音频会话；PlayerViewModel：播放页面使用的明确依赖 | 应用进程，共享队列 |
| 偏好 | PreferencesViewModel：持久化外观、字体、Home 布局、歌手拆分和联网许可 | 应用进程 |
| 导入与归档 | ImportViewModel：原生文件选择用途、导入任务、进度报告、Wi-Fi、备份与诊断导出 | 跨页面任务 |
| 跨功能呈现 | PresentationViewModel：请求打开播放器、队列或某首歌曲的编辑器；不存编辑草稿 | 跨页面请求 |
| 页面状态 | SongList／Collection／Settings 等 ViewModel：本页查询、选择、确认、范围与结果 | 页面实例 |
| 编辑器 | TrackEditor／BatchTrackEditor／PlaylistEditor／PlaylistSongPicker ViewModel：草稿、预览、选择及异步结果 | 每次打开独立实例 |
| 全播放器工具 | NowPlayingViewModel：均衡器弹窗；复用 PlayerViewModel 的播放会话 | 每个全播放器实例 |
| 导出文件 | BackupExportViewModel：复制进度、原子替换和结果信息 | 每个导出 sheet |
| 导航 | RootViewModel：每个窗口自己的 sidebar selection；DestinationViewModel：本路由新建歌单草稿 | 每个 scene／路由 |

RootView 只选择 iPhone TabView 或 iPad／Mac NavigationSplitView 并转发生命周期。AppPresentations 统一挂载跨页面 sheet／文件选择器；LibraryFooter 呈现导入进度、播放错误和 MiniPlayer。页面主体、编辑器、播放器组件分别位于单独文件。根视图的公开初始化入口接收 AppModel 仅用于创建 scene-local RootViewModel；子页面不引用、继承或持有 AppModel。

有独立页面状态的 View 使用 `@State` 保持自己的 `@Observable` ViewModel 身份，使用 `@Bindable` 提供原生控件绑定。复用共享偏好或播放状态的组件只接收对应 feature model 或 PlaybackCoordinator。物理滑块拖动标记、环境尺寸和 dismiss 等呈现细节保留在 View；播放时钟仍由 PlaybackCoordinator／PlaybackTimeline 管理，不建立第二份时间副本。

搜索框与查询属于具体页面及其 ViewModel。歌曲列表只筛选当前路由中的歌曲；歌单列表只搜索歌单名。不同页面／picker 的查询和选择独立。iPhone 切换 Tab 时保留各页面状态，Mac 切换 sidebar 路由时用路由 identity 创建对应页面状态。编辑器只修改本次草稿，保存时调用资料库操作；取消不会提交标签。编辑、解码修复、在线封面请求和封面文件读取由编辑器 ViewModel 执行。

新增功能遵守单向依赖：`View → ViewModel → existing domain/services`。不要把页面状态放回 AppModel、给所有页面传整个 application container，或将 SwiftUI View／Binding／NSSavePanel 导入 ViewModel。跨功能共享记录和播放会话应复用现有 feature boundary；新查询、编辑草稿和展示结果应留在本页面模型。SwiftPM 自动发现这些目录下的源码，不需要给 Xcode 工程逐文件登记，也不增加依赖。

## 播放

PlaybackCoordinator 持有唯一队列。队列条目与歌曲分别有 UUID，允许同一歌曲在歌单中出现多次。自动单曲循环不改变手动下一首行为；随机顺序和实际历史可持久化。

PlaybackCoordinator 依赖 PlaybackEngine 协议，App 默认注入 SFBPlaybackEngine。自动化逻辑测试显式注入不创建声卡或 AVAudioEngine 的测试实现；真实音频引擎的集成测试仅在 `IMUSIC_AUDIO_TESTS=1` 时运行，全部生成素材为静音 PCM。普通测试和编译不播放测试音。

每次显式加载更换底层 AudioPlayer 身份，旧回调通过身份检查丢弃。预加载解码器的对象身份映射保留到真正切换，避免首曲回调误删下一首。自动失败尝试有上界；手动失败显示原因。

UI 时长未知时为 `--:--`，进度为零并禁用 seek。实际位置来自解码器媒体时间，不用计时器累加。滑块预览与实际时钟分离；提交 seek 后有短期确认门，避免旧位置回弹。位置及比例始终有限且有界。暂停、下载、路由和媒体服务重置遵守用户播放意图。立即暂停优先于已经排队的开始回调；显式选择下一曲会建立新的播放意图，下载后继续播放，中断后可按系统许可恢复。

同格式音频预加载由 SFBAudioEngine 提供无缝连续渲染。混合采样率／声道会重配图，不声称采样级无缝。均衡器预留正增益余量，TimePitch 处理变速，AudioRegionDecoder 提供 A/B 区间循环。

收听事件使用每次播放会话的稳定 ID，定期更新累计实际收听秒数，避免每五秒创建一条永久统计记录。暂停与 seek 跳过的媒体时长不计入实际收听。

## 文件与事务

数据库以单个 `initial-schema` 初始化步骤创建当前完整结构：records、outbox、settings、FTS5 搜索表及维护触发器。发布前的 `v1-library`／`v2-search` 开发历史已合并，不提供旧开发数据库的升级路径，开发安装通过卸载并清理应用数据后重装。保留 GRDB 建库登记机制，后续正式发布后的结构变化再新增迁移；运行时不会自动删除不兼容数据库。

默认文件位于 Application Support/iMusic；沙盒签名构建由系统映射到应用容器。Media、Artwork 属于持久资料库，不是可清除缓存。iOS 使用首次解锁后可访问的数据保护类别，支持锁屏后的持续播放。

导入先记录日志，流式复制到 Staging，探测元数据并计算哈希，将可恢复的 Track 写入日志，再移动文件并提交 SQL。成功后清除日志。启动恢复不依赖原文件的临时授权。未知文件不会被自动清理。

关联目录保存安全作用域书签；分块读取使用文件协调。文件夹新增／修改会复制到托管资料库，原件保留。相同大小／修改时间且托管副本仍存在的扫描项目可跳过；显式重新导入仍执行内容校验。来源被移除不会删除托管副本。

Wi-Fi 使用用户显式启动的 NWListener/NIO HTTP 服务，随机六位配对码、有限错误尝试和随机会话令牌。仅提供上传，无资料库读取接口。跨源请求被拒绝；文件名限制为单一组件。请求体流式写盘，完成标记写入后才返回接收成功；进程中断后可恢复完整上传。iOS 进入后台关闭服务。

上传网页是 `Web/WiFiUpload` 中独立的 React + TypeScript + Vite 工程。`WiFiUploadBuild` SwiftPM 构建插件运行前端类型检查和生产构建，使用源码、翻译目录与锁文件指纹复用构建结果；输出写入插件工作目录，由 SwiftPM 自动打入 `Bundle.module`。Swift 不再拼接 HTML。`WiFiUploadResources` 按构建清单加载资源并提供固定路径映射；`GET /api/config` 提供应用语言、扩展名白名单和大小限制。JS／CSS 同源加载，CSP 不允许内联脚本或样式。上传令牌只保存在网页内存，XHR 提供传输进度与取消，HTTP 202 表示已接收，最终导入结果在 App 内确认。

React 页面按 `components`、`hooks`、`domain`、`services` 拆分。App.tsx 只组装页面；配对表单保留本地输入草稿，UploadPanel 的队列 hook 独立于认证会话，配对失效和重新认证不会清空队列。展示组件不执行网络请求，domain 不依赖 React 或网络服务；配置、配对、上传请求各自有取消与迟到结果保护。完整组件树和状态所有权见 [Wi-Fi Upload 源码结构](../Web/WiFiUpload/README.md#源码结构与职责)。

## 回收站与永久删除

歌曲先标记 `deletedAt` 进入可恢复的回收站。iOS／iPadOS 使用原生 List 的尾部滑动操作展示恢复和删除，禁用整行快速滑到底直接执行；永久删除另有确认弹窗。Mac 使用表格选择和右键操作。

永久删除只接受回收站记录：在一个 SQL 事务中设置 `permanentlyDeletedAt`、写入 outbox，并清理所有歌单（含回收站歌单）和保存的队列引用。此标记是不可逆的合并状态，不能被旧版本记录或同库旧备份清除。随后停止相关播放／下载会话并清理托管副本；若中断或文件操作失败，下次启动根据删除标记继续清理。

物理删除只作用于 Media／Artwork 中的单个文件，并检查真实父目录。共享同一音频或封面的其他可恢复记录、歌单仍保留该文件；叶子符号链接仅删除链接，目录被替换为外部链接时拒绝操作。来源目录、文件夹书签和原始音乐从不参与删除。

永久删除标记随资料库同步，其他设备接收后清理自己的托管副本。迟到的云下载写文件前通过同一个数据库写锁重新确认记录仍可用。CloudKit 资产及应用外备份不执行物理删除。自动文件夹扫描不重新加入已永久删除的相同内容；显式 Import Music 可以使用新歌曲 ID 重新导入。

## SQLite 与同步

当前统一初始结构保存类型化 JSON、字段版本、查询字段、哈希、设置、outbox、FTS5 及维护触发器；重构界面不改变数据库结构，也不清理现有资料库。CJK 和任意子串通过规范化 LIKE 补充，用户原文始终保留。

字段版本使用单调递增逻辑值和设备标识，冲突按字段确定性合并。PlaylistEntry 使用独立条目版本、位置和删除标记：离线并发添加不会覆盖另一设备添加的歌曲。传输将逻辑记录压缩为 LZFSE，避免一万首歌单超过单记录预算；过大记录留在本机并报告错误。

本地记录和 outbox 在同一 SQL 事务提交。发送快照带 generation，旧发送确认不能删除新修改。CKRecord 的系统字段及同步状态按容器／iCloud 账号隔离保存。账号切换暂停同步；跨重启检测到新账号时也必须明确启用。

元数据区和资产区分离。获取音乐是否已存在时只获取系统字段，不能下载整个音频。音频下载先校验 SHA-256，再放入本地库；普通元数据刷新不应拉取音乐文件。活动队列、路径和书签不跨设备同步。

## 本地化

`L10n` 从包资源读取英文、简体、繁体文案，UI 与服务层共享；数量使用位置参数和英文复数规则。稳定偏好标识与显示语言分离，旧标识通过兼容资源映射。详情见 [Localization.md](Localization.md)。

## 扩展方向

可将包内各层拆为独立 SPM target；PlaybackEngine 已隔离第三方接口。歌词时间轴、App Intents、WidgetKit 和 watchOS 应消费领域状态／命令，不能创建第二个独立播放器。

强调色遵循各平台系统默认行为；使用原生导航和选择控件，不提供应用内强调色选择器，不覆盖原生选中背景，也不声明固定的 AccentColor 资源。

## Now Playing 界面

`View/Player/NowPlayingView.swift` 独立负责全播放器的视觉层与自适应布局。封面、歌曲信息、时间轴、三键主控制和次级工具依次分组；不改写 PlaybackCoordinator 或 PlaybackTimeline。窄屏／竖屏及辅助功能字号使用可滚动单列；宽屏横向空间充足时采用封面与控制区双栏，低高度窗口缩小间距而保留至少 44 pt 点击区域。

主控制使用系统语义色的 SF Symbols，不使用永久实心圆盘；按压反馈尊重 Reduce Motion。随机和循环同时提供选中背景及无障碍 selected trait，非活动功能正确禁用。AirPlay 与队列可直接访问；十秒跳转、睡眠、A/B、均衡器和变速通过原生播放选项菜单提供，活动选项仍在界面显示。强调色、浅深模式和界面文案继续使用系统与本地化资源。

设计参考：[Apple Music 播放控制](https://support.apple.com/en-gb/guide/iphone/iph676daac9b/ios)、[Spotify Now Playing](https://support.spotify.com/kr-en/article/now-playing/)、[Apple HIG 按钮](https://developer.apple.com/design/human-interface-guidelines/buttons)及[无障碍](https://developer.apple.com/design/human-interface-guidelines/accessibility)。这些资料指导分组与交互，页面按 iMusic 的本地播放功能实现。
