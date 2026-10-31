# 架构

## 依赖与边界

两个原生应用目标共享本地 SPM 产品 `iMusicKit`。包内按 Application、Domain、Library、Playback、Import、Sources、Sync、Platform、View、ViewModel 分层。第三方版本由根目录及 Xcode 工作区的 `Package.resolved` 锁定。AppModel 只在启动时组装依赖、连接平台回调并执行一次性恢复；页面不再绑定 AppModel。View 绑定相应的 ViewModel，不直接操作 SQL 或音频节点。

- Domain：纯值类型 Track、Playlist、QueueEntry、PlaybackSession、PlaybackTimeline、字段版本、歌手解析。
- Library：GRDB/SQLite WAL、统一初始 Schema、FTS5 与 CJK 子串查询、托管文件、备份、标签覆盖、在线封面。
- Playback：唯一进程级播放会话、SFBAudioEngine 适配、预加载、音效、睡眠、音频时钟和进度预览。
- Import：actor 串行导入、分块复制、SHA-256、恢复日志、文件夹书签、增量扫描、局域网上传。
- Sources：原文件索引、系统物化与协调、安全作用域、后台解码器准备、逐曲定位和当前源观察。
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
| 资料库 | LibraryViewModel：共享快照与刷新代次保护；LibraryCommands：歌曲／歌单修改；LibraryDeletionWorkflow：确认后的永久删除 | 应用进程 |
| 播放 | PlaybackCoordinator：唯一音频会话；PlayerViewModel：播放页面使用的明确依赖 | 应用进程，共享队列 |
| 偏好 | PreferencesViewModel：持久化外观、字体、Home 布局、歌手拆分和联网许可 | 应用进程 |
| 导入与归档 | ImportViewModel：原生文件选择用途、导入任务、进度报告、Wi-Fi、备份与诊断导出 | 跨页面任务 |
| 跨功能呈现 | PresentationViewModel：请求打开播放器、队列或某首歌曲的编辑器；不存编辑草稿 | 跨页面请求 |
| 页面状态 | SongCollection／PlaylistDetail／TrashSongs／Collection／Settings 等 ViewModel：本页查询、选择、确认、范围与结果 | 页面实例 |
| 编辑器 | TrackEditor／BatchTrackEditor／PlaylistEditor／PlaylistSongPicker ViewModel：草稿、预览、选择及异步结果 | 每次打开独立实例 |
| 全播放器工具 | NowPlayingViewModel：均衡器弹窗；复用 PlayerViewModel 的播放会话 | 每个全播放器实例 |
| 导出文件 | BackupExportViewModel：复制进度、原子替换和结果信息 | 每个导出 sheet |
| 导航 | RootViewModel：每个窗口自己的 sidebar selection；DestinationViewModel：本路由新建歌单草稿 | 每个 scene／路由 |

RootView 只选择 iPhone TabView 或 iPad／Mac NavigationSplitView 并转发生命周期。AppPresentations 统一挂载跨页面 sheet／文件选择器；LibraryFooter 呈现导入进度、播放错误和 MiniPlayer。页面主体、编辑器、播放器组件分别位于单独文件。根视图的公开初始化入口接收 AppModel 仅用于创建 scene-local RootViewModel；子页面不引用、继承或持有 AppModel。

有独立页面状态的 View 使用 `@State` 保持自己的 `@Observable` ViewModel 身份，使用 `@Bindable` 提供原生控件绑定。复用共享偏好或播放状态的组件只接收对应 feature model 或 PlaybackCoordinator。物理滑块拖动标记、环境尺寸和 dismiss 等呈现细节保留在 View；播放时钟仍由 PlaybackCoordinator／PlaybackTimeline 管理，不建立第二份时间副本。

搜索框与查询属于具体页面及其 ViewModel。歌曲列表只筛选当前路由中的歌曲；歌单列表只搜索歌单名。不同页面／picker 的查询和选择独立。iPhone 切换 Tab 时保留各页面状态，Mac 切换 sidebar 路由时用路由 identity 创建对应页面状态。编辑器只修改本次草稿，保存时调用资料库操作；取消不会提交标签。编辑、解码修复、在线封面请求和封面文件读取由编辑器 ViewModel 执行。

