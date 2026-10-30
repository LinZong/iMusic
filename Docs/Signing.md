# 签名、CloudKit 与 CarPlay

## 本地开发

打开工程选择 iMusicMac 或 iMusic。Mac 可使用本地 ad-hoc 签名；iOS 真机需要自己的开发团队。工程不会内置作者证书、共享 CloudKit 账号或要求把密钥提交到源码。

复制 `Config/Signing.example.xcconfig` 到 `Config/Signing.local.xcconfig`，设置 DEVELOPMENT_TEAM 和独立 bundle 前缀。该文件被 Git 忽略。本地 Debug/Release 在 target 层清空云容器标识，避免误请求未授权能力。

## Cloud

1. 具备可使用 CloudKit 的开发者团队，注册 iOS 和 macOS App ID。
2. 创建一个 CloudKit 容器，将两个 App ID 关联到同一容器。
3. 配置 `IMUSIC_CLOUD_CONTAINER`，在相应 App ID／描述文件启用 CloudKit 与后台数据推送。
4. 选择 Cloud scheme 进行开发；Full scheme 同时启用 iOS CarPlay。
5. 在开发环境生成并验证 schema，再在 CloudKit Console 部署到生产环境。不要将开发与生产资料库当成同一个数据集。

私有数据库使用两个 zone：

- `iMusicMetadata`：`LibraryRecord`，字段 `envelope` 为压缩 Data，`encoding` 为 String。
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
