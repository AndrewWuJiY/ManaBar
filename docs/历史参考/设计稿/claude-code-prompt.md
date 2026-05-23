# 给 Claude Code 的开发 prompt（直接复制以下全部内容）

---

请帮我开发一个原生 macOS 菜单栏应用 **cc-bar**，用来监控我电脑上 Codex（OpenAI）和 Claude Code（Anthropic）的额度。下面是完整的产品需求 + 设计规范 + 实现指引，请严格按照执行。

## 一、技术栈（必须）

- **SwiftUI + AppKit 混合**，Xcode 项目
- macOS 14+ 部署目标，针对 **macOS 26 SDK** 编译（用到 Liquid Glass 材质和新版控件）
- 菜单栏用 `MenuBarExtra` 或 `NSStatusItem`
- 弹出面板用 `NSPopover`
- 桌面悬浮窗用 `NSPanel`（`.nonactivatingPanel` + `.canJoinAllSpaces` + `.stationary`，level = `.statusBar - 1`）
- 统计窗口和偏好窗口用普通 SwiftUI `Window` / `Settings` scene
- 用量历史用 **SwiftData**（或 SQLite），图表用 **Swift Charts**
- 开机启动用 `SMAppService.mainApp`
- 中英双语，`Localizable.strings` 加 `en` 和 `zh-Hans`

## 二、设计风格（macOS 26 Tahoe · Liquid Glass）

**整体气质**：克制、原生、半透明磨砂材质，圆角连续曲率（squircle），所有控件都用系统原生外观，**禁止**自造 Material/Bootstrap 风格按钮。

### 材质（关键）

- 所有半透明面板用 `NSVisualEffectView`：
  - 菜单栏弹出面板：`material: .popover`，`blendingMode: .behindWindow`
  - 桌面悬浮窗：`material: .hudWindow`
  - 窗口标题栏 / 侧边栏：`material: .sidebar`
- SwiftUI 里就是 `.background(.regularMaterial)` 或 `.thinMaterial`
- 面板顶部加一条 1pt 高的高光：白色从 0.18 透明度渐变到 0（模拟玻璃反光）

### 字体

- 全部用 `-apple-system` / `.systemFont`
- 标题用 SF Pro Display，正文用 SF Pro Text（系统自动切）
- **所有数字**必须 tabular figures：SwiftUI 用 `.monospacedDigit()`

### 字号 + 字重

| 用途 | 字号 | 字重 | tracking |
|---|---|---|---|
| KPI 大数字 | 22–38pt | 600 | -0.5 |
| 窗口标题 | 13pt | 600 | -0.1 |
| 节标题 | 13pt | 600 | - |
| 正文 | 12.5pt | 400/500 | - |
| 次要 caption | 11pt | 400 | - |
| 小标签（大写） | 10–11pt | 600 | +0.4 大写 |
| 等宽小字 | 10pt | 400 | SF Mono |

### 圆角

- 窗口 12pt · 弹出面板 18pt · HUD 14pt
- 卡片/分组 10–12pt · 行内 pill 6–8pt
- 切换开关、按钮维持系统默认

### 颜色

**全部用 macOS 系统语义色**：`.labelColor`、`.secondaryLabelColor`、`.tertiaryLabelColor`、`.separatorColor`、`.quaternarySystemFill`，accent 用 `systemBlue`。

**产品识别色**（这两个写死，用来区分两个服务）：

| 服务 | 浅色 | 深色 |
|---|---|---|
| Codex | `#6C6C70`（石墨灰） | `#98989D` |
| Claude Code | `#D97757`（桃橙） | `#E68A6E` |

