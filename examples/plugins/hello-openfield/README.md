# hello-openfield — 示例插件

最小可用的 OpenField 插件：统计启动次数并用 toast 问候。

## 打包

把本目录内容打成 zip（`manifest.json` 必须位于压缩包根目录）：

```powershell
Compress-Archive -Path manifest.json, main.js -DestinationPath hello-openfield.zip
```

## 安装方式

1. **插件商店**（推荐）：管理员在后台「插件商店」上传该 zip 并发布，
   客户端在 我的 → 插件 → 插件商店 中安装。
2. **本地导入**：客户端 我的 → 插件 → 导入 选择该 zip
   （导入的插件会带“未经审核”标记）。

## 权限说明

| 权限 | 级别 | 用途 |
|------|------|------|
| `storage` | L0 安全 | 按插件隔离的键值存储 |
| `log` | L0 安全 | 写入调试日志 |
| `ui.toast` | L0 安全 | 应用内提示条 |

## 运行时 API 一览

```js
of.log(msg)                          // 调试日志
await of.storage.get(key)            // -> {value}
await of.storage.set(key, value)
await of.storage.remove(key)
await of.http.fetch(url, options)    // 仅允许 manifest.allowed_hosts 中的主机
await of.posts.list(page)            // 需 posts.read
await of.chat.conversations()        // 需 chat.read（危险级）
await of.chat.send(conversationId, text) // 需 chat.send（危险级）
await of.account.me()                // 需 account.profile（敏感）
await of.ui.toast(text)
```

安全启动：断网或无法验证服务器连接时，所有插件运行时会被立即销毁；
恢复在线后已启用的插件自动重新加载。
