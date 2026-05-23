# cc-switch · macOS 应用开发参考

> 给「想做一个 Mac 桌面小工具」的人当索引：哪些主题需要了解、cc-switch 里是怎么落地的、关键代码在哪、有哪些常见坑。
>
> cc-switch 用的技术栈：**Tauri 2.x（Rust 后端 + React/TS 前端）**。如果你打算用 Electron 也能参考思路，原理是一样的。

---

## 0. 选什么技术栈

| 方案 | 体积 | 性能 | 学习曲线 | 备注 |
|---|---|---|---|---|
| **Tauri 2**（cc-switch 选的） | 安装包 5–20 MB | 原生 WebView（macOS 用 WKWebView） | 要会 Rust 但也能纯 JS | 系统级 API 全都有；跨平台 |
| Electron | 80+ MB | 自带 Chromium | 纯 JS | 生态最大，资源占用最大 |
| SwiftUI | 最小 | 原生 | 只能 mac/iOS | 想做"非常 Mac 风格"就选它 |
| Wails (Go) | 类 Tauri | 原生 WebView | Go | 跟 Tauri 思路一样 |

cc-switch 选 Tauri 的原因：CLI 配置工具，要跨 mac/win/linux、要快、要小，**Rust 调 macOS Keychain / 文件系统比写 Node 原生模块省心**。

---

## 1. 应用骨架

```
项目根/
├── src/                    # 前端（React/TS）
├── src-tauri/              # 后端（Rust）
│   ├── src/
│   │   ├── main.rs         # 入口 main()
│   │   ├── lib.rs          # tauri::Builder 装配
│   │   ├── commands/       # #[tauri::command] 暴露给前端的函数
│   │   ├── services/       # 业务逻辑
│   │   ├── tray.rs         # 系统托盘
│   │   ├── auto_launch.rs  # 开机自启
│   │   └── ...
│   ├── icons/              # .icns / .png（必须）
│   ├── tauri.conf.json     # 应用配置（标识符、窗口、bundle）
│   └── Cargo.toml
└── package.json
```

**核心心智模型**：前端通过 `invoke("命令名", { 参数 })` 调后端；后端 Rust 用 `#[tauri::command]` 标注函数；编译时自动生成 IPC bridge。

---

## 2. 文件系统：读写用户目录

macOS 应用最常做的事就是读写 `~/Library/...` 或 `~/.something/`。

### 2.1 取家目录、应用支持目录

```rust
// 跨平台
let home = dirs::home_dir();                      // ~/
let config = dirs::config_dir();                  // ~/Library/Application Support
let cache = dirs::cache_dir();                    // ~/Library/Caches
```

或用 Tauri 内置 path API（前端也能用）：

```rust
use tauri::Manager;
let app_data = app.path().app_data_dir()?;        // ~/Library/Application Support/<bundle id>
let app_log = app.path().app_log_dir()?;          // ~/Library/Logs/<bundle id>
```

cc-switch 里：[`src-tauri/src/config.rs:37`](src-tauri/src/config.rs:37) 的 `get_claude_config_dir()` 就是 `dirs::home_dir().join(".claude")`。

### 2.2 sandbox 还是非 sandbox？

- **从 Tauri/Electron 默认构建的 .app 是非 sandbox 的**，你可以随意访问用户家目录里任意文件。这也是 cc-switch 能直接读 `~/.claude/projects/*.jsonl` 的前提。
- 想上 **Mac App Store** 必须开 sandbox，那时候你只能访问应用容器目录（`~/Library/Containers/<bundle id>/`）。
- 非 sandbox 应用直接分发就行（dmg、Homebrew cask 都可以），不用走 App Store。

### 2.3 用户首次访问 `~/Downloads` / `~/Desktop` / `~/Documents` 会弹权限框

这是 macOS 10.15+ 的 **TCC（Transparency, Consent, Control）**。你的应用只要试图读这些目录，系统会自动弹 "xxx 想要访问下载文件夹"。

- **你不需要写代码请求**，系统会自动处理。
- 用户点拒绝后，你的 `read_dir()` 会返回 `EACCES`。要捕获错误并提示用户去 **系统设置 → 隐私与安全性 → 文件与文件夹** 给权限。
- 想避免弹窗：让用户主动通过文件选择器选目录（系统认为这是用户授权，不弹窗）。

### 2.4 增量读 / 流式读大文件

cc-switch 在 [`session_usage.rs:175`](src-tauri/src/services/session_usage.rs) 用了一个典型套路：