**状态色**：
- 剩余 ≥ 20% → 服务自身色
- 剩余 < 20% → `systemOrange` (#FF9F0A)
- 剩余 = 0 / 超限 → `systemRed`

### 双语标签规则

- 主标签英文，下方或后方小一号灰色补中文
- 例：`Menu Bar · 菜单栏`、`Codex` + 下行 `OpenAI · GPT-5`
- 写在 strings 文件里，组合：
  ```swift
  Text("Menu Bar") + Text(" · ").foregroundStyle(.secondary)
                   + Text("菜单栏").foregroundStyle(.secondary)
  ```

### 阴影

- 窗口：`0 24 60 rgba(0,0,0,0.22)` + `0 2 8 rgba(0,0,0,0.08)` + 内阴影描边 `inset 0 0 0 0.5 rgba(0,0,0,0.18)`
- 弹出面板：`0 14 38 rgba(0,0,0,0.22)`
- HUD：`0 10 28 rgba(0,0,0,0.28)` + 内白描边

### 动画

- 弹出面板出现：180ms cubic-bezier(0.2, 0.9, 0.3, 1.15)，从 `scale(0.96) translateY(-6)` 到 1
- 窗口出现：220ms ease-out，scale 0.97 → 1
- hover：100–120ms ease-out
- 切换开关拨动：150ms ease-out
- 刷新图标旋转：700ms ease-in-out 转 1 圈

---

## 三、6 个界面的布局（按这个顺序实现）

### ① 菜单栏图标

**默认形态：图标 + 百分比**

- SF Symbols 风的"仪表盘 + 火花"glyph，14pt
- 后跟空格 + 百分数（如 `62%`），等宽数字
- 百分数 = `min(codex5h剩余, claude5h剩余)`（取更紧迫的一个），或用户设置的固定服务
- hover：背景 `rgba(255,255,255,0.10)`（深色）/ `rgba(0,0,0,0.06)`（浅色），22pt 高，5pt 圆角
- 单击 → 切换弹出面板
- 右键/⌥ 单击 → 原生菜单：`Open Statistics… ⌘1` / `Preferences… ⌘,` / `Refresh now ⌘R` / 分隔 / `About cc-bar` / `Quit cc-bar ⌘Q`

**偏好设置里可让用户切换的 7 种备选形态**（先实现默认，备选作为下拉选项）：
1. 仅图标
2. 图标 + %（默认）
3. 两个 pill 并排：`C 42%`（灰）+ `CC 78%`（桃）
4. 迷你环 + %
5. 双行迷你条（C 一条、L 一条）
6. 纯文字 `C 42% · L 78%`
7. 低于 20% 时整体变橙色
8. 后缀 `5H` / `WK` 小 chip 标识当前显示的是哪个时段

### ② 弹出面板（点击菜单栏图标弹出）

**布局 A · 纵向列表**（推荐）

- 宽 340pt，高自适应（两个服务约 360pt）
- 18pt 圆角，Liquid Glass 材质
- 顶部一个 7pt 高的小箭头三角，指向菜单栏

从上到下分块：

1. **标题行**（14pt 上、16pt 左右内边距）
   - 左：`Usage`（13pt 600）+ 下方 `用量 · refreshed 32s ago`（11pt 次要）
   - 右：刷新图标按钮（圆形箭头 14pt）+ 折叠菜单按钮
   - 底部 0.5pt 分隔线

2. **Codex 块**（14pt 内边距，**始终排第一**）
   - 头部行：
     - 22pt 圆角方形 tile（6pt 圆角，石墨灰底）+ Codex glyph
     - `Codex` 13pt 600 + 下方 `OpenAI · Plus` 10.5pt 次要
     - 右侧 `resets in 2h 18m`（11pt 等宽次要）
   - 内容行（12pt 上间距）：
     - 左：**56pt 环形进度条**（5.5pt 粗），中心显示百分数 + 下方 `5H` 小标
     - 右：
       - 行 1：`Weekly · 周额度` 左、`31%` 右
       - 行 2：5pt 高的进度条（2.5pt 圆角）
       - 行 3：`184k / 440k` `tokens used` + `$12.40` `this week`（9pt 上间距）

3. **0.5pt 分隔线**（左右各内缩 16pt）

4. **Claude Code 块**：和 Codex 完全一样的结构，桃色

5. **底部行**（10pt 12pt 内边距，顶部 0.5pt 分隔线）
   - 左：`Open Statistics · 查看统计`（带菜单图标）
   - 右：刷新 + 设置图标按钮

**交互**：
- 点击外部任何位置 → 关闭
- 点击刷新图标 → 强制刷新，按钮旋转 360°
- 点击 `Open Statistics` → 关闭面板，打开统计窗口
- 点击 Codex 块 / Claude 块 → 打开统计窗口并定位到该服务

### ③ 桌面悬浮窗 HUD

**默认形态：两行 pill**

- 14pt 圆角，`hudWindow` 材质，深色透明度 0.62
- 内边距 10pt 14pt，最小宽度 168pt
- 两行（行间距 7pt），每行：
  - 44pt 宽的大写小标签（`Codex` / `Claude`，10.5pt 600，次要色）
  - 中间弹性进度条（4pt 高，2pt 圆角）
  - 右侧百分数（13pt 600，等宽，**服务自身色**，最小宽度 34pt）

**行为**：
- 可拖拽到屏幕任何位置，按下到 20pt 边缘范围内自动吸边
- 始终置顶（不被普通窗口遮挡）
- 所有桌面空间都显示
- 位置持久化

**偏好里 8 种备选形态**：两行 pill（默认）/ 堆叠大数字 / 双迷你环 / 极薄细行 / 单服务大环 / 横向胶囊 / 5h+周双数 / 无 chrome 纯文字

### ④ 统计窗口（标准窗口）

**工具栏**：
- 标题 `Statistics · 用量统计`
- 右侧 **segmented control**，7 个时段预设：`Today` / `Week` / `Month` / `7d` / `30d` / `All` / `Custom`
- 选中段填充 `.quaternarySystemFill`，字重 600

**左侧栏**（200pt 宽，`.sidebar` 材质）：

3 个分组，每组一个全大写灰色小标题：
- `Range · 时间范围`：和工具栏一致的 7 个预设（点选同步）
- `Service · 服务`：All / Codex / Claude Code（每行带颜色点）
- `View · 视图`：Overview（默认）/ Timeline / Breakdown

每行高度 ~24pt，5pt 8pt 内边距，6pt 圆角，左图标 + 双语标签，选中行 accent 蓝底白字。

**主区 — Overview 视图**：

1. **KPI 卡片行**（4 列等宽，12pt gap）
   每张：10pt 圆角，白底 / `.regularMaterial`，11pt 14pt 内边距
   - 标签（11pt 次要）+ 中文（10pt 三级）
   - 数值（22pt 600 -0.5 tracking 等宽）
   - 变化 chip：`↑ 12.4%`（绿）或 `↓ X%`（红）
   - 服务卡片前面带 6pt 颜色点
   - 4 张：`Total tokens` / `Total spend` / `Codex` / `Claude Code`

2. **Daily usage 面板**（12pt 圆角，16pt 内边距）
   - 标题 `Daily usage · 每日用量` + 右侧图例
   - 160pt 高 **堆叠条形图**（每天一条，Codex 灰下、Claude 桃上，3pt 间隔，2pt 圆角）
   - 下方日期轴：`Jul 16 / Jul 23 / Jul 30 / Aug 06 / Today`

3. **两栏行**（1.4 : 1）
   - 左：`By service · 按服务` 面板，每个服务一行（颜色点 + 名 + 中文 + 右侧 13pt 600 金额 + 进度条 + `Xk tokens` + `Y% of spend`）
   - 右：`Current limits · 当前限额` 面板，4 个小环排列（Codex 5h / Codex Week / Claude 5h / Claude Week），每个带 `resets in …`

**主区 — Timeline 视图**：
- `Tokens · hourly` 折线面积图（220pt 高，两条平滑曲线 + 渐变填充 0.4→0）
- `Hourly pattern` 热力图（7 天 × 24 小时，每格 14pt 高，强度 = Claude 用量，周末弱化）
- `Spend split` 110pt 甜甜圈，中心 `$1,284 total · 总计`，图例两个服务 + 占比

**Custom 范围**：点击 `Custom` 在工具栏下方弹出 2 个 `DatePicker` + `取消 / 应用` 行。

### ⑤ 偏好设置

单页窗口，680 × ~780pt，分组卡片（macOS 26 风）。从上到下：

- **Accounts · 账号**：每行 = 28pt 服务图标 tile + 名 + 中文 + 邮箱 + `Connected · 已连接`（绿点）+ NSSwitch 开关
- **Menu Bar · 菜单栏**：
  - `Show in menu bar` toggle
  - `Display` 下拉（8 种形态）
  - `Show service` 复选（Codex / Claude）
  - `Quota period` 单选（5 小时 / 周额度 / 两者轮播）
- **Floating HUD · 桌面悬浮窗**：
  - `Show floating window` toggle
  - `Show service` 复选
  - `Style` 下拉（8 种 HUD 形态）
  - `Position` 下拉（4 个角落，或拖到的最后位置）
  - `Opacity when idle` 滑块（0.3–1.0）
- **Refresh · 刷新**：
  - `Auto refresh` toggle
  - `Interval` 下拉（15s / 30s / 1m / 2m / 5m / 10m / 15m）
  - `Last refresh` 时间戳显示
- **General · 通用**：
  - `Launch at login` toggle（用 `SMAppService`）
  - `Show in Dock` toggle
  - `Language` 下拉（跟随系统 / 中文 / English）

每行：10pt 14pt 内边距，0.5pt 顶部分隔线，左标签右控件，可有次要说明行。

### ⑥ 首次启动引导

**Step 1 · Welcome**
- 居中 96pt 应用图标（圆角方形，灰→桃渐变）
- `Welcome to cc-bar` 22pt 700 + 下方 `欢迎使用 cc-bar` 14pt 次要
- 两行描述（英 + 中）
- `Get started · 开始` 主按钮 + `What's new in 1.0` 链接
- 底部 4 个圆点分页指示

**Step 2 · Detect accounts**
- 标题 `We found these accounts` + 中文副标题
- 列表，每行：复选框 + 34pt 服务 tile + 名 + 中文 + 邮箱 + 源文件路径（等宽小字）
- 蓝色 tint 提示卡：`Read-only access · 仅读取` + 不上传凭据的说明
- 底部：`Back`（幽灵）· `Add manually`（次要）· `Continue`（主）

**Step 3 + 4**：菜单栏 / HUD 偏好实时预览 → 完成进入应用

---

## 四、账号检测路径（首次启动 + Preferences 里的"重新扫描"按钮触发）

**Codex（OpenAI codex CLI / Plus 订阅）**：
- `~/.codex/auth.json`
- `~/.codex/config.toml`

**Claude Code（Anthropic claude CLI）**：
- `~/.claude/credentials.json`
- `~/.claude/.credentials.json`
- macOS Keychain：service = `claude-code`

读取邮箱 / 套餐信息显示给用户，**绝不上传或转发凭据**。

## 五、数据模型（Swift）

```swift
enum Service: String, Codable { case codex, claudeCode }

struct Account: Identifiable, Codable {
    let id: UUID
    var service: Service
    var displayName: String     // "Codex (Work)"
    var email: String?
    var plan: String?           // "Plus" / "Max 20×"
    var credentialPath: String
    var enabled: Bool
}

struct WindowQuota: Codable {
    var used: Int               // tokens
    var cap: Int
    var spendUSD: Double
    var percentUsed: Double { Double(used) / Double(cap) }
}

struct QuotaSnapshot: Codable {
    let accountId: UUID
    let fetchedAt: Date
    var fiveHour: WindowQuota
    var weekly: WindowQuota
    var resetAt5h: Date
    var resetAtWeek: Date
}

struct UsageEvent: Codable {     // 持久化到 SwiftData，给统计窗口用
    let accountId: UUID
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
}

protocol QuotaProvider {
    func fetchSnapshot(for account: Account) async throws -> QuotaSnapshot
    func recentUsage(for account: Account, in range: DateInterval) async throws -> [UsageEvent]
}
```

为 Codex 和 Claude Code 分别实现一个 `QuotaProvider`。具体调哪个官方接口请自行查最新文档；如果没有公开接口，回退到解析本地 CLI 日志。

## 六、快捷键

- `⌘,` 打开 Preferences
- `⌘1` 打开 Statistics
- `⌘R` 立即刷新
- `⌘W` 关闭当前窗口
- `Esc` 关闭弹出面板

## 七、状态指示

- 绿色点 + `live`：在刷新间隔内
- 橙色点 + `stale`：上次刷新 > 2 倍间隔
- 红色点 + `offline`：连续 3 次失败

## 八、实现顺序建议

1. 工程骨架：菜单栏图标 + 空 popover（Liquid Glass 壳）
2. 数据层：`Account`、`QuotaSnapshot`、`QuotaProvider` 协议、定时刷新
3. 账号检测 + 偏好里的账号开关
4. Popover 完整 UI（最先要做到能用）
5. HUD 悬浮窗
6. 偏好设置完整页
7. 统计窗口（先 Overview 再 Timeline）
8. 首次启动引导
9. 中英双语 strings、深浅模式、沙盒 / 公证

## 九、注意事项

- 沙盒 + Hardened Runtime entitlement 全开，读凭据文件用 Security-Scoped Bookmarks
- 中文翻译要短而地道，不要直译（参考上面用过的"用量"、"已连接"、"额度"）
- **每个屏幕都要在浅色 + 深色下检查**
- 数字一律 tabular figures，不然刷新时会跳动
- 不要为 SVG / 图片再造轮子，全部用 SF Symbols：`gauge.medium`、`arrow.clockwise`、`chart.bar.xaxis`、`gear`、`xmark.circle.fill` 等

---

请按上面规范开始，先创建 Xcode 项目并完成第 1 步（菜单栏图标 + 空 popover 的 Liquid Glass 壳），完成后告诉我，我们再继续往下走。
