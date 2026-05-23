# cockpit-tools 中的 macOS 开发要点速记

> 一份从 Cockpit Tools 源码里整理出来的 macOS 应用开发参考清单，覆盖
> 常见话题：路径与文件、权限、菜单栏（Tray）、Dock、窗口、原生通知、
> 深链接、自动启动、单实例、自动更新、Swift 互操作、打包签名。
> 适合你做一个小工具时当 checklist 用，**简明扼要**，不深入每个细节。

---

## 1. 项目里用到的栈

- **Tauri 2**：Rust 后端 + React/Vite 前端，跨平台。
- **Rust ↔ Cocoa**：用 `objc2 / objc2-app-kit / objc2-foundation`（现代、类型安全，比老的 `cocoa` crate 好用）。
- **Swift Package + swift-rs**：拿不动的 AppKit 部分（自定义弹层菜单、NSPopover）就单独写 Swift Package，用 `swift-rs` 在 `build.rs` 里编进来。
- **mac-notification-sys**：发系统通知。
- **dirs crate**：跨平台拿 `home_dir` / `data_dir` 等。
- **trash crate**：跨平台「移到废纸篓」。

`Cargo.toml` 关键片段：
```toml
[target.'cfg(target_os = "macos")'.dependencies]
mac-notification-sys = "0.6"
objc2 = "0.6"
objc2-foundation = "0.3"
objc2-app-kit = "0.3"

[build-dependencies]
swift-rs = { version = "1.0.7", features = ["build"] }
```

---

## 2. 文件系统 / 路径

### 2.1 跨平台拿用户目录

```rust
use dirs;
dirs::home_dir()          // ~
dirs::config_dir()        // ~/Library/Application Support  (macOS)
dirs::cache_dir()         // ~/Library/Caches
```

Tauri 里更推荐 `AppHandle::path()`，它自动按 bundle identifier 落盘：

```rust
let data_dir   = app.path().app_data_dir()?;    // ~/Library/Application Support/<bundleId>/
let config_dir = app.path().app_config_dir()?;
let log_dir    = app.path().app_log_dir()?;     // ~/Library/Logs/<bundleId>/
```

### 2.2 读其他 App 留下的文件

像项目里读 `~/.codex/auth.json` / `~/.vscode/...` 这种**跨进程共享文件**，路径都拼自 `dirs::home_dir()`，并允许用环境变量覆盖（参考 `resolve_codex_home_from_env`），方便用户在自定义路径时也能用。

### 2.3 原子写入（必备）

为防止「写一半应用挂了得到半坏文件」，项目自己封装了 `modules::atomic_write`：
**先写 `path.tmp` → `fsync` → `rename` 到目标**。
所有 token 文件、`auth.json` 注入、settings 都走这个，**强烈建议你也这么做**。

### 2.4 「移到废纸篓」

```rust
trash::delete(path)?;   // 而不是直接 fs::remove_file
```

---

## 3. 权限模型（你最容易踩坑的地方）

macOS 的权限分两类：**沙盒里 entitlements 决定能不能**，**TCC 决定第一次弹什么提示**。

| 你想做什么 | 需要什么 |
|---|---|
| 读用户的 `~/Library/Application Support/<别人App>` | **沙盒里默认禁，普通分发 App 不沙盒就能读。** 如果开沙盒，需要 `com.apple.security.files.user-selected.read-write` + 用户在系统弹窗里授权。 |
| 读 `~/Documents`、`~/Desktop`、`~/Downloads` | 第一次访问会触发 TCC 弹窗（系统设置 → 隐私与安全 → 文件与文件夹）。 |
| 读他人 App 的私有数据（Mail、Messages、Safari 等） | 需要 **完全磁盘访问**（Full Disk Access），用户得手动去系统设置开。 |
| 屏幕录制、辅助功能、相机麦克风 | 各自独立的 TCC 类别，第一次调用 API 才会弹。 |
| 网络访问 | 不沙盒不要 entitlement；沙盒要 `com.apple.security.network.client`。 |
| 后台/启动登录项 | 用 `tauri-plugin-autostart`，本质封装了 `LaunchAgents` 或 ServiceManagement。 |
| Apple Events（操控其他 App） | `NSAppleEventsUsageDescription` + 第一次会弹 TCC。 |

