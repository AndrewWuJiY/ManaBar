# cockpit-tools 用量/配额获取机制分析

> 说明：本项目（**Cockpit Tools**）不直接支持「Claude Code」官方账号的用量查询。它支持的 AI IDE 是
> Antigravity / **Codex** / **GitHub Copilot** / Windsurf / Kiro / Cursor / Gemini CLI / CodeBuddy / Qoder / Trae / Zed。
> 由于你最关心的是「Codex 和 Claude Code 的用量、刷新时间、token 计数与费用是怎么拿到的」，
> 本文以 **Codex**（最完整、最接近 ChatGPT/Claude 这类「订阅制 + OAuth + 后端 usage 接口」的形态）为主线讲解，
> 同时简要带过 **GitHub Copilot** 的另一种形态。Claude Code 的官方 CLI 也是「本地 token + 远端 usage」结构，
> 实现思路完全可以照搬本文。

---

## 1. 总体架构（先有个大图）

技术栈：**Tauri 2（Rust 后端 + React 前端）+ macOS 局部 Swift 原生模块**。
跟「读取/请求用量」相关的代码都在 Rust 端的 `crates/cockpit-core` 里，前端只是把它们用 Tauri command 调出来再展示。

涉及的核心模块（路径）：

| 模块 | 作用 |
|---|---|
| `crates/cockpit-core/src/modules/codex_oauth.rs` | OAuth 授权登录 / token 刷新 |
| `crates/cockpit-core/src/modules/codex_account.rs` | 本地账号存储、从 `~/.codex/auth.json` 导入 |
| `crates/cockpit-core/src/modules/codex_quota.rs` | 调用 ChatGPT 后端 `wham/usage` 拉取配额 |
| `crates/cockpit-core/src/models/codex.rs` | `CodexAccount` / `CodexTokens` / `CodexQuota` 等数据结构 |
| `crates/cockpit-core/src/modules/github_copilot_account.rs` | GitHub Copilot 配额解析（另一种形态） |
| `crates/cockpit-core/src/modules/github_copilot_oauth.rs` | Copilot token 端点 |

数据流：

```
 ┌──────────────────────────┐
 │ ① 取得 token             │
 │   (a) OAuth 走完一遍     │
 │   (b) 读 ~/.codex/auth.json (用户已经在 Codex CLI 登录过)
 └──────────────┬───────────┘
                │
                ▼
 ┌──────────────────────────┐
 │ ② 本地落盘 (CodexAccount) │
 │   data_dir/codex/        │
 │     accounts/<id>.json   │
 │     index.json           │
 └──────────────┬───────────┘
                │
                ▼
 ┌──────────────────────────┐
 │ ③ 每次查询配额前         │
 │   - 解 JWT 看 exp        │
 │   - 过期就 refresh_token │
 └──────────────┬───────────┘
                │
                ▼
 ┌──────────────────────────────────────────────┐
 │ ④ GET https://chatgpt.com/backend-api/wham/usage  │
 │   Headers:                                   │
 │     Authorization: Bearer <access_token>     │
 │     ChatGPT-Account-Id: <从 JWT 解出>        │
 │   返回: rate_limit.primary_window (5h)       │
 │         rate_limit.secondary_window (周)     │
 │         plan_type                            │
 └──────────────┬───────────────────────────────┘
                │
                ▼
 ┌──────────────────────────┐
 │ ⑤ 落盘 + 通知前端刷新 UI │
 └──────────────────────────┘
```

---

## 2. 关键问题逐条回答

### 2.1 「是直接读本地账号，还是需要用户重新登录/导入？」

**两种都支持，用户自己选**（见 `codex_account.rs`）：