新增功能遵守单向依赖：`View → ViewModel → existing domain/services`。不要把页面状态放回 AppModel、给所有页面传整个 application container，或将 SwiftUI View／Binding／NSSavePanel 导入 ViewModel。跨功能共享记录和播放会话应复用现有 feature boundary；新查询、编辑草稿和展示结果应留在本页面模型。SwiftPM 自动发现这些目录下的源码，不需要给 Xcode 工程逐文件登记，也不增加依赖。

### 歌曲列表基础能力与功能扩展

SwiftUI 的 View 是值类型，列表使用泛型组合与能力协议，不使用 UIViewController 式的
视图基类继承。`View/Library/SongList/` 中的 `SongListView` 只负责统计、居中空态、
macOS Table、iPhone／iPad List、选择与排序绑定。它通过 ViewBuilder 接收行、统计栏操作、
空态与上下文菜单，并通过可选闭包接收重排与激活操作；不接收 LibraryDestination，
也不判断是否为回收站或歌单。

- `AllSongsView`：拥有分类快捷入口，组合普通歌曲列表。
- `SongCollectionView`／`SongCollectionViewModel`：所有歌曲、收藏及歌手／专辑／流派筛选。
- `PlaylistDetailView`／`PlaylistDetailViewModel`：歌单条目移除、重排、排序、重命名和编辑器。
- `TrashSongsView`／`TrashSongsViewModel`：恢复、永久删除和确认弹窗，不依赖播放器。
- `ViewModel/Library/SongList/SongListState`：每页各自持有搜索、排序和选择；共享过滤、
  排序和选择解析。`PlayableSongList` 协议只为活跃歌曲列表提供保留条目身份的播放能力。

新增列表场景应组合基础列表并提供本场景的行与操作；不要向基础组件添加场景标志、路由
分支或业务弹窗。歌单使用 QueueEntry.id 标识每个出现位置；移除和播放不得退化为 Track.id。
过滤、排序或存在隐藏失效条目时禁用按索引重排，避免修改不对应的条目。Trash 的原生搜索框
继续由分类页持有独立绑定，避免 UISearchController 在切换分类与退出搜索时发生布局循环。

## 播放

PlaybackCoordinator 持有唯一队列。队列条目与歌曲分别有 UUID，允许同一歌曲在歌单中出现多次。自动单曲循环不改变手动下一首行为；随机顺序和实际历史可持久化。

PlaybackCoordinator 依赖 PlaybackEngine 协议，App 默认注入 SFBPlaybackEngine。自动化逻辑测试显式注入不创建声卡或 AVAudioEngine 的测试实现；真实音频引擎的集成测试仅在 `IMUSIC_AUDIO_TESTS=1` 时运行，全部生成素材为静音 PCM。普通测试和编译不播放测试音。

每次显式加载更换底层 AudioPlayer 身份，旧回调通过身份检查丢弃。预加载解码器的对象身份映射保留到真正切换，避免首曲回调误删下一首。自动失败尝试有上界；手动失败显示原因。

UI 时长未知时为 `--:--`，进度为零并禁用 seek。实际位置来自解码器媒体时间，不用计时器累加。滑块预览与实际时钟分离；提交 seek 后有短期确认门，避免旧位置回弹。位置及比例始终有限且有界。暂停、下载、路由和媒体服务重置遵守用户播放意图。立即暂停优先于已经排队的开始回调；显式选择下一曲会建立新的播放意图，下载后继续播放，中断后可按系统许可恢复。

100 ms 时钟采样仅更新 PlaybackTimeline，不改写整个 PlaybackSession，避免仅依赖队列／
随机／循环状态的菜单随进度刷新。持久化时创建含最新 timeline.elapsed 的会话副本；普通恢复和
下载后继续同样使用 timeline。播放期间的五秒检查点通过 GRDB asyncWrite 在串行 writer 上
原子保存会话和稳定 ID 的收听事件，编码和 SQL 均不在主线程执行；与显式同步保存共用同一
writer 顺序，防止旧后台位置覆盖新的暂停／seek。暂停后不执行空转周期写入。

LibraryViewModel 在后台刷新中检测托管文件并发布 availableTrackIDs 快照。歌曲表格和原生
菜单只读取此集合，渲染时不调用 fileExists。导入、云下载和清理后的刷新更新这份可用性信息。

