# 签名、CloudKit 与 CarPlay

## 本地开发

打开工程选择 iMusicMac 或 iMusic。Mac 可使用本地 ad-hoc 签名；iOS 真机需要自己的开发团队。工程不会内置作者证书、共享 CloudKit 账号或要求把密钥提交到源码。

复制 `Config/Signing.example.xcconfig` 到 `Config/Signing.local.xcconfig`，设置 DEVELOPMENT_TEAM 和独立 bundle 前缀。该文件被 Git 忽略。本地 Debug/Release 在 target 层清空云容器标识，避免误请求未授权能力。

请在本地 xcconfig 中维护团队信息，不要将自己的 DEVELOPMENT_TEAM 写入并提交到共享工程。
工程生成脚本也会排除所有 `.local.xcconfig` 文件引用。

## 真机 Release 运行

1. 连接并解锁 iPhone／iPad，在 Xcode 顶部选择真实设备。
2. 选择共享 **iMusic Playback** scheme；它的 Run 已设为 Release，且不附加 LLDB。
3. 在 `Config/Signing.local.xcconfig` 设置有效的开发团队与独立 bundle 前缀，确认自动签名可用。
4. 使用 Product → Run（⌘R）构建、安装并启动。手机需信任开发者，并在系统要求时启用开发者模式。

也可复制普通 **iMusic** scheme，在 Product → Scheme → Edit Scheme → Run → Info 中
将 Build Configuration 设为 Release，并取消 Debug executable。普通共享 scheme 保留 Debug 配置供断点调试。
Release 编译配置与分发签名是两件事：以上方式安装的是开发签名应用，不会上传 App Store 或 TestFlight。

### 命令行构建和安装

完成签名配置后，执行 `./Scripts/install_ios_release.py` 即可不打开 Xcode，构建并安装 Release。
脚本会自动选择唯一连接的 iOS 真机；多个设备时使用 `--device` 指定名称或 UDID。
通过 `--skip-build` 复用已有签名产物，缺少新机型支持镜像时可使用 `ideviceinstaller` 备用安装通道。
前置条件、参数与错误排查见 [命令行安装指南](InstallRelease.md)。

### SideStore unsigned IPA

执行 `./Scripts/build_sidestore_ipa.py` 可使用普通 iMusic scheme 编译真机 Release，
但在本次构建中关闭代码签名与描述文件，并输出
`build/SideStore/iMusic-unsigned.ipa`。此流程不需要开发团队或连接真机，也不会修改本地
签名配置；产物不能直接安装，必须交给 SideStore 重签。参数、校验与日志位置见
[SideStore IPA 编译指南](BuildSideStoreIPA.md)。

### macOS Release 构建

执行 `./Scripts/build_macos_release.py` 可不打开 Xcode，编译并导出 macOS Release。
默认使用 ad-hoc 临时签名，产物供本机使用，无需配置开发团队；本机签名配置文件不会被修改。
脚本默认生成 Apple Silicon／Intel 通用应用，公开分发所需的 Developer ID 签名与公证另行处理。
参数与输出路径见 [macOS Release 构建指南](BuildMacRelease.md)。

## Cloud

1. 具备可使用 CloudKit 的开发者团队，注册 iOS 和 macOS App ID。
2. 创建一个 CloudKit 容器，将两个 App ID 关联到同一容器。
3. 配置 `IMUSIC_CLOUD_CONTAINER`，在相应 App ID／描述文件启用 CloudKit 与后台数据推送。
4. 选择 Cloud scheme 进行开发；Full scheme 同时启用 iOS CarPlay。
5. 在开发环境生成并验证 schema，再在 CloudKit Console 部署到生产环境。不要将开发与生产资料库当成同一个数据集。

私有数据库使用两个 zone：

- `iMusicMetadataV2`：`LibraryRecord`，字段 `envelope` 为压缩 Data，`encoding` 为 String。
- `iMusicAssets`：`AudioAsset`（`audio`: Asset、`extension`: String），`ArtworkAsset`（`artwork`: Asset）。

无需公开数据库或服务端账号。CKSyncEngine 使用后台数据通知，不请求 alert/badge/sound 授权。用户需在设置中主动启用资料库同步；音乐上传是单独开关。本地导入始终独立可用。

## CarPlay

CarPlay 音频需要 Apple 审批 `com.apple.developer.carplay-audio`，并签署其对应附加条款。这些由账号持有人在开发者网站处理，项目不会自动申请或接受协议。

- `iMusic CarPlay`：本地资料库加车载界面。
- `iMusic Full`：CloudKit 加 CarPlay；Archive 使用 FullRelease。
- FullRelease 使用 Production CloudKit 环境及 production APS 环境；开发构建使用 Development。

CarPlay scene 在专用 Info.plist 中声明，手机和平板的场景交给 SwiftUI 管理，避免重复代理。此方式遵循 [Apple 场景配置文档](https://developer.apple.com/documentation/carplay/displaying-content-in-carplay)。模拟器可用于验证列表、歌单和 Now Playing；真实车载支持必须使用获授权描述文件，并完成真机连接与系统控制验证。仅给本地构建强行添加 entitlement 不能获得能力。

## 公开分发

源码可以公开；签名产物、上架、TestFlight、Developer ID 公证属于后续发布操作。工程提供配置，未自动上传或发布。每位自行构建的开发者使用自己的 bundle ID、团队和容器。

参考：[Apple CarPlay 权限](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)、[CloudKit](https://developer.apple.com/documentation/cloudkit)。

升级版从旧 `iMusicMetadata` 区域一次性读取历史记录，随后只向 `iMusicMetadataV2` 写入元数据；原 `iMusicAssets` 继续复用。关联歌曲的原音频、书签和本机路径不会上传到这些区域。