1. **从本地直接导入**（最常用、零成本）
   `import_from_local()` —— 读 `~/.codex/auth.json`，那是 Codex CLI 官方自己写的文件，里面有 `id_token / access_token / refresh_token`。
   ```rust
   // codex_account.rs:2607
   pub fn import_from_local() -> Result<CodexAccount, String> {
       let auth_path = get_auth_json_path();          // ~/.codex/auth.json
       let content   = fs::read_to_string(&auth_path)?;
       let auth_file: CodexAuthFile = serde_json::from_str(&content)?;
       ...
       if let Some(tokens) = auth_file.tokens {
           return upsert_account_from_auth_tokens(tokens);
       }
       ...
   }
   ```
   `auth.json` 的结构 (`models/codex.rs:CodexAuthFile`)：
   ```json
   {
     "OPENAI_API_KEY": null,
     "tokens": {
       "id_token": "eyJ...",
       "access_token": "eyJ...",
       "refresh_token": "...",
       "account_id": "acc_..."
     },
     "last_refresh": "..."
   }
   ```
   `CODEX_HOME` 环境变量可以覆盖路径（`resolve_codex_home_from_env`）。

2. **在 App 里走一遍 OAuth**（用户没装 Codex CLI 时用）
   `codex_oauth.rs:start_oauth_login()` —— 启动一个本机 HTTP listener 接 `http://localhost:1455/auth/callback`，用浏览器打开 OpenAI 授权页（PKCE / S256），用户授权回来后用 `code + code_verifier` 去 `https://auth.openai.com/oauth/token` 换 token。
   常量：
   ```rust
   const CLIENT_ID: &str       = "app_EMoamEEZ73f0CkXaXp7hrann"; // Codex CLI 公开 client id
   const AUTH_ENDPOINT: &str   = "https://auth.openai.com/oauth/authorize";
   const TOKEN_ENDPOINT: &str  = "https://auth.openai.com/oauth/token";
   const SCOPES: &str          = "openid profile email offline_access";
   const ORIGINATOR: &str      = "codex_vscode";
   const OAUTH_CALLBACK_PORT: u16 = 1455;
   ```
   注意 query 里还带了两个 Codex 专属参数：`id_token_add_organizations=true&codex_cli_simplified_flow=true`。

> Claude Code 的官方 CLI 同样会把 token 写在用户目录（一般在 `~/.config/claude/` 或 `~/.claude/`），结构与上面非常相似，可以照抄「读本地文件 + 兜底 OAuth」的双通道思路。

### 2.2 「怎么获取用量、配额、刷新时间？」

只调一个接口，全靠 ChatGPT 后端返回（`modules/codex_quota.rs`）：

```rust
const USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";
```

调用方式（`fetch_quota`）：

```rust
let mut headers = HeaderMap::new();
headers.insert(AUTHORIZATION, format!("Bearer {}", access_token));
headers.insert(ACCEPT, "application/json");
// 关键: 必须带 ChatGPT-Account-Id，从 access_token 的 JWT payload 里解出
if let Some(acc_id) = account_id_or_extract_from_jwt(&access_token) {
    headers.insert("ChatGPT-Account-Id", acc_id);
}
let resp = client.get(USAGE_URL).headers(headers).send().await?;
```

响应（`UsageResponse`）：

```jsonc
{
  "plan_type": "plus",                // Basic / Plus / Team / Pro …
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window":   { "used_percent": 32, "limit_window_seconds": 18000, "reset_after_seconds": 7200, "reset_at": 1736901234 },
    "secondary_window": { "used_percent": 12, "limit_window_seconds": 604800, ... }
  },
  "code_review_rate_limit": { ... }
}
```

代码里把它归一化为 `CodexQuota`（`models/codex.rs`）：

| 字段 | 含义 | 计算 |
|---|---|---|
| `hourly_percentage` | 5 小时窗口剩余比例 | `100 - primary.used_percent` |
| `hourly_reset_time` | 5 小时窗口重置 Unix 秒 | `primary.reset_at` 或 `now + reset_after_seconds` |
| `hourly_window_minutes` | 主窗口长度（分钟） | `ceil(limit_window_seconds / 60)` |
| `weekly_percentage` / `weekly_reset_time` / `weekly_window_minutes` | 同上，对应 `secondary_window` | |
| `raw_data` | 原始响应 JSON | 备用 |

