# CodexBar macOS 应用开发参考笔记

本文档基于 CodexBar 的实现,梳理一个 **菜单栏类 macOS 应用** 在开发过程中会遇到的关键技术点。适合刚接触 macOS / SwiftUI 原生开发的人作为索引使用 —— 每节先讲"是什么/为什么用得到",再给出 CodexBar 里的对应代码位置,需要时再去翻源码。

---

## 一、技术栈与项目结构

- **语言/构建**:Swift 6,Swift Package Manager(SPM)管理,没有用 Xcode 项目文件(`.xcodeproj`)。
- **平台**:`platforms: [.macOS(.v14)]` —— 最低 macOS 14 (Sonoma)。
- **UI**:SwiftUI 为主,但菜单栏、PTY、WebView 这些底层场景仍混用 AppKit。
- **多 target 拆分**(参考 [Package.swift](../Package.swift)):
  - `CodexBarCore` —— 跨平台的纯逻辑(可以在 Linux 跑测试)。
  - `CodexBar` —— macOS 主 App。
  - `CodexBarCLI` —— 命令行工具(同样的 Core 复用)。
  - `CodexBarWidget` —— 桌面/通知中心小组件(WidgetKit)。
  - `CodexBarClaudeWatchdog` / `CodexBarClaudeWebProbe` —— 独立的小型子进程二进制。
  - `CodexBarMacros` / `CodexBarMacroSupport` —— Swift Macro 插件。

**关键经验**:**核心逻辑独立成 framework target**,让 GUI、CLI、Widget、子进程都能复用,也方便单元测试。

### 常用第三方依赖

| 依赖 | 用途 |
|---|---|
| `Sparkle` | 应用自动更新(macOS 上的事实标准) |
| `KeyboardShortcuts`(sindresorhus) | 全局快捷键注册/录入 UI |
| `swift-log` / `swift-crypto` | 标准库 |
| `SweetCookieKit` | 跨浏览器 Cookie 读取 |
| `Sparkle` 配套的 `appcast.xml` | 描述新版本元数据 |

---

## 二、菜单栏(Menu Bar)应用

代码:`Sources/CodexBar/StatusItemController.swift`、`Sources/CodexBar/MenuBarVisibilityWatcher.swift`

两个核心 API:

- **`NSStatusItem`(AppKit)**:在菜单栏右侧创建一个图标 + 弹出菜单。CodexBar 用的是这个(支持自定义绘制图标、动画、悬停文字等)。
- **`MenuBarExtra`(SwiftUI 14+)**:更简单的纯声明式写法,但灵活度低。

要让 App **只在菜单栏出现,不在 Dock 里显示**,需要在 `Info.plist` 加:

```xml
<key>LSUIElement</key><true/>
```

或在 SPM 里通过 `unsafeFlags` 或 `infoPlist` 注入(CodexBar 使用打包脚本注入 plist,见 `Scripts/`)。

---

## 三、文件系统访问

### 3.1 常用路径

| 用途 | API |
|---|---|
| 用户 home (`~`) | `FileManager.default.homeDirectoryForCurrentUser` |
| `~/Library/Application Support/<Bundle>` | `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, ...)` |
| `~/Library/Caches/<Bundle>` | `.cachesDirectory` |
| 临时目录 | `FileManager.default.temporaryDirectory` |
| 当前进程环境变量 | `ProcessInfo.processInfo.environment` |

CodexBar 在 [PathEnvironment.swift](../Sources/CodexBarCore/PathEnvironment.swift) 里集中处理 `$CODEX_HOME` / `$CLAUDE_CONFIG_DIR` 等环境变量回退。

### 3.2 沙盒(App Sandbox)

- **菜单栏小工具如果不上架 Mac App Store,通常不开沙盒**。CodexBar 就是这种,所以能直接读 `~/.codex/`、`~/.claude/`、`~/Library/Cookies/Cookies.binarycookies`。
- 一旦开启沙盒(`com.apple.security.app-sandbox` entitlement),应用只能读自己的容器目录 `~/Library/Containers/<Bundle>/Data/`,要读用户文件夹必须走"用户选择文件"(`NSOpenPanel`)拿到 *security-scoped bookmark* 才能复用。
- 上 App Store ⇔ 必须沙盒 ⇔ 几乎不可能做 CodexBar 这种工具,因此这类工具通常 **走 Sparkle 自分发,不进 App Store**。

