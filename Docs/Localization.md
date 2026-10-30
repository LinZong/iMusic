# 本地化

iMusic 当前提供英文（`en`）、简体中文（`zh-Hans`）和繁体中文（`zh-Hant`）。跟随系统或系统提供的应用语言偏好，未支持的语言回退英文。iPhone、iPad 和 Mac 共用同一份文案资源。无需联网选择语言。

## 文案入口

编辑 `Localization/Strings.json`，然后运行：

```sh
python3 Scripts/generate_localizations.py
python3 Scripts/check_localizations.py
swift test --filter LocalizationTests
```

权威翻译表包含 337 个键，输出为标准 `Localizable.strings`／`Localizable.stringsdict`；生成文件随项目分发，无需用户安装 Python 才能构建应用。新增语言时需要补齐翻译、`L10n.supportedLanguages`、生成脚本的语言列表和应用 `CFBundleLocalizations`／工程地区列表。重新生成 Xcode 工程后执行检查。

业务代码使用 `L10n.text(key, arguments...)`，从 **SPM 的 Bundle.module** 读取资源，不依赖调用者的主 bundle。格式参数采用有位置编号的 `%1$ld`／`%1$@`，允许译者调整顺序。英文数量通过 stringsdict 区分单复数；不得通过拼接数量和已翻译名词构造句子。

SwiftUI 文案、菜单、无障碍标签、导入／备份／播放／同步错误、CarPlay 列表和 Wi-Fi 上传网页均调用此入口。品牌、编码名称、音频格式及用户音乐／歌单名称不作翻译。系统和第三方框架提供的底层错误详情由对应框架产生。

## 非原生界面与系统说明

- Wi-Fi 上传网页使用独立 React 工程，构建时从同一翻译目录提取文案，运行时通过配置接口跟随应用语言。
- `Apps/Resources/*.lproj/InfoPlist.strings` 本地化局域网权限说明和音频文件类型名称。
- 应用 Info.plist 使用英文开发语言并声明全部支持语言。默认本地构建不请求可见通知权限。

## 偏好兼容

显示模式和首页布局使用 `system`、`continue` 等稳定标识，与语言无关。早期开发构建保存的中文标识通过 `LegacyPreferences.json` 映射；该文件是兼容数据，不是 UI 文案。切换语言不重命名用户内容，也不改变播放队列。

## 已验证

- 语言匹配：英文、简体、繁体、台湾／中国地区标识、法语回退英文。
- 数量：0、1、2 首歌曲；同时带数量与时长的格式化。
- 参数：保留 Unicode 文件名和错误原因。
- Wi-Fi 网页：浏览器语言回退、跟随 App 语言、三语文案完整性及配置接口检查。
- 偏好：旧标识迁移和默认标识跨语言稳定。
- 界面：Mac 英文、iPhone 简体、iPad 繁体已实际打开检查，用户创建的中文歌单名保持原文。

CI 运行 `check_localizations.py` 校验翻译齐全、参数一致、生成资源同步，以及 Swift 源码中没有直接写入中文文案。
## Wi-Fi 上传网页

React 页面通过 `Web/WiFiUpload/src/messages.json` 引用本目录 `Strings.json` 中的文案键。Vite 构建时仅提取所需的三种语言，不另维护一份网页翻译。初始状态按浏览器语言选择，获取 `/api/config` 后跟随 iMusic 应用语言。新增提示需补齐翻译目录中的三种语言，并运行生成和覆盖检查脚本。

