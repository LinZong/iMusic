# Swift 代码风格

项目使用 Swift 官方维护的 [swift-format](https://github.com/swiftlang/swift-format) 同时执行格式化和风格检查。工具随 Swift 6／Xcode 提供，脚本通过 `xcrun` 使用当前选择的 Xcode 工具链；本次统一使用 Xcode 26.3 自带的 swift-format 6.2.3，不增加 App 的 SPM 或 CocoaPods 依赖。

API 命名和文档遵循 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) 的清晰、一致、易于使用原则。缩进和行宽是本项目统一采用的排版约定；Swift 官方并未规定唯一的代码排版风格。

## 统一规则

- 使用 4 个空格缩进，不使用 Tab；条件编译指令不额外增加缩进。
- 所有 Swift 源码、注释和字符串所在物理行最多 100 字符，不设置超长行豁免。
- 不使用分号在同一行拼接多条语句；枚举 case 和成员字段分别声明。
- 长函数签名、参数列表、集合及 SwiftUI 表达式由 formatter 按语法断行；多行参数逐项排列。
- 需要断行的链式调用在组件边界换行，保留原生 SwiftUI 的声明式结构。
- 类型使用 UpperCamelCase，方法及变量使用 lowerCamelCase；import 有序，空行、括号、空格和集合尾逗号保持一致。
- 所有成员字段、public 方法／初始化方法和协议 API 保留英文 `///` 文档注释。
- 保留显式初始化方法，不启用 `UseSynthesizedInitializer` 自动移除构造函数。

根目录 `.swift-format` 保存全部规则，避免本地依赖工具默认值。官方规则和配置语义见 [Configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md)。

## 执行

```sh
# 格式化全仓自有 Swift 源码，随后执行严格检查。
python3 Scripts/swift_style.py format

# 只检查，不修改文件；任一告警或超长行都会失败。
python3 Scripts/swift_style.py check
```

脚本包含 Git 已跟踪以及尚未忽略的新 Swift 文件，覆盖 `Package.swift`、`Sources`、`Apps`、`Tests`、`Plugins` 和 Swift 脚本。通过 Git 文件清单避免遍历被忽略的第三方依赖、`node_modules`、SwiftPM 和 Xcode 构建缓存。删除的文件不参与检查。

`format` 先执行 `swift-format format`，再执行 `swift-format lint --strict` 和物理行宽检查。原生 formatter 无法自动拆开的长注释、普通单行字符串同样会被行宽检查拒绝，需要先手动换行，再重新运行。`check` 全程只读，适合提交前和 CI 使用。

## 长字符串与注释

长字符串使用 Swift 多行字面量，并通过行末 `\` 连接，保持原字符串值、空格及本地化 key 不变：

```swift
let detail = """
    This text continues \
    without inserting a newline into the value.
    """
```

SQL、HTTP 头以及长本地化 key 同样遵循这一约定。formatter 的 `reflowMultilineStringLiterals` 使用 `onlyLinesOverLength`，只重排超长内容，不随意改动已有的换行语义。`Scripts/check_localizations.py` 同时检查单行、跨行参数和上述多行 key，避免格式化后漏查翻译。

英文 `///` 注释应按句意换行，每行不超过 100 字符；不要删除原有功能说明来缩短代码。

## 编辑器与 CI

VS Code 使用项目推荐的官方 Swift 扩展。仓库 `.vscode/settings.json` 已配置 Swift 保存时格式化、4 空格缩进和 100 字符参考线；Tasks 中提供 `Swift: Format repository` 和 `Swift: Check repository style`。

Xcode 用户可以直接在项目根目录执行上述命令，无需安装额外扩展。团队应使用相同的 Xcode 工具链，避免不同版本 formatter 产生排版差异。

GitHub Actions 在选择 Xcode 后、构建测试前运行全仓严格检查。新增 Swift 文件会自动进入检查范围。