Cockpit Tools **没有开沙盒**（这是大多数开发者工具的选择），所以读 `~/.codex/auth.json` 之类直接 `fs::read_to_string` 就行。
如果你最终要上 Mac App Store，就必须开沙盒，那一堆「读别人家文件」的能力就基本没了。

### Info.plist 里常用的 Usage Description（哪怕只是为了不被审核拒）

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Cockpit Tools 通过系统事件唤起目标 IDE。</string>
<key>NSDocumentsFolderUsageDescription</key>
<string>用于导入/导出账号配置文件。</string>
```
Tauri 里改 `tauri.conf.json` → `bundle.macOS.info_plist` 或单独 plist 文件。

---

## 4. 菜单栏（Tray / Status Bar）

Tauri 自带 `tray-icon` feature 已经能满足 99% 需求：

```toml
tauri = { version = "2", features = ["tray-icon", "image-png"] }
```

```rust
TrayIconBuilder::new()
    .icon(Image::from_path("icons/tray.png")?)
    .menu(&menu)
    .on_tray_icon_event(|tray, event| { ... })
    .build(app)?;
```

但项目还做了一件高级的：**完全自定义的 NSPopover 菜单**，因为 Tauri 自带的菜单是 NSMenu，没法塞自定义内容（带头像、进度条之类）。
做法：单写一个 Swift Package（`src-tauri/native/macos-native-menu/`），里面用 `NSPopover + NSHostingController(SwiftUI)`，再用 `swift-rs` 在 `build.rs` 里编进来，Rust 那边声明 `extern "C"` 调进去：

```rust
unsafe extern "C" {
    fn macos_native_menu_toggle(json: *const c_char, status_item_ptr: *mut c_void);
}
```

—— 想做花哨菜单栏 App 时，这是参考价值最大的部分。

### NSStatusItem 关键设置

```rust
status_item.setAutosaveName(NSString::from_str("CockpitToolsStatusItem"));
status_item.setLength(NSVariableStatusItemLength);
```
`autosaveName` 让用户拖动菜单栏排序后下次还在原位。

---

## 5. Dock 图标 / 激活策略

「能不能在 Dock 显示图标」走 `NSApplication.activationPolicy`，Tauri 直接封装：

```rust
app.set_activation_policy(ActivationPolicy::Accessory); // 不显示 Dock，纯菜单栏 App
app.set_activation_policy(ActivationPolicy::Regular);   // 常规 App
app.set_dock_visibility(false);                         // macOS 14+ 才有
```

切换时机：用户开关「隐藏 Dock 图标」时实时切（见 `apply_macos_activation_policy`）。

---

## 6. 窗口 / 透明 / 圆角 / 「不抢焦点」浮窗

项目里的「悬浮卡片」窗口（`floating_card_window.rs`）配置：

```jsonc
{
  "decorations": false,    // 无标题栏
  "transparent": true,     // 透明背景
  "shadow": false,
  "resizable": false,
  "skipTaskbar": true,
  "alwaysOnTop": false,
  "visible": false         // 默认隐藏，按需 show()
}
```

主窗口的「内容延伸到标题栏」效果用：
```jsonc
{ "titleBarStyle": "Overlay", "hiddenTitle": true }
```
配合 `app.macOSPrivateApi: true` 才能使用部分私有 API。

**圆角窗口**：Tauri 没有直接 API，得拿到 `NSView` 改 `wantsLayer / cornerRadius`：

```rust
use objc2_app_kit::NSWindow;
let ns_view = ns_window.contentView();
ns_view.setWantsLayer(true);
let layer = ns_view.layer();
layer.setCornerRadius(12.0);
layer.setMasksToBounds(true);
```

---

## 7. 系统通知

```rust
mac_notification_sys::send_notification("标题", None, "正文", None)?;
```

Tauri 也有 `tauri-plugin-notification`，跨平台用它就够了。
要做「带按钮、回调」的富通知就只能走原生 `UNUserNotificationCenter`（项目没用到）。

---

## 8. Deep Link（`cockpit://...`）

```toml
tauri-plugin-deep-link = "2"
tauri-plugin-single-instance = { version = "2", features = ["deep-link"] }
```