同格式音频预加载由 SFBAudioEngine 提供无缝连续渲染。混合采样率／声道会重配图，不声称采样级无缝。均衡器预留正增益余量，TimePitch 处理变速，AudioRegionDecoder 提供 A/B 区间循环。

收听事件使用每次播放会话的稳定 ID，定期更新累计实际收听秒数，避免每五秒创建一条永久统计记录。暂停与 seek 跳过的媒体时长不计入实际收听。

macOS 的 Now Playing 与独立 MiniPlayerWindow 复用 VolumeControl：小扬声器图标、原生细滑块和静音切换，界面不显示百分比；辅助功能仍可读出音量。PlaybackCoordinator 持有 0…1 的应用音量及静音前的音量，变化时立即写入资料库 settings 的本机 `playbackVolume` 项，关闭进程后重新打开仍恢复。该项不属于可移植备份偏好，不更改数据库 Schema。SFBPlaybackEngine 通过 mainMixerNode.outputVolume 应用增益，重建播放器时在开始播放前重新应用，切歌、预加载及音频恢复不重置音量；不修改系统设备音量，也不通过改变均衡器来模拟音量。

## 文件与事务

数据库以单个 `initial-schema` 初始化步骤创建当前完整结构：records、outbox、settings、FTS5 搜索表及维护触发器。发布前的 `v1-library`／`v2-search` 开发历史已合并，不提供旧开发数据库的升级路径，开发安装通过卸载并清理应用数据后重装。保留 GRDB 建库登记机制，后续正式发布后的结构变化再新增迁移；运行时不会自动删除不兼容数据库。

默认文件位于 Application Support/iMusic；沙盒签名构建由系统映射到应用容器。Media、Artwork 属于持久资料库，不是可清除缓存。托管文件在 iOS 使用首次解锁后可访问的数据保护类别，支持锁屏后的持续播放；外部来源仍遵守其所有者和文件提供者的保护规则。

导入先记录日志，流式复制到 Staging，探测元数据并计算哈希，将可恢复的 Track 写入日志，再移动文件并提交 SQL。成功后清除日志。启动恢复不依赖原文件的临时授权。未知文件不会被自动清理。

关联目录使用独立的原文件索引和元数据管线，不调用复制导入。系统下载云端内容后直接解析原文件；播放在后台协调打开解码器，安全作用域随解码器保留。文件绑定和恢复任务使用现有 settings 的本机命名空间，歌曲使用稳定 UUID 与 linkedSource 描述；不需要新增表、迁移或清空当前资料库。移动／失败状态可重新授权和逐曲修复。详见 [Link Folder 实施说明](LinkedFolderPlaybackPlan.md)。

Wi-Fi 使用用户显式启动的 NWListener/NIO HTTP 服务，随机六位配对码、有限错误尝试和随机会话令牌。仅提供上传，无资料库读取接口。跨源请求被拒绝；文件名限制为单一组件。请求体流式写盘，完成标记写入后才返回接收成功；进程中断后可恢复完整上传。iOS 进入后台关闭服务。

