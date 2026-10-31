# 备份格式 v2（兼容读取 v1）

ZIP 根目录包含 `manifest.json`，完整备份另外包含 `Media/<SHA-256>.<extension>`；图片位于 `Artwork/<opaque-name>`。ZIP 不保留父目录。音频不转码，按原始字节校验。

Manifest 字段：

- `formatVersion`: 整数，当前为 2；恢复支持 1 和 2。
- `createdAt`: Foundation Date 默认 Codable 数值，基准为 2001-01-01 UTC。
- `includesAudio`: 是否要求并包含全部未永久删除的托管音频；不包含关联音频。
- `records`: SyncEnvelope 数组，包含歌曲、歌单、收藏、原始／覆盖标签和收听记录。
- `files`: 相对路径、SHA-256 和字节大小。
- `managedSongCount` / `linkedReferenceCount`: 托管歌曲数与仅含引用的关联歌曲数，v1 中可缺省。
- `settings`: 可移植设置名到 JSON Data 的映射，可选；JSON 中的 Data 编码为 Base64。

SyncEnvelope 包含 `id`、`kind`、Base64 JSON `payload` 和每字段版本 `versions`。歌单条目版本键为 `entry:<UUID>`；条目从 payload 消失但版本保留表示删除。版本是逻辑 clock 与 device 标识；按 clock 再按 device 比较。

备份不携带证书、iCloud 同步状态、账号关联、文件夹书签、本机路径、配对码或主动联网授权。外观、音效、首页编排和歌手拆分设置可以随备份迁移。强调色跟随系统，不存储或导出应用内配色设置。

恢复先检查 ZIP 条目路径，拒绝绝对路径、父目录穿越和符号链接；限制展开大小。解压在暂存区域完成，逐文件验证清单、大小和哈希，并验证逻辑记录。完整备份要求每首 Managed 歌曲都有对应音频；Linked 只备份记录与封面，不要求源音频已经下载。轻量备份按内容哈希关联已有托管文件；关联歌曲则保留 folderID、相对定位提示，等待本机重新授权，不能从 CloudKit 托管资产补齐。

提交前保存 `BeforeRestore.json` 逻辑快照；原有音频不被覆盖。通过事务合并逻辑记录，保留较新字段和删除标记，不用旧备份静默覆盖后续修改。文件复制成功而 SQL 失败时可能保留未引用的音频；这些文件不会被自动清除。

完整备份前必须下载全部可恢复的托管音乐，包含回收站中的托管记录；缺失音频会使完整备份明确失败。永久删除记录保留 `permanentlyDeletedAt` 标记，但不要求或导出其已清理的音频。恢复到仍保有此标记的资料库时，旧备份不会重新激活该歌曲；额外复制的无引用副本会被清理。应用外的旧备份内容本身不会被改写，恢复到没有删除标记的全新资料库仍可重建其中的音乐。请把导出文件保存到应用之外，避免卸载或磁盘故障同时影响资料库与备份。

Linked 记录的 assetHash 缺省，linkedSource 明确携带可移植描述；没有 linkedSource 的旧 v1 歌曲继续视为 Managed，并验证其哈希。folders 与 linked.item.* 本机设置不进入清单。导出界面显示两类歌曲数量，提醒关联音频和目录授权不包含在档案中。