```rust
.plugin(tauri_plugin_deep_link::init())
.plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
    // 第二次启动时把参数转到第一个进程
}))
```

macOS 需要在 `tauri.conf.json` 里注册 URL scheme（生成到 Info.plist 的 `CFBundleURLTypes`）。
注意 macOS 上是**通过 NSApplication open URL 事件**送进来，不是命令行参数，但 plugin 已经统一封装了。

---

## 9. 单实例（避免开两份）

`tauri-plugin-single-instance` 自动处理。
配合 deep-link：第二次启动会把参数交回首个进程的回调（项目里用来处理「从浏览器点击 oauth 回调链接」）。

---

## 10. 开机自启

```toml
tauri-plugin-autostart = "2"
```
macOS 它走的是 `~/Library/LaunchAgents/` 下生成 plist；用户能在系统设置「登录项」里看到。
不需要你自己写 launchd plist。

---

## 11. 自动更新

```toml
tauri-plugin-updater = "2.10.0"
```
- 用 `minisign` 签名 zip/dmg；
- 用 `tauri-plugin-process` 触发重启。
- 私钥不要进仓库，CI 里走 secret。

---

## 12. Swift 互操作（你迟早会用到）

模式：

```
src-tauri/native/<name>/
  Package.swift
  Sources/<Target>/*.swift   # 业务代码
  Sources/<Target>/Resources # SwiftUI 用的资源
```

`build.rs`：
```rust
swift_rs::SwiftLinker::new("12")           // 最低 macOS 12
    .with_package("MyNativeBridge", "native/my-bridge")
    .link();
```

Swift 侧用 `@_cdecl` 暴露 C ABI：
```swift
@_cdecl("my_native_toggle")
public func my_native_toggle(_ jsonPtr: UnsafePointer<CChar>?) { ... }
```

Rust 侧：
```rust
unsafe extern "C" {
    fn my_native_toggle(json: *const c_char);
}
```

**踩坑提醒**：
- Swift 里 UI 操作必须在主线程，跨语言调用前先 `NSThread.isMainThread` 判一下，必要时 `dispatch_async(main)`。
- 字符串穿越边界用 CString，记得双方都明确所有权。

---

## 13. 打包 / 签名 / 公证

- 在 `tauri.conf.json` 的 `bundle.macOS` 里填 `signingIdentity / providerShortName / entitlements`。
- 必须用 **Developer ID Application** 证书签，再用 `xcrun notarytool submit` 公证、`stapler staple` 装订。
- 没公证的 dmg 用户首次打开会被 Gatekeeper 拦截。
- CI（GitHub Actions）里可以用 `apple-actions/import-codesign-certs` 导证书。

---

## 14. 调试小技巧

| 想看什么 | 怎么看 |
|---|---|
| App 日志 | `Console.app` 里按 bundle id 过滤；项目用 `tracing-appender` 写 `~/Library/Logs/<bundle>/` |
| 权限弹窗历史 | `tccutil reset All <bundleId>` 重置后重新触发 |
| 自启项是否生效 | `launchctl list | grep <bundleId>` |
| URL scheme 是否注册 | `/usr/bin/open "yourscheme://test"` |
| WebView 调试 | `tauri.conf.json` 里 `app.withGlobalTauri` + debug 构建可右键检查 |

---

## 15. 你最少要会的 10 件事

1. 拿目录用 `dirs` / `AppHandle::path()`，不要硬编码 `/Users/xxx`。
2. 写敏感文件先 tmp + rename。
3. **不要**在主线程之外操作 UI（Cocoa 会崩）。
4. 沙盒一开，能读的东西骤减——发布前想清楚走哪条路径。
5. Tray + Popover 是菜单栏 App 的灵魂，记得设 `autosaveName`。
6. Dock 图标可切（Regular / Accessory）。
7. 通知 / 自启 / 单实例 / 深链 / 更新 全都有现成 Tauri plugin，不要自己造。
8. Swift 互操作走 `swift-rs` + `@_cdecl`，比硬写 Objective-C 桥舒服。
9. Info.plist 的 `NSXxxUsageDescription` 不写，App 一调相关 API 就直接 crash。
10. 发布前必做：签名 + 公证 + stapler，否则用户安装一脸黄字。