SwiftNIO 暂时精确锁定为 `2.103.0`。`2.104.0` 的 HTTP 管线初始化会在 iOS 17 的 Swift 运行时中触发 `ByteToMessageHandler` 协议类型转换崩溃，见 [上游问题 #3764](https://github.com/apple/swift-nio/issues/3764)。等待修复版正式发布并通过 iOS 17 运行时验证后再解除锁定；仅在新版 macOS 或 iOS 上运行网络测试不能覆盖该问题。升级验收必须包含浏览器首次连接、JS/CSS 资源加载、配对、上传，以及 App 内实际导入结果。

上传网页是 `Web/WiFiUpload` 中独立的 React + TypeScript + Vite 工程。`WiFiUploadBuild` SwiftPM 构建插件运行前端类型检查和生产构建，使用源码、翻译目录与锁文件指纹复用构建结果；输出写入插件工作目录，由 SwiftPM 自动打入 `Bundle.module`。Swift 不再拼接 HTML。`WiFiUploadResources` 按构建清单加载资源并提供固定路径映射；`GET /api/config` 提供应用语言、扩展名白名单和大小限制。JS／CSS 同源加载，CSP 不允许内联脚本或样式。上传令牌只保存在网页内存，XHR 提供传输进度与取消，HTTP 202 表示已接收，最终导入结果在 App 内确认。

React 页面按 `components`、`hooks`、`domain`、`services` 拆分。App.tsx 只组装页面；配对表单保留本地输入草稿，UploadPanel 的队列 hook 独立于认证会话，配对失效和重新认证不会清空队列。展示组件不执行网络请求，domain 不依赖 React 或网络服务；配置、配对、上传请求各自有取消与迟到结果保护。完整组件树和状态所有权见 [Wi-Fi Upload 源码结构](../Web/WiFiUpload/README.md#源码结构与职责)。

## 回收站与永久删除

`TrashView` 使用原生分段页签分别显示歌曲与歌单，`TrashViewModel` 保留选中页签及两个子页面的独立状态。歌曲页复用 `SongListView` 的表格／原生列表，歌单页由 `TrashPlaylistsView` 和 `TrashPlaylistsViewModel` 管理；后者不会渲染歌曲列或时长。两个页面各自保留搜索词、数量、空态和删除确认。搜索控件跟随对应子页创建和销毁，查询保存在各自的子模型中。macOS 使用工具栏中的 `NSSearchField`，iPhone／iPad 使用内容区内的 `UISearchTextField`，以原生编辑回调更新查询，不依赖导航栏搜索控制器的呈现和清空生命周期。字段保留系统外观、清除按钮和辅助功能，触屏高度随动态字体缩放。空态在页签与统计栏下方的内容区居中，设置入口同时显示两类回收站数量。

歌曲先标记 `deletedAt` 进入可恢复的回收站。iOS／iPadOS 使用原生 List 的尾部滑动操作展示恢复和删除，禁用整行快速滑到底直接执行；永久删除另有确认弹窗。Mac 使用表格选择和右键操作。

歌曲永久删除只接受回收站记录：在一个 SQL 事务中设置 `permanentlyDeletedAt`、写入 outbox，并清理所有歌单（含回收站歌单）和保存的队列引用。此标记是不可逆的合并状态，不能被旧版本记录或同库旧备份清除。随后停止相关播放／下载会话并清理托管副本；若中断或文件操作失败，下次启动根据删除标记继续清理。

歌单永久删除同样只接受回收站记录。iPhone／iPad 左滑展示恢复与删除，macOS 提供行内按钮和右键菜单；删除前显示包含歌单名称的确认弹窗。事务清空该歌单的 `entries`，设置 `permanentlyDeletedAt` 并写入 outbox；不修改歌曲记录、音频文件、其他歌单或当前播放队列。删除标记不出现在资料库或回收站，但参与同步和备份合并，防止旧备份或离线编辑恢复歌单及其条目。新增字段位于现有 JSON payload 中，无需修改 SQLite 表结构。

物理删除只作用于 Media／Artwork 中的单个文件，并检查真实父目录。共享同一音频或封面的其他可恢复记录、歌单仍保留该文件；叶子符号链接仅删除链接，目录被替换为外部链接时拒绝操作。来源目录、文件夹书签和原始音乐从不参与删除。

永久删除标记随资料库同步，其他设备接收后清理自己的托管副本。迟到的云下载写文件前通过同一个数据库写锁重新确认记录仍可用。CloudKit 资产及应用外备份不执行物理删除。自动扫描不会复活已永久删除的同一关联文件引用，托管导入继续使用内容哈希删除历史；显式 Import Music 可以使用新歌曲 ID 重新导入。

## SQLite 与同步

当前统一初始结构保存类型化 JSON、字段版本、查询字段、哈希、设置、outbox、FTS5 及维护触发器；重构界面不改变数据库结构，也不清理现有资料库。CJK 和任意子串通过规范化 LIKE 补充，用户原文始终保留。

字段版本使用单调递增逻辑值和设备标识，冲突按字段确定性合并。PlaylistEntry 使用独立条目版本、位置和删除标记：离线并发添加不会覆盖另一设备添加的歌曲。传输将逻辑记录压缩为 LZFSE，避免一万首歌单超过单记录预算；过大记录留在本机并报告错误。

本地记录和 outbox 在同一 SQL 事务提交。发送快照带 generation，旧发送确认不能删除新修改。CKRecord 的系统字段及同步状态按容器／iCloud 账号隔离保存。账号切换暂停同步；跨重启检测到新账号时也必须明确启用。

元数据区 iMusicMetadataV2 和资产区 iMusicAssets 分离；升级后一次性读取旧 iMusicMetadata，不向旧区域写入新来源格式。获取音乐是否已存在时只获取系统字段，不能下载整个音频。音频下载先校验 SHA-256，再放入本地库；普通元数据刷新不应拉取音乐文件。活动队列、路径和书签不跨设备同步。

## 本地化

`L10n` 从包资源读取英文、简体、繁体文案，UI 与服务层共享；数量使用位置参数和英文复数规则。稳定偏好标识与显示语言分离，旧标识通过兼容资源映射。详情见 [Localization.md](Localization.md)。

## 扩展方向

可将包内各层拆为独立 SPM target；PlaybackEngine 已隔离第三方接口。歌词时间轴、App Intents、WidgetKit 和 watchOS 应消费领域状态／命令，不能创建第二个独立播放器。

强调色遵循各平台系统默认行为；使用原生导航和选择控件，不提供应用内强调色选择器，不覆盖原生选中背景，也不声明固定的 AccentColor 资源。

## Now Playing 界面

`View/Player/NowPlayingView.swift` 独立负责全播放器的视觉层与自适应布局。封面、歌曲信息、时间轴、三键主控制和次级工具依次分组；不改写 PlaybackCoordinator 或 PlaybackTimeline。窄屏／竖屏及辅助功能字号使用可滚动单列；宽屏横向空间充足时采用封面与控制区双栏，低高度窗口缩小间距而保留至少 44 pt 点击区域。

主控制使用系统语义色的 SF Symbols，不使用永久实心圆盘；按压反馈尊重 Reduce Motion。随机和循环同时提供选中背景及无障碍 selected trait，非活动功能正确禁用。AirPlay 与队列可直接访问；十秒跳转、睡眠、A/B、均衡器和变速通过原生播放选项菜单提供，活动选项仍在界面显示。强调色、浅深模式和界面文案继续使用系统与本地化资源。

设计参考：[Apple Music 播放控制](https://support.apple.com/en-gb/guide/iphone/iph676daac9b/ios)、[Spotify Now Playing](https://support.spotify.com/kr-en/article/now-playing/)、[Apple HIG 按钮](https://developer.apple.com/design/human-interface-guidelines/buttons)及[无障碍](https://developer.apple.com/design/human-interface-guidelines/accessibility)。这些资料指导分组与交互，页面按 iMusic 的本地播放功能实现。

## SOLID 边界与扩展方式

本轮审计覆盖 Sources、Apps 和 Wi-Fi Upload 前端。按变化原因拆分职责，保留真正需要共享的
播放状态机和数据库事务；不使用行数作为职责是否单一的唯一判断，也不为每个数据类型创建
空接口。SwiftUI 使用值类型组合和能力协议，服务通过窄接口替换。无新增第三方依赖、Schema
迁移、用户偏好键变更或音频文件所有权变更。

| 审计发现 | 当前所有者与边界 |
| --- | --- |
| 集合网格按 kind 混合四种导航、查询、菜单 | CollectionGrid 仅管理布局／搜索／空态；Artist／Album／Genre／PlaylistCollectionView 与同名 ViewModel 分别维护分类行为 |
| Home 大型 section switch 同时构建各类内容、执行排序 | 五个 Home section 组件；HomeView 仅分派已配置的分区，排序队列和统计由 HomeViewModel 提供 |
| Settings 直接批量改记录、创建云任务及处理联网许可 | 独立设置分区；CloudSettingsViewModel、OnlineMetadataSettingsViewModel 管理操作和许可；修改通过 LibraryCommands |
| 完整播放器集中布局、封面、控制、菜单、详情 | NowPlayingView 只管理呈现；NowPlayingContent、PlayerArtworkView、NowPlayingMetadata、PlayerTransportControls、NowPlayingUtilities、PlaybackOptionsMenu、PlaybackDetailsView 各管一部分 |
| View 内聚合统计、分组重复歌曲、批量修改收藏 | ListeningSummary 纯聚合；DuplicatesViewModel 生成稳定分组；SongActionsViewModel 执行选中歌曲命令 |
| ImportViewModel 同时拥有六类状态和任务 | 仅保留组成、生命周期及文件选择结果分派；ImportPicker／AudioImport／FolderImport／Archive／WiFiTransfer／DiagnosticsViewModel 各自管理状态 |
| LibraryViewModel 同时读库、查集合、写记录及清理文件 | LibrarySnapshotReading／Loader 提供快照；LibraryCatalog 纯查询；LibraryCommands 修改；LibraryDeletionWorkflow 管永久删除；ViewModel 发布快照 |
| 播放协调器同时管音频偏好、统计存库与原文件生命周期 | PlaybackAudioSettings、PlaybackHistoryRecorder、PlaybackSourceController 负责各自状态；PlaybackCoordinator 保留队列、播放意图及 transport 状态机 |
| 导入器同时复制、解码、恢复；原文件与副本重复解析标签 | ManagedFileImporter、CoordinatedFileCopier、ManagedImportRecovery；AudioMetadataReader 共用标签解析；原文件扫描由 OriginalFolderScanner 完成 |
| SQLite 类夹杂版本合并、Schema 和文件删除 | SyncEnvelope 为纯冲突合并值；LibrarySchema 为唯一基线；VersionedRecordRepository 在调用者事务内维护版本与 outbox；ManagedMediaCleanup 只清理托管文件 |
| CloudKit metadata worker 同时传输媒体文件 | CloudSyncWorker 维护账号、metadata 和同步事件；CloudAssetTransfer 只传输验证后的托管音频及封面 |
| Wi-Fi listener 同时做地址枚举、协议校验和写文件 | InterfaceAddressProvider、UploadRequestRouter、UploadSession、StagedUpload；UploadHandler 只适配 NIO 请求生命周期，WiFiUploadServer 管 listener |
| CarPlay 和后台云通知通过全局 AppModel 互相耦合 | CarPlayLibraryProviding 只暴露车辆需要的资料库与播放能力；CloudNotificationHandling／Receiver 单独分派静默通知 |
| 两个编辑器重复封面文件读取与验证、直接构造联网客户端 | ArtworkImporting／ManagedArtworkImporter 统一封面入库；OnlineMetadataProviding 可替换；TagEncodingRepair 为纯预览；编辑器只修改草稿 |
| React 队列 hook 同时管理渲染与执行传输策略 | useUploadQueue 保留 React 状态／取消句柄；runUploadBatch 使用注入的 UploadTransport 执行顺序上传、取消和会话失败策略 |

`LibraryStore` 仍是统一 SQLite 入口，跨记录删除、恢复和同步继续使用同一个 writer 事务；不要
在拆分的协作者里开启嵌套写事务。`VersionedRecordRepository` 接收调用者的 Database，不能
单独提交。永久删除先提交 tombstone，再清理托管副本，外部原文件不进入删除清单。

`PlaybackCoordinator` 仍是唯一播放状态机；各播放器组件共享它，不复制队列或播放时钟。
PlaybackHistoryRecorder 继续使用 GRDB 同一串行 writer 的后台 checkpoint，显式保存与后台
保存顺序不变。PlaybackSourceController 只交付仍有效的准备结果；暂停意图和选中条目仍由
协调器判定，旧文件／下载回调不能启动新播放。

新增功能应优先扩展独立组件或窄协议，不向通用列表／网格增加目标路由分支。异步快照、导入、
云设置、联网标签、封面和传输的替代实现由 FeatureBoundaryTests 与 uploadBatch.test.ts 验证。
`python3 Scripts/check_architecture.py` 在本地和 CI 检查确定的层间依赖规则：View 不直接读写
数据库或导入音频／网络实现，ViewModel 不引入 UI 或 SQL／NIO 框架，通用列表／网格不识别
业务路由。这些检查用于防止已识别问题回流，不等同于对所有 SOLID 属性的自动化证明。

macOS 完整播放器的默认键盘焦点必须由 NowPlayingView 的 sheet／NavigationStack 作用域持有，
通过 FocusState.Binding 显式传递给 NowPlayingContent、NowPlayingControls 和
PlayerTransportControls。不要把 defaultFocus 移到内部 HStack；那会使父层的折叠按钮重新
获得默认焦点，导致空格键关闭播放器。MacPlaybackUITests 的完整播放器空格操作覆盖此边界。
