# CodexBar 用量/额度采集实现分析

本文档基于对 CodexBar 仓库源码与官方说明文档(`docs/codex.md`、`docs/CLAUDE.md`)的分析,梳理 **Codex(ChatGPT/Codex CLI)** 与 **Claude Code** 两类客户端用量、额度、刷新时间、Token 计数与费用的获取方式,供你自己实现一个简化版小工具时参考。

---

## 一、整体架构:三类数据 + 多条采集通道

CodexBar 把"用量数据"拆成三个相对独立的概念,分别用不同通道采集:

| 数据类型 | 含义 | 主要来源 |
|---|---|---|
| **配额/额度窗口(rate limits)** | 5h 窗口、周窗口、月窗口的"已用百分比 + 重置时间" | 厂商官方 API(OAuth/Cookie)、CLI 内置命令 |
| **积分/钱包(credits / overage)** | 套餐外费用、剩余积分 | 同上 |
| **本地 Token 计数与费用** | 今日/本周/本月按模型聚合的 token 数与折算 USD | **扫描本地 CLI 写出的 `*.jsonl` 会话日志** |

关键点:**前两类必须靠用户已经登录的本地凭证去调远端 API**(配额状态在云端,本地拿不到);**第三类完全本地化**,只读会话日志就能算出 token 数与费用,不需要任何登录态。

---

## 二、Codex 数据采集

参考:[docs/codex.md](codex.md)、[Sources/CodexBarCore/Providers/Codex/](../Sources/CodexBarCore/Providers/Codex/)

### 2.1 凭证来源:直接读本地 `auth.json`

CodexBar 不要求用户在自己的 App 里再登录一次,而是**直接读 Codex CLI 已经写好的本地凭证文件**:

- 路径:`~/.codex/auth.json`(或 `$CODEX_HOME/auth.json`)
- 内容:OAuth `access_token` / `refresh_token` / `id_token` / `account_id` / `last_refresh`
- 代码:[CodexOAuthCredentials.swift](../Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift)
- 刷新策略:`last_refresh` 超过 **8 天**自动用 `refresh_token` 续期(`CodexTokenRefresher`)。

这是 CodexBar 的"零额外登录"基础:**只要用户在终端里跑过 `codex` 登录,App 就有权拿到全部用量**。

### 2.2 配额窗口/积分:三条通道(自动降级)

按优先级:

1. **OAuth API(默认)**
   ```
   GET https://chatgpt.com/backend-api/wham/usage
   Authorization: Bearer <access_token>
   ```
   返回:`plan_type` / `rate_limit.primary_window` / `rate_limit.secondary_window` / `credits`。
   每个 window 含 `used_percent`、`resets_at` 等字段 → 直接对应 UI 上的"5h"和"weekly"进度条与"X 分钟后重置"。
   实现:[CodexOAuthUsageFetcher.swift](../Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift)

2. **Codex CLI RPC(回退)**
   - 启动子进程:`codex -s read-only -a untrusted app-server`
   - 通过 stdin/stdout 用 JSON-RPC 调:`initialize` / `account/read` / `account/rateLimits/read`
   - 优点:不依赖网络,跟 CLI 内部状态一致;缺点:启动慢、要处理超时。

3. **OpenAI Web Dashboard(可选,默认关)**
   - 用隐藏的 `WKWebView` 打开 `https://chatgpt.com/codex/settings/usage`,注入 JS 抓 DOM。
   - 自带"浏览器 Cookie 自动导入":按顺序读 Safari `Cookies.binarycookies` → Chrome 系 `Cookies` (SQLite) → Firefox `cookies.sqlite`,域名 `chatgpt.com`/`openai.com`,Cookie 缓存进 Keychain (`com.steipete.codexbar.cache`)。
   - 拿到的额外信息:code review 剩余额度、用量明细图表、积分历史。

### 2.3 调试通道:CLI `/status` PTY 解析

把 `codex` 跑在 PTY 里、读屏幕渲染出的文本,正则提取 `Credits:`、`5h limit`、`Weekly limit` 行。仅做调试与解析兜底,正常路径不使用。

---

## 三、Claude Code 数据采集

参考:[docs/CLAUDE.md](CLAUDE.md)、[Sources/CodexBarCore/Providers/Claude/](../Sources/CodexBarCore/Providers/Claude/)

### 3.1 三套并行的"主数据"通道