```rust
let file = fs::File::open(path)?;
let reader = BufReader::new(file);
for line in reader.lines() { ... }                // 逐行流式
```

并维护一张表记 `(file_path, last_mtime, last_line_offset)`，下次只从断点开始读。Mac 上 `fs::metadata().modified()` 返回 mtime，纳秒精度。

---

## 3. 凭据 / 密钥：macOS Keychain

**不要把 token 明文写在 `~/.config/xxx.json` 里**，Mac 用户会期望关键信息进 Keychain。

### 3.1 读 Keychain（cc-switch 方式：调 `security` 命令）

```rust
// services/subscription.rs:125
let output = std::process::Command::new("security")
    .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    .output()?;
let token = String::from_utf8(output.stdout)?;
```

参数：
- `-s <service>`：服务名（钥匙串里的"种类"）
- `-a <account>`：账户名（可选）
- `-w`：只输出密码字段
- `add-generic-password -s X -a Y -w "secret" -U`：写入（`-U` 覆盖）

### 3.2 用 Rust crate（更好）

```toml
[dependencies]
keyring = "3"
```

```rust
let entry = keyring::Entry::new("my-app", "default")?;
entry.set_password("secret")?;
let token = entry.get_password()?;
```

底层在 Mac 上也是走 Keychain Services。**比起 `security` 命令的好处**：不依赖 PATH、错误更清晰、不会被 shell 转义坑。

### 3.3 用户首次访问会弹密码框

第一次读取你"以前没写过"的 Keychain 条目，或者别的 App 写的条目，Mac 会弹"xxx 想要访问 钥匙串中的 yyy"。这是预期行为。**点"始终允许"后下次就不弹了**。

cc-switch 就是利用这点直接读 Claude/Codex CLI 写好的条目（用户首次会被弹一下询问，同意后免再次确认）。

---

## 4. 网络：HTTPS / 代理

Rust 这边用 `reqwest`，没什么特别 mac 的事，但有几点：

1. **TLS 后端**：Tauri 项目通常用 `rustls`（不依赖 OpenSSL，编译省事）。需要 `rustls::crypto::ring::default_provider().install_default()` 初始化（见 [`lib.rs:285`](src-tauri/src/lib.rs:285)）。
2. **系统代理**：Mac 用户经常开代理。`reqwest::Client::builder().no_proxy()` 默认会读 `HTTP_PROXY` 环境变量；想完全跟随系统代理可以用 `system-proxy` crate 或自己读 `scutil --proxy`。
3. **网络权限**：非 sandbox 应用不需要任何 entitlement。sandbox 才需要 `com.apple.security.network.client`。

---

## 5. 窗口、托盘、菜单栏

### 5.1 窗口

`tauri.conf.json`：

```jsonc
"windows": [{
  "label": "main",
  "title": "",
  "titleBarStyle": "Overlay",     // 隐藏标题栏，前端自绘
  "width": 1000, "height": 650,
  "visible": false,                // 启动不可见，setup 里再 show
  "center": true
}]
```

`titleBarStyle` 在 Mac 上的可选值：`Visible` / `Transparent` / `Overlay`。Overlay 会让红绿灯还在，但内容延伸到顶部 —— 现代 Mac 应用标配。

### 5.2 系统托盘（菜单栏图标）

cc-switch 在 [`src-tauri/src/tray.rs`](src-tauri/src/tray.rs) 完整实现。要点：

```rust
TrayIconBuilder::new()
    .icon(macos_tray_icon())     // PNG，命名带 "Template" 的会自动跟随暗黑模式
    .menu(menu)
    .on_tray_icon_event(handler)
    .build(app)?;
```

**macOS 特定**：
- 文件名以 `Template` 结尾的 PNG（或代码里 `Image::new_template`）会被系统当**模板图标**，自动反色适配深色菜单栏。cc-switch 用的 `statusbar_template_3x.png`。
- `@2x`、`@3x` Retina 资源要同时准备。

### 5.3 Activation Policy：让 Dock 图标消失

「最小化到托盘后不在 Dock 里显示」—— 这是 Mac 特色，叫 Accessory App：

```rust
// tray.rs:659
use tauri::ActivationPolicy;
app.set_activation_policy(if dock_visible {
    ActivationPolicy::Regular     // 正常出现在 Dock
} else {
    ActivationPolicy::Accessory   // 只在菜单栏，不占 Dock
});
```