### 3.3 增量读大文件 / JSONL 扫描

CodexBar 扫几百 MB 的 `*.jsonl`,用了:
- 文件大小 + 上次偏移量持久化在 JSON 缓存里。
- `FileHandle.seek(toOffset:)` + 按行读;Swift 现代写法可以用 `URL.lines` (async sequence) 但要注意内存。
- 路径:[CostUsageScanner.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift)。

### 3.4 文件变化监听

虽然 CodexBar 用定时轮询为主,但 macOS 提供了:
- `DispatchSource.makeFileSystemObjectSource(...)` —— 监听单个文件的 inode 事件。
- `FSEvents`(C API)—— 监听整个目录树。
- `NSMetadataQuery` —— Spotlight 风格的查询。

---

## 四、Keychain(钥匙串)

代码:`Sources/CodexBar/KeychainMigration.swift`、`Sources/CodexBarCore/KeychainCacheStore.swift`、各 `*TokenStore.swift`。

- API:`Security.framework` 的 `SecItemAdd / SecItemCopyMatching / SecItemUpdate / SecItemDelete`,字典里指定 `kSecClass = kSecClassGenericPassword`。
- 关键字段:`kSecAttrService`(你的服务名,如 `com.steipete.codexbar.cache`)、`kSecAttrAccount`(账号/key)、`kSecValueData`(存的 Data)。
- 用途:CodexBar 用 Keychain 存 Cookie 头缓存、各 Provider 的 token、Admin API Key,**避免明文落盘**。

**常见坑**:
- App 没签名时,首次写入 Keychain 系统会弹"允许访问"弹窗,且每次重新构建 binary 都会重弹。开发期最好用同一开发者证书签名(`codesign`)。
- 不同 binary(主 App、CLI、子进程)如果想共享 Keychain item,需要它们具备相同的 **Keychain Access Group / Team ID**。
- 读其他 App 的 Keychain item(例如 Claude CLI 写的 `Claude Code-credentials`),要么用 `security` 命令行(`security find-generic-password -s "Claude Code-credentials" -w`),要么直接用 `SecItemCopyMatching` —— 但都可能触发"App 想访问钥匙串"系统弹窗。CodexBar 在 [KeychainAccessPreflight.swift](../Sources/CodexBarCore/KeychainAccessPreflight.swift) 等文件里做了一套"是否允许触发弹窗"的策略。

---

## 五、运行子进程 / PTY

代码:[ClaudeCLISession.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift)、[CodexCLISession.swift](../Sources/CodexBarCore/Providers/Codex/CodexCLISession.swift)。

两种场景:

### 5.1 普通子进程

- 用 `Foundation.Process`(原 `NSTask`),设置 `executableURL`、`arguments`、`environment`,捕获 `Pipe()` 的 stdout/stderr。
- 适合像 `codex app-server` 这种纯 JSON-RPC over stdio 的程序。

### 5.2 PTY(伪终端)

- CLI 工具如 `claude`、`codex` 在直接给 Pipe 时表现和给真实终端不一样(颜色、TUI、`/` 命令行为)。需要 PTY 才能拿到"屏幕上看到的内容"。
- macOS 上用 `<util.h>` 的 `openpty()` / `forkpty()`,Swift 里通常封装一个 C bridging。
- 拿到的输出还要 **剥掉 ANSI 转义序列** 再正则匹配文本。

---

## 六、WebKit 抓页(隐藏 WebView)

代码:`Sources/CodexBarCore/OpenAIWeb/*`、`Sources/CodexBarCore/WebKit/*`。

- API:`WKWebView`(`WebKit.framework`),不需要把它加进视图层级,创建 off-screen 实例即可加载页面。
- **每账号独立 cookie 池**:用 `WKWebsiteDataStore(forIdentifier: UUID)`(macOS 14+ 引入),按账号 email 派生确定性的 UUID,各账号互不污染。
- 注入 JS:`WKUserContentController.addUserScript(...)`,在 `documentEnd` 注入抓 DOM 的脚本,通过 `WKScriptMessageHandler` 回传结构化结果。
- **绕开人机验证 / 登录页**:CodexBar 会检测 Cloudflare interstitial、登录跳转,直接报错让用户在 Preferences 手动处理。