| 通道 | 凭证 | 端点 | 说明 |
|---|---|---|---|
| **OAuth API**(首选) | `~/.claude/.credentials.json`,或 macOS Keychain item `Claude Code-credentials` | `GET https://api.anthropic.com/api/oauth/usage` 头部 `anthropic-beta: oauth-2025-04-20` | 返回 `five_hour` / `seven_day` / `seven_day_sonnet` / `seven_day_opus` / `extra_usage`(月度套餐外消费) |
| **Web API(Cookie)** | 浏览器 `claude.ai` 的 `sessionKey` cookie(`sk-ant-...`) | `GET /api/organizations` → orgId,然后 `/usage`、`/overage_spend_limit`、`/account` | 自动导入 Safari/Chrome/Firefox cookie,缓存进 Keychain |
| **CLI PTY** | 直接跑 `claude` 命令 | 在 PTY 内发 `/usage`、`/status`,正则解析屏幕输出 | 兜底,且能提取 `Account:` / `Org:` |

代码入口:
- OAuth:[ClaudeOAuthUsageFetcher.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift)
- Web:[ClaudeWebAPIFetcher.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift)
- CLI:[ClaudeStatusProbe.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift) + `ClaudeCLISession.swift`

### 3.2 Admin API(组织级账单)

如果用户在 Preferences 配置了 `sk-ant-admin...`,会改走 Anthropic 组织 Admin API:
- `/v1/organizations/cost_report`
- `/v1/organizations/usage_report/messages`

输出:今天 / 7 天 / 30 天的花费 + 消息数 + Token 数,以及 30 天柱状图。

### 3.3 凭证读取的细节(很有参考价值)

`~/.claude/.credentials.json` 在新版 Claude Code 里**可能不存在或为空**,真正的 token 存在 Keychain 里(item 名 `Claude Code-credentials`)。CodexBar 用了一组兜底:
1. 直接读 `.credentials.json`
2. 用 `security find-generic-password` 命令行读取 Keychain(避免触发 GUI 钥匙串弹窗)
3. 多个文件提供策略(`ClaudeOAuthKeychainPromptMode`)控制是否允许出弹窗

这块是踩坑最多的地方,代码也最复杂,自己实现时建议**只支持读 `.credentials.json`**,Keychain 那条以后再补。

---

## 四、本地 Token 计数与费用(今日/本周/本月)

参考:[Sources/CodexBarCore/Vendored/CostUsage/](../Sources/CodexBarCore/Vendored/CostUsage/)、[CostUsageFetcher.swift](../Sources/CodexBarCore/CostUsageFetcher.swift)

### 4.1 数据源:CLI 的会话 JSONL 日志

**Codex**
- `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
- `~/.codex/archived_sessions/*.jsonl`
- 或 `$CODEX_HOME/...`

**Claude**
- `$CLAUDE_CONFIG_DIR/projects/**/*.jsonl`(可逗号分隔多个)
- 兜底:`~/.config/claude/projects/**/*.jsonl`、`~/.claude/projects/**/*.jsonl`

### 4.2 解析方式

每行是一条 JSON,扫描器(`CostUsageScanner`)按 provider 分别处理:

- **Claude**:筛 `type == "assistant"` 的行,读 `message.usage` 里的 `input_tokens` / `output_tokens` / `cache_creation_input_tokens` / `cache_read_input_tokens`;用 `message.id + requestId` 去重(流式 chunk 累计写入)。按 `message.model` 桶到模型,按行内 timestamp 桶到日期。
- **Codex**:读 `event_msg` 中 token_count 事件,用 `turn_context` 锁定模型。
- 两边都额外解析 pi(`~/.pi/agent/sessions/**/*.jsonl`)以兼容统一 CLI。

### 4.3 费用换算

`USD = input * inputCostPerToken + output * outputCostPerToken + cacheRead * cacheReadCostPerToken + cacheCreate * cacheCreationCostPerToken`

价格表:
- **内置** [`CostUsagePricing.swift`](../Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift):内置一套主流模型的硬编码价格(GPT-5、Sonnet 4.x 等),含分档定价(超阈值不同价)与 priority/cache 价。
- **远端覆盖** [`ModelsDevPricing.swift`](../Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift):后台拉 `https://models.dev/api.json`(USD per 1M tokens → 转换成 per token)缓存到磁盘,新模型即使没硬编码也能算价。

### 4.4 缓存与增量扫描

- 缓存目录:`~/Library/Caches/CodexBar/cost-usage/`
  - `codex-v2.json`、`claude-v2.json`、`pi-sessions-v1.json`
- 增量:按文件大小 offset 记录,**只读上次结束位置之后的字节**,避免每次重扫几百 MB 日志。
- 节流:最小刷新间隔 60s。