cc-switch 在窗口关闭时切到 Accessory，再次打开窗口时切回 Regular（[`lib.rs:264`](src-tauri/src/lib.rs:264)）。

### 5.4 应用菜单（顶部菜单栏）

Tauri 2 默认会给一个最小化菜单。要完全自定义就用 `MenuBuilder`。**Mac 上的菜单是顶部全局菜单栏**（不是窗口内的），跟 Windows 完全不同。

---

## 6. 开机自启

cc-switch 用 [`auto-launch`](https://crates.io/crates/auto-launch) crate（[`auto_launch.rs:35`](src-tauri/src/auto_launch.rs)）。

**macOS 关键坑**：必须传 `.app bundle 路径`（`/Applications/CC Switch.app`），**不是** 内部的可执行文件路径（`.../Contents/MacOS/CC Switch`）。否则 AppleScript 的 login item 会打开终端窗口。

```rust
// 把 /xxx/CC Switch.app/Contents/MacOS/CC Switch 截到 /xxx/CC Switch.app
if let Some(pos) = path_str.find(".app/Contents/MacOS/") {
    Some(PathBuf::from(&path_str[..pos + 4]))
}
```

实现原理：底层走 AppleScript 注册 login item（类似 `tell application "System Events" to make login item...`）。新版可以用 ServiceManagement framework（`SMAppService`），更现代但要更高的最低 macOS 版本。

---

## 7. Deep Link（自定义 URL Scheme）

让 `ccswitch://import?...` 在浏览器点击后直接打开你的应用。

### 7.1 注册

`tauri.conf.json`：
```jsonc
"plugins": {
  "deep-link": {
    "desktop": { "schemes": ["ccswitch"] }
  }
}
```

构建时 Tauri 会往 `Info.plist` 写 `CFBundleURLTypes`。Mac 的 LaunchServices 收到 URL 时通过 **AppleEvent** 唤醒你的进程。

### 7.2 处理

```rust
.plugin(tauri_plugin_deep_link::init())
.setup(|app| {
    app.deep_link().on_open_url(|event| {
        for url in event.urls() {
            handle_deeplink_url(&app, url.as_str(), true, "open_url");
        }
    });
    Ok(())
})
```

**Mac 特别注意**：URL 通过 AppleEvent 而不是 `argv` 进来。所以**不要**只在 `main` 函数读命令行参数 —— Windows/Linux 会进 argv，Mac 不会。Tauri deep-link 插件已经把这个差异屏蔽了。

### 7.3 单实例

`tauri-plugin-single-instance`：用户已经打开应用时再点击 deep link，OS 会启动第二个进程，插件会把参数转发给已经在跑的实例并退出新进程。否则会启动多份。

---

## 8. 通知

```rust
use tauri_plugin_notification::NotificationExt;
app.notification().builder()
    .title("xxx").body("yyy").show()?;
```

macOS 首次会弹「允许通知」系统弹窗。用户也可在 系统设置 → 通知 里关掉。

---

## 9. 进程间通信（前端 ↔ 后端）

```rust
#[tauri::command]
fn get_summary(state: State<AppState>, start: i64) -> Result<UsageSummary, AppError> {
    state.db.get_usage_summary(Some(start), None, None)
}
```

前端：
```ts
import { invoke } from "@tauri-apps/api/core";
const summary = await invoke<UsageSummary>("get_summary", { start: 0 });
```

约定：Rust 用 `snake_case`，前端用 `camelCase` 参数；Tauri 自动转换。返回结构体加 `#[serde(rename_all = "camelCase")]`。

**事件**（后端推给前端）：
```rust
app.emit("usage-cache-updated", &payload)?;
```
```ts
listen("usage-cache-updated", (e) => { ... });
```

---

## 10. 数据存储

cc-switch 用 SQLite（[`rusqlite`](https://crates.io/crates/rusqlite)），DB 文件存在 `app.path().app_data_dir()` 下。

可选项：
- **SQLite**：用 `rusqlite` 或 `sqlx`，最通用。
- **`tauri-plugin-store`**：键值 JSON，前端也能直接读写。简单设置/偏好用这个。
- **直接 JSON 文件**：最简单但要注意并发写。

`app_data_dir` 在 Mac 上是 `~/Library/Application Support/<identifier>/`，identifier 在 `tauri.conf.json` 里写：

```jsonc
"identifier": "com.ccswitch.desktop"
```

---

## 11. 打包、签名、公证

这一步是 macOS 上最坑的，专门拆开说。

### 11.1 普通构建

```bash
pnpm tauri build
```

产出：
- `src-tauri/target/release/bundle/dmg/*.dmg` —— 用户拖到 Applications
- `.../macos/*.app` —— 应用 bundle 本体

### 11.2 不签名 → 用户打开会被 Gatekeeper 拦

没签名的 .app，用户首次打开会弹「无法打开，因为无法验证开发者」。绕过办法：右键 → 打开（用户自己点确认）。**但很多人不知道这个动作，建议至少做 Ad-hoc 签名或申请开发者证书**。

### 11.3 开发者证书 + 签名

需要：
- Apple Developer Program 会员（99 USD/年）
- 创建 **Developer ID Application** 证书（在 developer.apple.com）

`tauri.conf.json`：
```jsonc
"bundle": {
  "macOS": {
    "minimumSystemVersion": "12.0",
    "signingIdentity": "Developer ID Application: Your Name (TEAMID)"
  }
}
```

或环境变量 `APPLE_SIGNING_IDENTITY=...`。

### 11.4 公证（Notarization）

签名只让 Gatekeeper 知道是谁，**还要把 .app 发给 Apple 服务器扫一遍**才能让用户「双击直接打开」。

```bash
APPLE_ID=xxx@xxx.com \
APPLE_PASSWORD=app-specific-password \
APPLE_TEAM_ID=XXXXXXXXXX \
pnpm tauri build
```

`APPLE_PASSWORD` 不是你的 Apple ID 密码，是在 [appleid.apple.com](https://appleid.apple.com) 生成的**应用专用密码**（App-Specific Password）。

Tauri 会自动调 `xcrun notarytool submit`，等几分钟拿到结果，然后 staple（把公证票据装订到 .app）。

### 11.5 通用二进制（Apple Silicon + Intel）

```bash
pnpm tauri build --target universal-apple-darwin
```

体积大约翻倍。如果只发 ARM 用户用 `aarch64-apple-darwin`，Intel 用 `x86_64-apple-darwin`，可以发两个 dmg。

### 11.6 分发渠道

- **DMG 直接放官网下载** —— cc-switch 在用，最常见。
- **Homebrew Cask**：写一个 ruby 脚本提交到 [homebrew-cask](https://github.com/Homebrew/homebrew-cask)，`brew install --cask 你的应用`。cc-switch 推荐用户走这个（见项目 README）。
- **Mac App Store**：要求 sandbox，限制多，独立开发者很少走。
- **GitHub Releases + 自动更新器**：见下条。

---

## 12. 自动更新

cc-switch 用 `tauri-plugin-updater`：

```jsonc
"plugins": {
  "updater": {
    "pubkey": "minisign 公钥（base64）",
    "endpoints": ["https://github.com/.../releases/latest/download/latest.json"]
  }
}
```

工作流程：
1. `cargo install tauri-cli` 然后 `tauri signer generate` 生成 minisign 密钥对。
2. 公钥写进 `tauri.conf.json`。
3. 每次构建会输出 `.app.tar.gz` 和 `.app.tar.gz.sig`。
4. 你写一个 `latest.json` 指向最新 release 的 url 和 sig。
5. 应用启动时检查更新、下载、验签、应用。

**Mac 关键**：自动更新要求**应用本身经过签名**，否则下载下来的新版替换旧版后 Gatekeeper 会拒。

---

## 13. 日志、崩溃

cc-switch 在 [`panic_hook.rs`](src-tauri/src/panic_hook.rs) 装了 panic hook，把崩溃写到 `~/.cc-switch/crash.log`。

Tauri 提供 `tauri-plugin-log`，直接落到 `~/Library/Logs/<bundle id>/`，也能写控制台。

**查看 Mac 上别人的 App 日志的标准位置**：`Console.app` → 左侧选机器 → 搜应用名。系统级 crash 报告在 `~/Library/Logs/DiagnosticReports/`。

---

## 14. 平台条件编译

Rust 这边写跨平台代码靠 cfg 属性，cc-switch 里到处都是：

```rust
#[cfg(target_os = "macos")]
fn keychain_read() { ... }

#[cfg(not(target_os = "macos"))]
fn keychain_read() { /* fallback */ }
```

前端 TS 这边判平台：
```ts
import { platform } from "@tauri-apps/plugin-os";
if (platform() === "macos") { ... }
```

---

## 15. 常用 macOS API & 工具命令速查

| 你想做 | 命令 / API |
|---|---|
| 读 Keychain | `security find-generic-password -s X -w` / `keyring` crate |
| 写 Keychain | `security add-generic-password -s X -a Y -w SECRET -U` |
| 显示文件管理器中此项 | `open -R /path/to/file`（Tauri：`tauri-plugin-opener` 的 `revealItemInDir`） |
| 用默认应用打开 | `open <path or url>` |
| 通知 | `osascript -e 'display notification "x" with title "y"'` 或通知插件 |
| 系统代理 | `scutil --proxy` |
| 应用 bundle 信息 | `mdls -name kMDItemVersion /Applications/X.app` |
| 看 entitlements | `codesign -d --entitlements - /Applications/X.app` |
| 看签名 | `codesign -vv -d /Applications/X.app` |
| 检查公证 | `spctl -a -vvv -t install /Applications/X.app` |
| 卸载（含偏好） | `rm -rf ~/Library/Application\ Support/<id>` + `~/Library/Preferences/<id>.plist` |

---

## 16. 最小起步建议

如果你要从零做一个 Mac 小工具：

1. `pnpm create tauri-app` 选 React+TS。
2. 修改 `src-tauri/tauri.conf.json`：
   - `identifier`（反过来的域名）
   - 窗口尺寸、`titleBarStyle: "Overlay"`
   - `minimumSystemVersion: "12.0"` 大概够用
3. 想要菜单栏图标：抄 cc-switch 的 [`tray.rs`](src-tauri/src/tray.rs)，模板图标命名带 `Template`。
4. 要本地存 token：用 `keyring` crate。
5. 要读用户家目录的 JSONL/JSON：直接 `std::fs`，无需任何 entitlement。
6. 要持久化设置：`tauri-plugin-store` 最省事。
7. 上 GitHub 发布前：申请 Developer ID 证书 + 公证；或者至少在 README 写"右键打开"。
8. 用户量上来再考虑：自动更新 → Homebrew cask → 国际化。

---

## 17. cc-switch 里值得抄的 Mac 相关代码

| 主题 | 文件 |
|---|---|
| Activation Policy 切换（Dock 显隐） | [src-tauri/src/tray.rs:659](src-tauri/src/tray.rs) |
| 托盘模板图标加载 | [src-tauri/src/lib.rs:188](src-tauri/src/lib.rs) |
| 开机自启（.app bundle 路径修正） | [src-tauri/src/auto_launch.rs](src-tauri/src/auto_launch.rs) |
| Keychain 读凭据（多服务名） | [src-tauri/src/services/subscription.rs:125](src-tauri/src/services/subscription.rs) |
| Deep link 注册 + 单实例转发 | [src-tauri/src/lib.rs:208](src-tauri/src/lib.rs) |
| 窗口关闭时最小化到托盘 vs 退出 | [src-tauri/src/lib.rs:253](src-tauri/src/lib.rs) |
| Panic hook 写崩溃日志 | [src-tauri/src/panic_hook.rs](src-tauri/src/panic_hook.rs) |
| Tauri 配置示例 | [src-tauri/tauri.conf.json](src-tauri/tauri.conf.json) |

---

## 18. 一些我踩过的"非常 mac"的坑

1. **`include_bytes!` 路径以 .rs 所在目录为基准**，不是 crate 根。
2. **`std::env::current_exe()` 在 Mac 上返回 `.../X.app/Contents/MacOS/X`**，不是 `.app`。判断"运行在 bundle 里"靠这个路径里有没有 `.app/`。
3. **公证需要 hardened runtime 已启用**，Tauri 默认开。如果你用 `unsafe_eval` 之类的 entitlement 反而会被拒。
4. **WKWebView 不允许加载 `file://` 资源到 `http(s)://` 页面里**（除非配 `assetProtocol`）。Tauri 提供 `asset://` 协议绕过。
5. **macOS 区分大小写文件系统是可选的**，默认 APFS 不区分。代码里别假设 case-sensitive。
6. **拖拽到 dock 图标会触发 `OpenURL` 或 `OpenFiles` AppleEvent**，要用 deep-link 插件或 `RunEvent::Opened` 处理。
7. **第一次启动很慢**：Gatekeeper 在线验证签名 + dyld 缓存还没建立，是正常现象。

---

完。这个文档只是个索引，每个主题往深了挖都能写一本书；但作为「一周内做出来一个能在 Mac 上跑的小工具」的入门地图，应该够用了。