---

## 七、读浏览器 Cookie(零授权)

代码:依赖 `SweetCookieKit`,以及 [BrowserCookieAccessGate.swift](../Sources/CodexBarCore/BrowserCookieAccessGate.swift)、[BrowserDetection.swift](../Sources/CodexBarCore/BrowserDetection.swift)。

- **Safari**:`~/Library/Cookies/Cookies.binarycookies`(自定义二进制格式,有现成解析器)。
- **Chrome / Edge / Brave 等 Chromium 系**:`~/Library/Application Support/<Vendor>/<Channel>/<Profile>/Cookies` —— SQLite 文件,加密 cookie 用 macOS Keychain 里的 `Chrome Safe Storage` key + AES 解密。
- **Firefox**:`~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite` —— 纯 SQLite,字段明文。

**坑**:
- macOS 15.3+ 起,读 Safari Cookie 文件要 **完全磁盘访问权限**(系统设置 → 隐私 → 完全磁盘访问)。CodexBar 会检测并提示用户授权。
- 浏览器在运行时锁住 SQLite,需要 `sqlite3_open_v2` 加 `SQLITE_OPEN_READONLY` + URI 参数 `?mode=ro&nolock=1`,或先拷贝出来再读。

---

## 八、网络请求

- 标准做法:`URLSession.shared.data(for: URLRequest)`(async/await)。
- CodexBar 自己封装了 [ProviderHTTPClient.swift](../Sources/CodexBarCore/ProviderHTTPClient.swift) 统一 timeout / 重试 / User-Agent。
- 不要轻信第三方 HTTP 库 —— `URLSession` 已经支持 HTTP/2、HTTPS、代理、cookie store。
- 如果调的接口要 `Cookie:` header,可以手动 set,也可以把 cookie 注入 `URLSession.configuration.httpCookieStorage`。

---

## 九、并发 / async

- Swift 6 严格并发模式(`StrictConcurrency`)默认开启,所有跨 actor 数据要 `Sendable`。
- UI 线程是 `@MainActor`;后台采集任务用普通 `Task { ... }`,UI 更新前 `await MainActor.run`。
- 不要再写 GCD `DispatchQueue.global().async`,统一走 `async/await` + `actor`。

---

## 十、SwiftUI + AppKit 混合

- 菜单栏弹出的菜单内容用 `NSMenu + NSMenuItem`(SwiftUI 的 `Menu`/`MenuBarExtra` 不够灵活)。
- 把 SwiftUI 视图塞进 NSMenu:`NSHostingView(rootView: yourView)` 包装后 `menuItem.view = hostingView`。
- 偏好设置窗口、关于面板等用纯 SwiftUI Window 即可(macOS 13+ 的 `WindowGroup` / `Settings` scene)。

---

## 十一、桌面 / 通知中心 Widget

代码:`Sources/CodexBarWidget/`。

- 用 `WidgetKit` + SwiftUI。Widget 是独立的 extension target,有自己的运行进程。
- **跨进程共享数据**:用 **App Group**(`group.com.steipete.codexbar`),`UserDefaults(suiteName:)` 或共享文件目录 `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`。CodexBar 的 [AppGroupSupport.swift](../Sources/CodexBarCore/AppGroupSupport.swift) 就是干这个。
- Widget 不能跑长时间任务,只能 `TimelineProvider` 提供"未来若干个时间点的快照"。

---

## 十二、通知 / 全局快捷键 / 开机启动

- **通知**:`UserNotifications.framework`(`UNUserNotificationCenter`),首次发会请求授权。
- **全局快捷键**:CodexBar 用 `KeyboardShortcuts` 库,底层是 Carbon `RegisterEventHotKey`,自带 UI 让用户改键。
- **开机自启**:[LaunchAtLoginManager.swift](../Sources/CodexBar/LaunchAtLoginManager.swift)。macOS 13+ 用 `SMAppService.mainApp.register()`(老系统要装个 LoginItem helper bundle,远比新 API 麻烦)。

---

## 十三、签名 / 公证 / 自动更新

这是发布给别人用之前绕不开的环节:

1. **签名(codesign)**:用 Developer ID Application 证书签名 `.app`,否则用户首次打开会被 Gatekeeper 拦下。
2. **公证(notarize)**:用 `xcrun notarytool submit ... --wait` 上传给苹果做自动扫描,通过后 `xcrun stapler staple` 把票据钉到 `.app` 上。
3. **打包**:做成 `.dmg` 或 `.zip` 给用户下载。
4. **自动更新(Sparkle)**:维护一个 `appcast.xml`([根目录就有](../appcast.xml)),Sparkle 会定期拉、比较版本、下载更新包、验签后替换自身。

详细配置看 [docs/RELEASING.md](RELEASING.md)、[docs/sparkle.md](sparkle.md)、[docs/packaging.md](packaging.md)。

---

## 十四、隐私权限弹窗一览

macOS 上很多敏感操作首次会弹"是否允许 App 访问 X",对应 `Info.plist` 里要写 *Usage Description*,例如:

| 权限 | plist Key |
|---|---|
| 麦克风 | `NSMicrophoneUsageDescription` |
| 摄像头 | `NSCameraUsageDescription` |
| 联系人 | `NSContactsUsageDescription` |
| AppleScript 控制其他 App | `NSAppleEventsUsageDescription` |
| 完全磁盘访问 | (无 plist,需要用户手动到"系统设置 → 隐私"加) |
| 辅助功能(模拟键鼠) | (同上,需手动加) |

不加描述就调对应 API 会直接 crash,这是新手最常踩的坑。

---

## 十五、调试 / 日志

- 系统统一日志:`os.Logger`(import `OSLog`),用 `log show --predicate 'subsystem == "com.steipete.codexbar"' --last 1h` 在 Console.app 查看。
- CodexBar 自己包了一层 [CodexBarLog.swift](../Sources/CodexBarCore/Logging/),分 category。
- 跑 PTY / 子进程时,把子进程的 stdout/stderr 也转发到 logger,出问题才好排查。

---

## 十六、推荐的最小起步路径

如果你想从零做一个"读本地 token 日志、菜单栏显示用量"的小工具:

1. `swift package init --type executable`,加 `platforms: [.macOS(.v14)]`。
2. 主入口里用 AppKit `NSApplication.shared.run()` + `NSStatusItem` 起菜单栏。或者最简单 —— `MenuBarExtra` (SwiftUI)。
3. 加 `LSUIElement = true`,不进 Dock。
4. 写一个 actor 周期性扫描 `~/.claude/projects/**/*.jsonl`,聚合 token 数。
5. 用 `NSHostingView` 把 SwiftUI 视图塞进菜单显示数据。
6. 等需要"调远端配额接口"再加 `URLSession`、Keychain 缓存等等。
7. 想发布就申请 Apple Developer ($99/年)→ 签名 → 公证 → 用 Sparkle 自分发,**不必上 App Store**。

不需要做的(初期):沙盒、entitlements、App Group、Widget、Macros。

---

## 附:CodexBar 里值得对照阅读的入口文件

| 主题 | 文件 |
|---|---|
| App 入口 | [CodexbarApp.swift](../Sources/CodexBar/CodexbarApp.swift) |
| 菜单栏图标控制 | [StatusItemController.swift](../Sources/CodexBar/StatusItemController.swift) |
| Keychain 封装 | [KeychainCacheStore.swift](../Sources/CodexBarCore/KeychainCacheStore.swift) |
| 子进程 / PTY | [ClaudeCLISession.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift) |
| WebView 抓页 | `Sources/CodexBarCore/OpenAIWeb/*` |
| 浏览器 Cookie | [BrowserCookieAccessGate.swift](../Sources/CodexBarCore/BrowserCookieAccessGate.swift) |
| HTTP 客户端 | [ProviderHTTPClient.swift](../Sources/CodexBarCore/ProviderHTTPClient.swift) |
| Widget | [Sources/CodexBarWidget/](../Sources/CodexBarWidget/) |
| App Group 共享 | [AppGroupSupport.swift](../Sources/CodexBarCore/AppGroupSupport.swift) |
| 开机自启 | [LaunchAtLoginManager.swift](../Sources/CodexBar/LaunchAtLoginManager.swift) |
| 自动更新配置 | [appcast.xml](../appcast.xml) + [docs/sparkle.md](sparkle.md) |