⚠️ **注意：Codex 这个端点只返回「百分比 + 重置时间」，不直接给「今日/本周/本月 token 数」**，也不给费用。
项目里所有「剩余多少」「下次什么时候重置」都是从这两个 window 算出来的；并没有日/月维度的统计。
真实的 token / 费用统计 OpenAI 只在 web 管理后台展示，没有公开 API。

> 如果你想要的是「**今日 / 本周 / 本月 token 计数 + 费用**」：
> - **Claude Code** 思路 1：解析 `~/.claude/projects/**/*.jsonl` 会话日志，里面每条 message 都带 `usage.input_tokens / output_tokens / cache_*_tokens`，自己按时间分桶累计。社区已有 `ccusage` 这类项目就是这么做的。
> - **Claude Code** 思路 2：调 Anthropic 的 Admin API（`/v1/organizations/usage_report/messages`），但需要 Admin Key。
> - **Codex** 目前没有公开 usage API，能拿到的就是上面这两个窗口百分比。

### 2.3 「额度刷新时间」是谁给的？

完全是接口里直接给的（`primary_window.reset_at` 或 `reset_after_seconds`），项目只是搬运 + 兜底换算：

```rust
fn normalize_reset_time(window: &WindowInfo) -> Option<i64> {
    if let Some(reset_at) = window.reset_at { return Some(reset_at); }
    let secs = window.reset_after_seconds?;
    if secs < 0 { return None; }
    Some(chrono::Utc::now().timestamp() + secs)
}
```

### 2.4 token 是怎么自动续期的？

`codex_quota.rs::refresh_account_quota_once` 在每次拉配额前会主动验签 + 续期：

```rust
if codex_oauth::is_token_expired(&account.tokens.access_token) {
    refresh_account_tokens(&mut account, "Token 已过期").await?;
    // ...再从 id_token 里解一遍最新 plan_type
}
```

`is_token_expired` 自己把 JWT 拆三段、base64 解 payload、看 `exp`，并留 **5 分钟（`TOKEN_REFRESH_SKEW_SECONDS = 300`）安全 skew**：

```rust
exp < now + TOKEN_REFRESH_SKEW_SECONDS
```

续期 (`refresh_access_token_with_fallback`)：

```
POST https://auth.openai.com/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token=...
&client_id=app_EMoamEEZ73f0CkXaXp7hrann
```

响应里如果没有新 `id_token` 就复用旧的；没有新 `refresh_token` 就复用旧的。
续期成功后会把新 token 落盘并 `token_generation += 1`。

### 2.5 多账号并发刷新

```rust
const MAX_CONCURRENT: usize = 5;
let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT));
// futures::join_all 起一批任务，每个抢一个 permit
```

—— 用 `tokio::Semaphore` 控制最多 5 个并发，避免对官方接口太激进。

### 2.6 用户信息（邮箱 / plan）从哪里来？

不需要额外调接口，全部从 OAuth 返回的 `id_token` 里解 JWT：

```rust
// models/codex.rs
pub struct CodexAuthData {
    pub chatgpt_user_id: Option<String>,
    pub chatgpt_plan_type: Option<String>,   // basic / plus / team ...
    pub account_id: Option<String>,
    pub organization_id: Option<String>,
}
// 字段路径: payload["https://api.openai.com/auth"]
```

`extract_user_info()` 就负责把 email / plan / account_id / org_id 一次性挖出来。
之后 `wham/usage` 返回的 `plan_type` 还会再覆盖一次（用户升降级也能感知），见 `sync_plan_type_from_token()`。

### 2.7 GitHub Copilot 形态（另一种参考）

