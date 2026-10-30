# Wi-Fi Upload

独立 React 19 + TypeScript + Vite 工程；运行时由 iMusic 内置 HTTP 服务提供静态资源，不使用 WebView，不依赖 CDN 或 Node 服务。npm 依赖按 `package-lock.json` 锁定。

## 安装与开发

```sh
# 项目根目录；Node.js 22.12+（推荐 Node 22 LTS）
npm ci --prefix Web/WiFiUpload
npm test --prefix Web/WiFiUpload
npm run build --prefix Web/WiFiUpload
```

仅编辑页面时，在 iMusic 打开 Wi-Fi Transfer，然后将该页面显示的地址作为代理目标：

```sh
cd Web/WiFiUpload
IMUSIC_UPLOAD_SERVER=http://127.0.0.1:实际端口 npm run dev
```

打开 Vite 输出的本机地址，使用 App 显示的六位码配对。开发代理仅监听本机，代理目标默认 `http://127.0.0.1:8080`；App 的实际端口随机分配，需按显示的地址设置。生产资源不包含开发代理。

## 与原生构建的关系

`Package.swift` 将 `Plugins/WiFiUploadBuild` 绑定到 `iMusicKit`。Xcode 的所有 App scheme 和 SwiftPM 构建都会调用 `Scripts/build_wifi_upload.sh` → `build.mjs`：

1. 查找 Node（支持 PATH、Homebrew、Volta 和 nvm 安装；非标准安装可在启动构建的环境设置 `NODE_BINARY`）。
2. 检查依赖已安装且与锁文件匹配。依赖缺失会明确失败，提示 `npm ci`；插件不在沙箱中下载 npm 包。
3. 对前端源码、配置、翻译目录、锁文件及 Node 版本计算 SHA-256 指纹。指纹和完整输出均相符时复用，否则先类型检查再运行 Vite 生产构建。
4. 输出 `upload-index.html`、带内容哈希的 `upload-*.js/css` 和 `upload-assets.json` 到 SwiftPM 插件工作目录。SwiftPM 将这些资源自动复制到 `iMusicKit` 的资源包，App 签名／Archive 自然包含它们。

没有提交或手动复制的 `dist`，没有 Swift HTML 模板。`npm run build` 产生的本地 `dist` 仅供前端开发检查；App 始终使用插件构建的资源。不要在 Xcode 再加一份 Copy Resources 或 Run Script，避免重复／时序冲突。首次使用 Xcode 可能需要确认信任本地构建插件。

## 服务协议

| 请求 | 行为 |
| --- | --- |
| `GET /`、`GET /index.html` | React 页面 |
| `GET /upload-*.js/css` | 仅允许资源清单中的文件；正确 MIME，`nosniff` |
| `GET /api/config` | 应用语言、支持扩展名、单文件最大字节数；不含配对码或令牌 |
| `POST /pair` | 请求体为六位码；200 返回仅存网页内存的会话令牌；错误次数受限 |
| `POST /upload?name=…` | Bearer 令牌、原始文件体；服务端流式写盘；202 表示文件已接收并提交导入 |

XHR 的发送进度最多显示 99%，服务端返回 202 后才标记已接收。接收成功与导入成功分开表达；最终结果在 iMusic 查看。请求取消时终止 XHR，服务器清理不完整上传；已接收的文件不会因网页取消而撤回。网络错误停止本批次，保留其余待上传文件；鉴权失效要求重新配对。

文本仅引用 `src/messages.json` → 根目录 `Localization/Strings.json`，支持英文、简中和繁中。主题跟随系统，窄屏自动调整布局；无统计或外部资源请求。

## 验证

- Vitest／Testing Library：多语言、配对前门禁、错误码、格式与大小校验、Unicode 文件名、真实进度事件、取消与重试、会话失效。
- `swift test`：构建资源入包、HTTP MIME／CSP、路径拒绝、配置接口、配对与流式字节一致性。
- CI 在原生构建前运行 `npm ci` 和前端测试。