### 4.5 时间窗口聚合

扫描器把每行落到 `day` × `model` 桶,UI 再按"今日/本周(自然周)/本月/最近 N 天"聚合(默认可配置 1–365 天历史)。这是 CodexBar 能显示"日/周/月 Token + USD"的根本。

---

## 五、采集触发与刷新

- 全局后台计时器:菜单栏 App 周期性调用各 provider 的 `UsageFetcher`。
- 手动:菜单点 Refresh、用 `CodexBarCLI usage` 命令触发。
- 节能:`OpenAI web battery saver`、Claude OAuth Keychain prompt policy 等开关减少后台行为。

---

## 六、给"简化版小项目"的实现建议

如果你只想做一个简单的本地用量小工具(命令行或菜单栏),可以大幅裁剪,推荐分两步:

### Step 1:本地 Token 计数(零依赖,优先做)

只读 `*.jsonl` 就能输出今日/本周/本月 token 与 USD,不需要任何登录:

```text
1. 扫描:
   - Claude: ~/.claude/projects/**/*.jsonl
   - Codex:  ~/.codex/sessions/**/*.jsonl
2. 每行 JSON 解析:
   - Claude: type=="assistant" → message.usage + message.model + timestamp
   - Codex:  event_msg.type=="token_count" → input/output + turn_context.model + timestamp
3. 按 day/model 累加,去重:
   - Claude: message.id + requestId
   - Codex:  以 session_id + turn_id 去重
4. 价格:硬编码主流模型 USD/token,或拉 models.dev/api.json
5. 输出:today / this_week / this_month → tokens & USD
```

参考代码:[CostUsageScanner+Claude.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift)、[CostUsageScanner.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift)。

### Step 2:接配额窗口(选做)

完全靠"读现成凭证 + 调一个 API":

| 厂商 | 读什么 | 调什么 |
|---|---|---|
| Codex | `~/.codex/auth.json` 里的 `access_token` | `GET https://chatgpt.com/backend-api/wham/usage` |
| Claude | `~/.claude/.credentials.json` 里的 `access_token` | `GET https://api.anthropic.com/api/oauth/usage`,加 `anthropic-beta: oauth-2025-04-20` |

返回的 JSON 里直接有 `used_percent` 和 `resets_at`,UI 渲染就完事。

不需要做:浏览器 Cookie 自动导入、WebView 抓 DOM、CLI PTY 解析、Keychain 读取 —— 这些是 CodexBar 为了"鲁棒兜底"做的,简化版可全跳过。

### 风险提示

- **`wham/usage`、`/api/oauth/usage` 都是非公开 API**:Anthropic / OpenAI 可能随时改字段或加 UA / 设备指纹校验,需要做好"接口失败时降级"的预案。
- **token 计数仅覆盖 CLI 路径**:Web 版 ChatGPT / claude.ai 浏览器对话不会写入本地 JSONL,扫描不到。
- **价格**只是估算,与厂商实际计费可能有差(尤其是 cache 命中折扣、Priority 通道)。
- **macOS Keychain**:读 `Claude Code-credentials` 会触发钥匙串授权弹窗,跨平台/无人值守场景麻烦较多,起步阶段建议绕开。

---

## 七、可直接参考的关键源码定位

| 主题 | 文件 |
|---|---|
| Codex OAuth 凭证读取/刷新 | [CodexOAuthCredentials.swift](../Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthCredentials.swift)、`CodexTokenRefresher.swift` |
| Codex `wham/usage` 调用与解析 | [CodexOAuthUsageFetcher.swift](../Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift) |
| Codex CLI RPC | [CodexCLISession.swift](../Sources/CodexBarCore/Providers/Codex/CodexCLISession.swift) |
| Claude OAuth 用量 | [ClaudeOAuthUsageFetcher.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift) |
| Claude Web Cookie 用量 | [ClaudeWebAPIFetcher.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift) |
| Claude CLI PTY | [ClaudeStatusProbe.swift](../Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift) |
| 本地 JSONL 扫描总入口 | [CostUsageFetcher.swift](../Sources/CodexBarCore/CostUsageFetcher.swift)、[CostUsageScanner.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift) |
| 价格表 | [CostUsagePricing.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift)、[ModelsDevPricing.swift](../Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift) |
| 缓存 | [CostUsageCache.swift](../Sources/CodexBarCore/Vendored/CostUsage/CostUsageCache.swift)、[PiSessionCostCache.swift](../Sources/CodexBarCore/PiSessionCostCache.swift) |