Copilot 不走 OpenAI 那种 5 小时窗口，它的「配额」编码在 **Copilot Token 字符串本身** 里（用 `;` 分隔的 KV）和一个 `copilot_limited_user_quotas` / `copilot_quota_snapshots` JSON 里。

端点：

```rust
const GITHUB_COPILOT_TOKEN_ENDPOINT: &str = "https://api.github.com/copilot_internal/v2/token";
const GITHUB_COPILOT_USER_INFO_ENDPOINT: &str = "https://api.github.com/copilot_internal/user";
```

解析（`github_copilot_account.rs`）：

```rust
fn parse_token_map(token: &str) -> HashMap<String, String> {
    // 把 "tid=..;exp=..;cq=8000;tq=300;..." 拆成 KV
}
// 推算剩余比例：
//   Inline Suggestions  = limited.completions / token.cq
//   Chat Messages       = limited.chat        / token.tq
//   Premium Interactions= snapshots.premium_interactions.percent_remaining
```

—— 这套同样属于「拿后端给的剩余/总量直接算百分比」，不存在「日/月 token 累计」。

---

## 3. 数据存哪儿、什么时候刷新

* **存储路径**：`get_data_dir()/codex/accounts/<id>.json` + `index.json`。Tauri 的 `app_data_dir()`，macOS 上一般是 `~/Library/Application Support/<bundleId>/`。
* **写盘方式**：`modules::atomic_write::*` —— 先写 `.tmp` 再 `rename`，避免半文件。
* **触发时机**：
  - 用户在 UI 点「刷新配额」按钮 → 走 `refresh_account_quota`；
  - 「全部刷新」/ 仪表盘进入 → `refresh_all_quotas`；
  - 切号、唤醒任务 (`codex_wakeup*`) 完成后也会顺手刷一次。
* **缓存层**：`modules/quota_cache.rs` 只做轻量内存缓存（避免短时间内重复请求），并不持久化用量历史。

---

## 4. 复刻最小版：你要做的事

如果你想做一个**更简单的小工具**（"账号 + 配额仪表盘"），按这个顺序最快：

1. **挑技术栈**
   - 想要跨平台 + 漂亮 UI：Tauri 2（Rust + 任意前端），完全照搬本项目；
   - 想要更轻：Python + textual / Go + Bubble Tea 写 TUI；
   - 想要纯 macOS：SwiftUI 也行，本质就是发 HTTPS。
2. **拿 token**：先做「读本地文件」一条通路就够用。Codex 看 `~/.codex/auth.json`，Claude Code 看 `~/.claude/.credentials.json`（或 keychain 项 `Claude Code-credentials`，依版本而定）。
3. **预先检测过期 + 自动 refresh**：JWT 解 `exp` 字段，留 5 分钟 skew。
4. **打 usage 接口**：
   - Codex → `GET https://chatgpt.com/backend-api/wham/usage`，带 `ChatGPT-Account-Id`。
   - Claude Code → 解析本地 `~/.claude/projects/**/*.jsonl` 自己统计；或 Admin API。
5. **UI 展示三件套**：百分比进度条、`reset_at` 倒计时、`plan_type` 标签。已经够用了。
6. **本地落盘**：单文件 JSON 即可，写盘时用「先写 tmp 再 rename」防半文件。

---

## 5. 一句话总结

> Cockpit Tools 之所以能拿到 Codex 配额，是因为它**复用 Codex CLI 在本地登录后留下的 OAuth token**，
> 然后**自带 token 续期**，**直接打 ChatGPT 后端没公开的 `wham/usage` 接口**，
> 把返回的 `primary_window`（5h）/ `secondary_window`（周）两个百分比 + `reset_at` 渲染成 UI。
> 它**不会跟踪今日/本周/本月的 token 数和费用**——因为官方根本没给这种 API。
> 想做这种统计，就得走 Claude Code 那条「解析本地 JSONL 会话日志」的路。
