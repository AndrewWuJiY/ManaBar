# cc-switch 用量统计实现分析

> 目的：拆解 cc-switch 是「**怎样得到 Claude Code / Codex / Gemini 的 token 计数、费用、额度刷新时间**」的，给「想自己实现一个更精简版本」的小项目当蓝本。
>
> 项目位置：`~/Code/cc-switch`（Tauri + React + Rust + SQLite）

---

## 0. 一句话先说清楚

cc-switch 把「用量数据」分成**两路完全独立**的来源，前端 UI 把两者拼到一起展示：

| 维度 | 来源 1：本地 JSONL 会话日志 | 来源 2：官方 OAuth 用量 API |
|---|---|---|
| 看到什么 | 每条消息的精确 token、费用（按本地定价表算的） | 5h/7d 窗口的额度使用率、`resets_at` 重置时间 |
| 怎么拿 | 直接扫 CLI 自己写在硬盘上的 `*.jsonl` | 复用 CLI 已经登过录的 OAuth token，直接调官方 API |
| 是否要登录 | 不要 —— 只读 | 不要 —— **直接读 CLI 写好的凭据**（macOS Keychain 或 `~/.<tool>/...`） |
| 是否要代理 | 不要（早期方案有，但当前已是「无代理纯日志」路线） | 不要 |
| 数据落地 | SQLite 表 `proxy_request_logs` | 进程内 `RwLock<HashMap>` 缓存（重启即丢） |

也就是说：「**今日/本周/本月的 token 和费用**」是 cc-switch 自己用本地 JSONL 算出来的；「**额度刷新时间 / 还剩多少 5h 窗口**」是直接 GET 官方 API 拿到的。两个数据其实**对不上一一对应**，是分开汇报的。

---

## 1. 总体架构

```
┌────────────────────────────────────────────────────────────────────┐
│  React 前端                                                         │
│    UsageDashboard            SubscriptionQuotaFooter                │
│        ↓ invoke              ↓ invoke                               │
└────────────────────────────────────────────────────────────────────┘
        ↓ tauri::command                ↓ tauri::command
┌────────────────────────────────────┬──────────────────────────────┐
│ commands/usage.rs                  │ commands/subscription.rs     │
│  - sync_session_usage              │  - get_subscription_quota    │
│  - get_usage_summary               │                              │
│  - get_usage_trends                │                              │
│  - get_request_logs                │                              │
└────────────────────────────────────┴──────────────────────────────┘
        ↓                                  ↓
┌────────────────────────────────────┬──────────────────────────────┐
│ services/session_usage*.rs         │ services/subscription.rs     │
│  扫 JSONL → 解析 → 算钱 → 入库     │  读凭据 → 调 API → 缓存      │
└────────────────────────────────────┴──────────────────────────────┘
        ↓                                  ↓
┌────────────────────────────────────┬──────────────────────────────┐
│ SQLite (~/.cc-switch/...)          │ RwLock<HashMap> 进程内缓存   │
│  - proxy_request_logs              │  UsageCache                  │
│  - usage_daily_rollups             │                              │
│  - model_pricing                   │                              │
│  - session_log_sync                │                              │
└────────────────────────────────────┴──────────────────────────────┘
        ↑                                  ↑
┌────────────────────────────────────┬──────────────────────────────┐
│ ~/.claude/projects/**/*.jsonl      │ macOS Keychain               │
│ ~/.codex/sessions/YYYY/MM/DD/*.jsonl│  "Claude Code-credentials"   │
│ ~/.codex/archived_sessions/*.jsonl │  "Codex Auth"                │
│ (Gemini 没有本地 JSONL)            │  "gemini-cli-oauth"          │
│                                    │ 或文件：                     │
│                                    │  ~/.claude/.credentials.json │
│                                    │  ~/.codex/auth.json          │
│                                    │  ~/.gemini/oauth_creds.json  │
└────────────────────────────────────┴──────────────────────────────┘
```

---

## 2. 路径一：从本地 JSONL 得到 token + 费用

这是「**今日/本周/本月的精确用量**」的数据来源。

### 2.1 数据从哪来

CLI 工具自己在硬盘上写会话日志，cc-switch 只是**读取**它们：

| 工具 | 路径 | 备注 |
|---|---|---|
| Claude Code | `~/.claude/projects/<项目目录>/*.jsonl` 以及 `<项目>/<SESSION_ID>/subagents/*.jsonl` | 主会话 + 子 agent |
| Codex | `~/.codex/sessions/YYYY/MM/DD/*.jsonl` 和 `~/.codex/archived_sessions/*.jsonl` | 按日期分区 |
| Gemini | 类似的 session 文件 | 见 `session_usage_gemini.rs` |

> **关键**：cc-switch 完全没碰过用户的 API key / OAuth；它只是个会读 `.jsonl` 的离线工具。

### 2.2 怎么解析 —— Claude

`src-tauri/src/services/session_usage.rs:60`：`sync_claude_session_logs(db)`

每个 JSONL 文件按行流式读，**只关心 `type=assistant` 的行**：

```json
{
  "type": "assistant",
  "message": {
    "id": "msg_xxx",
    "model": "claude-opus-4-7",
    "usage": {
      "input_tokens": 3,
      "output_tokens": 1349,
      "cache_read_input_tokens": 5000,
      "cache_creation_input_tokens": 10000
    },
    "stop_reason": "end_turn"
  },
  "timestamp": "2026-04-05T12:00:00Z",
  "sessionId": "session-abc"
}
```

要点：
1. **按 `message.id` 去重**：一次回答会有多条中间增量行；优先保留有 `stop_reason` 的那条（说明流式输出已结束），否则取 `output_tokens` 最大的。
2. **`output_tokens == 0` 的整条丢弃**（无意义）。
3. `input_tokens` 已经是「**fresh input**」，不包含缓存命中。`cache_read` / `cache_creation` 单独统计。
4. **增量同步**：维护一张 `session_log_sync` 表，键是文件路径，值是 `(last_modified_nanos, last_line_offset)`。下次只解析 mtime 变了之后、新增行偏移之后的内容。

```rust
// session_usage.rs:328 简化
SELECT last_modified, last_line_offset
  FROM session_log_sync
 WHERE file_path = ?;
```

### 2.3 怎么解析 —— Codex

`src-tauri/src/services/session_usage_codex.rs:144`：`sync_codex_usage(db)`

Codex 的 JSONL 格式不同，关心三种事件：

| `type` 字段 | 用来 |
|---|---|
| `session_meta` | 拿 `session_id` |
| `turn_context` | 拿当前 `model`（要做归一化，去掉 `openai/` 前缀和 `-YYYY-MM-DD` 日期后缀） |
| `event_msg` (且 `payload.type=token_count`) | 拿累计 token 用量 |

**关键技巧**：Codex 的 `total_token_usage` 是**累计值**，所以要**计算 delta**：

```rust
// session_usage_codex.rs:107
delta.input = current.input.saturating_sub(prev.input);
```

每次 `event_msg.token_count` 触发一次「一次 API 调用」的记录。`request_id` 是 `codex_session:<session_id>:<event_index>`，保证幂等。

> Gemini 的同步逻辑在 `session_usage_gemini.rs`，思路类似，这里不展开。

### 2.4 费用怎么算

`src-tauri/src/proxy/usage/calculator.rs:71`：

```text
input_cost  = billable_input * input_per_million / 1_000_000
output_cost = output_tokens  * output_per_million / 1_000_000
cache_read_cost      = cache_read_tokens * cache_read_per_million / 1_000_000
cache_creation_cost  = cache_creation_tokens * cache_creation_per_million / 1_000_000
total = (sum) × cost_multiplier
```

**单位语义差异**（这是个 trick）：

- **Claude 系**：`input_tokens` 已经扣过缓存命中，直接用 `billable = input_tokens`。
- **Codex / Gemini 系（OpenAI Responses 风格）**：`input_tokens` 包含缓存命中，需 `billable = input_tokens - cache_read_tokens`。

代码用一个布尔标志 `input_includes_cache_read` 区分；通过 `CostCalculator::calculate_for_app(app_type, …)` 入口选择。

**定价表**：内置在 SQLite 的 `model_pricing` 表里，初始化时由 `seed_model_pricing()` 写入（见 `database/schema.rs:1206`），并允许用户在 UI 里改。所有金额都用 `rust_decimal::Decimal`，**不用 f64**，避免精度问题。

### 2.5 落地到哪里

所有 token + 费用记录都进 `proxy_request_logs` 表。SQL 字段（schema.rs:184）：

```sql
CREATE TABLE proxy_request_logs (
  request_id TEXT PRIMARY KEY,         -- 用 "session:<msg_id>" 或 "codex_session:<sid>:<idx>" 拼成
  provider_id TEXT,                    -- "_session" / "_codex_session" 标记数据来源
  app_type TEXT,                       -- "claude" | "codex" | "gemini"
  model TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_tokens INTEGER,
  cache_creation_tokens INTEGER,
  input_cost_usd TEXT,                 -- Decimal 序列化为字符串
  output_cost_usd TEXT,
  cache_read_cost_usd TEXT,
  cache_creation_cost_usd TEXT,
  total_cost_usd TEXT,
  status_code INTEGER,                 -- 会话日志固定 200
  session_id TEXT,
  created_at INTEGER,                  -- Unix 时间戳（秒）
  data_source TEXT                     -- "proxy" | "session_log" | "codex_session"
);
```

还有 `usage_daily_rollups`（日聚合表）—— 旧数据被滚到这里后，详细日志可以被清掉，查询时把两边 `UNION ALL`。

### 2.6 聚合查询（今日 / 本周 / 本月）

`services/usage_stats.rs:435` `get_usage_summary(start_date, end_date, app_type)`：

- 前端只要给一个 `start_date` / `end_date` 的 Unix 时间戳范围；
- Rust 这边对 `proxy_request_logs` 用 `WHERE created_at BETWEEN ? AND ?` 做聚合，加上 `usage_daily_rollups` 已经滚到日的部分；
- 返回 `total_requests / total_cost / total_input_tokens / output / cache_read / cache_creation / success_rate / cache_hit_rate`。

```rust
real_total = input + output + cache_creation + cache_read
cache_hit_rate = cache_read / (input + cache_creation + cache_read)
```

「今日/本周/本月」就是前端三个 chip，分别传不同 `start_date`：今天 0 点、本周一 0 点、本月 1 号 0 点。**Rust 后端本身没有"周/月"的概念**，是前端自己决定时间窗。

### 2.7 触发同步的时机

前端有定时器 30s 拉一次（`UsageFooter.tsx:66` 等），调 `sync_session_usage` 命令；Rust 这边的实现：

```rust
// commands/usage.rs:247
sync_session_usage = sync_claude_session_logs + sync_codex_usage + sync_gemini_usage
```

每次同步：扫文件 → 比较 mtime → 增量解析 → 入库。一次 sync 完返回 `imported / skipped / files_scanned`，并触发前端重新查 summary。

---

## 3. 路径二：从官方 OAuth API 拿额度刷新时间

这是「**5h / 7d 窗口的使用率、resets_at**」的数据来源。

### 3.1 凭据怎么找

文件：`src-tauri/src/services/subscription.rs`

cc-switch **完全不做登录**。它假设你已经在终端里 `claude login` / `codex login` / `gemini login` 过了，凭据本来就在系统里，它只是去**读**。

| 工具 | 优先读 macOS Keychain | 回退到文件 |
|---|---|---|
| Claude | `security find-generic-password -s "Claude Code-credentials"` | `~/.claude/.credentials.json` |
| Codex | `security find-generic-password -s "Codex Auth"` | `~/.codex/auth.json` |
| Gemini | `security find-generic-password -s "gemini-cli-oauth" -a "main-account"` | `~/.gemini/oauth_creds.json` |

JSON 结构（精简）：

```jsonc
// Claude
{ "claudeAiOauth": { "accessToken": "...", "expiresAt": 1730000000 } }

// Codex  (仅 auth_mode == "chatgpt" 即 OAuth 模式有用量；API key 模式查不到)
{ "auth_mode": "chatgpt",
  "tokens": { "access_token": "...", "account_id": "..." },
  "last_refresh": "2026-05-20T08:00:00Z" }

// Gemini  (Keychain 内是嵌套的 keytar 格式，文件是扁平的)
{ "access_token": "...", "refresh_token": "...", "expiry_date": 1730000000000 }
```

过期判定：
- Claude：解析 `expiresAt`（兼容秒/毫秒/ISO 字符串），与当前时间比较。
- Codex：CLI 在 >8 天会自动刷新，所以 `now - last_refresh > 8d` 视为可能过期（仍尝试调用）。
- Gemini：Google access_token 只有 ~1h。**cc-switch 自己用 `refresh_token` 调 `https://oauth2.googleapis.com/token` 刷新**（client_id/secret 是 Gemini CLI 源码里写死的公开值）。

### 3.2 调哪个 API

| 工具 | Endpoint | Method | 关键 header |
|---|---|---|---|
| Claude | `https://api.anthropic.com/api/oauth/usage` | GET | `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20` |
| Codex / ChatGPT | `https://chatgpt.com/backend-api/wham/usage` | GET | `Authorization: Bearer <token>`, `User-Agent: codex-cli`, `ChatGPT-Account-Id: <id>` |
| Gemini | 两步：`https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` → `:retrieveUserQuota` | POST | `Authorization: Bearer <token>` |

### 3.3 返回长什么样

**Claude** (`subscription.rs:317`)：

```json
{
  "five_hour":       { "utilization": 23.5, "resets_at": "2026-05-22T15:00:00Z" },
  "seven_day":       { "utilization": 45.2, "resets_at": "2026-05-27T00:00:00Z" },
  "seven_day_opus":  { ... },
  "seven_day_sonnet":{ ... },
  "extra_usage": { "is_enabled": true, "monthly_limit": 100, "used_credits": 23.5, "currency": "USD" }
}
```

cc-switch 把它归一化成统一的 `QuotaTier { name, utilization, resets_at }`。「**额度刷新时间**」就是 `resets_at` 字段。

**Codex**：

```json
{
  "rate_limit": {
    "primary_window":   { "used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1730000000 },
    "secondary_window": { "used_percent": 60, "limit_window_seconds": 604800, "reset_at": 1730500000 }
  }
}
```

`limit_window_seconds`：`18000` → `five_hour`，`604800` → `seven_day`（命名复用 Claude 的，便于 i18n 共用）。`reset_at` 是 Unix 秒，再 `unix_ts_to_iso()` 转成 ISO 字符串。

**Gemini**：先 POST `loadCodeAssist` 拿 `cloudaicompanionProject` 项目 ID；再 POST `retrieveUserQuota`，拿到分桶的 `buckets[] { remainingFraction, resetTime, modelId }`。然后按模型分类（pro / flash / flash_lite），每类取**最小** `remainingFraction`（=最紧张的那个）作为该类的剩余额度，`utilization = (1 - remaining) * 100`。

### 3.4 落地

不写 SQLite，只塞进进程内 `UsageCache { subscription: RwLock<HashMap<AppType, SubscriptionQuota>> }`（`services/usage_cache.rs`）。每次前端拉就实时调一次 API，结果顺手写入缓存供托盘菜单复用。**重启就没了，没问题，下次调用自然会重填**。

---

## 4. 国产 Token Plan（Kimi / GLM / MiniMax）

`services/coding_plan.rs`：根据 provider 的 `base_url` 识别厂商，然后调各家自己的 `/usages` 端点，把响应套到同一个 `SubscriptionQuota` 结构里返回。这里凭据是用户在 cc-switch 里配的 API key（不是从 CLI 偷凭据，因为这些工具没有"官方 OAuth"）。

---

## 5. 「最小可复制版本」该怎么搭

如果你要做一个**最简**的小项目，以下是建议的取舍：

### 5.1 只看 token + 费用 → 一个脚本就够

伪 Python 版本（解析 Claude）：

```python
import json, glob, os, sqlite3, datetime as dt
from pathlib import Path

PRICING = {
    "claude-opus-4-7": dict(in_=15, out=75, cache_r=1.5, cache_w=18.75),
    "claude-sonnet-4-6-20260217": dict(in_=3, out=15, cache_r=0.3, cache_w=3.75),
    # ...
}

def cost(model, usage):
    p = PRICING.get(model)
    if not p: return 0
    M = 1_000_000
    return (usage["input_tokens"] * p["in_"]
          + usage["output_tokens"] * p["out"]
          + usage.get("cache_read_input_tokens", 0) * p["cache_r"]
          + usage.get("cache_creation_input_tokens", 0) * p["cache_w"]
          ) / M

def scan_claude():
    seen = {}  # message_id -> row（去重，留 stop_reason 那条）
    for f in glob.glob(str(Path.home() / ".claude/projects/**/*.jsonl"), recursive=True):
        for line in open(f, encoding="utf-8"):
            try: r = json.loads(line)
            except: continue
            if r.get("type") != "assistant": continue
            m = r["message"]; u = m.get("usage")
            if not u or u.get("output_tokens", 0) == 0: continue
            cur = {
                "id": m["id"], "model": m["model"],
                "ts": r.get("timestamp"),
                **u, "stop_reason": m.get("stop_reason"),
                "cost": cost(m["model"], u)
            }
            old = seen.get(cur["id"])
            if not old or (cur["stop_reason"] and not old["stop_reason"]):
                seen[cur["id"]] = cur
    return [v for v in seen.values() if v["stop_reason"]]

rows = scan_claude()
today = dt.date.today().isoformat()
today_rows = [r for r in rows if r["ts"] and r["ts"].startswith(today)]
print("Today input:", sum(r["input_tokens"] for r in today_rows))
print("Today cost:", sum(r["cost"] for r in today_rows))
```

百来行就能跑：扫 JSONL → 按 `message.id` 去重 → 算钱 → 按时间筛今日/本周/本月。

### 5.2 想要"额度刷新时间" → 复用 OAuth 凭据

也是一个脚本：

```python
import json, subprocess, requests
from pathlib import Path

def read_claude_token():
    # macOS Keychain
    try:
        out = subprocess.check_output(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ).decode().strip()
    except subprocess.CalledProcessError:
        out = (Path.home() / ".claude/.credentials.json").read_text()
    return json.loads(out)["claudeAiOauth"]["accessToken"]

def claude_quota():
    r = requests.get(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": f"Bearer {read_claude_token()}",
            "anthropic-beta": "oauth-2025-04-20",
        }, timeout=10).json()
    for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
        w = r.get(k)
        if w: print(k, w["utilization"], "%, resets at", w["resets_at"])

claude_quota()
```

Codex 版只是把 URL 换成 `https://chatgpt.com/backend-api/wham/usage`，加 `User-Agent: codex-cli`，token 从 `~/.codex/auth.json` 的 `tokens.access_token` 拿。

### 5.3 推荐的最小架构

```
小项目/
  data.db                  # SQLite
  pricing.json             # 模型定价表（从 cc-switch 的 seed 抄一份）
  scan.py                  # 扫 ~/.claude /  ~/.codex 入库（增量）
  quota.py                 # 调官方 API 拿额度
  serve.py                 # 一个 Flask/FastAPI，吐 today/week/month 汇总
  index.html               # 一个简单页面，定时 poll
```

关键设计点（从 cc-switch 抄的）：

1. **增量同步表**：`(file_path, last_modified, last_line_offset)` → 别每次全量重扫。
2. **按 message.id / event_index 主键去重**：JSONL 同一条消息有多个增量行，必须挑"已完成"的那个。
3. **Codex 用累计值要算 delta**，Claude 直接是单次量。
4. **fresh input 语义差异**：Claude 的 `input_tokens` 已扣缓存命中；Codex 没扣。算钱时要分流派。
5. **金额用 Decimal**，别用 float。
6. **额度 API 数据放内存就行**，每次拉一次 fresh 的，TTL 30s。

---

## 6. 关键文件索引

| 关注点 | 文件 |
|---|---|
| Claude JSONL 解析 | [src-tauri/src/services/session_usage.rs](src-tauri/src/services/session_usage.rs) |
| Codex JSONL 解析 | [src-tauri/src/services/session_usage_codex.rs](src-tauri/src/services/session_usage_codex.rs) |
| Gemini 解析 | [src-tauri/src/services/session_usage_gemini.rs](src-tauri/src/services/session_usage_gemini.rs) |
| 费用计算（含 Claude vs Codex 语义差异）| [src-tauri/src/proxy/usage/calculator.rs](src-tauri/src/proxy/usage/calculator.rs) |
| 聚合查询 SQL | [src-tauri/src/services/usage_stats.rs](src-tauri/src/services/usage_stats.rs) |
| OAuth 凭据读取 + 额度 API 调用 | [src-tauri/src/services/subscription.rs](src-tauri/src/services/subscription.rs) |
| Token Plan 国产厂商 | [src-tauri/src/services/coding_plan.rs](src-tauri/src/services/coding_plan.rs) |
| 内存缓存 | [src-tauri/src/services/usage_cache.rs](src-tauri/src/services/usage_cache.rs) |
| DB schema | [src-tauri/src/database/schema.rs](src-tauri/src/database/schema.rs) |
| 模型定价 seed | [src-tauri/src/database/schema.rs:1206](src-tauri/src/database/schema.rs) |
| Tauri command 入口 | [src-tauri/src/commands/usage.rs](src-tauri/src/commands/usage.rs)、[src-tauri/src/commands/subscription.rs](src-tauri/src/commands/subscription.rs) |
| 前端 API 封装 | [src/lib/api/usage.ts](src/lib/api/usage.ts)、[src/lib/api/subscription.ts](src/lib/api/subscription.ts) |

---

## 7. 几个容易踩坑的点

1. **Claude 的 input_tokens 不含缓存**，但 Codex / Gemini 的 input_tokens **含**缓存命中。如果直接套同一公式算钱，Codex 会双倍计费 cache_read 那部分。
2. **JSONL 同一条 message.id 会出现多行**（流式中间态 + 最终态），只统计 `stop_reason != null` 的那条。
3. **Codex 的 `total_token_usage` 是累计**，必须做 delta；同时要处理 task 边界出现的 delta=0 事件。
4. **Codex 模型名要归一化**：`openai/gpt-5.4-2026-03-05` 要剥成 `gpt-5.4` 才能匹定价表。
5. **Gemini access_token 只有 ~1h**，必须自己用 refresh_token + Google 公开的 client_id/secret 刷新。
6. **macOS 上凭据先在 Keychain 找，找不到才回退文件**（CLI 新版本越来越倾向于只存 Keychain）。
7. **"今日/本周/本月"是前端定义的时间窗**，后端是个无状态的范围查询；时区取本地（chrono `Local`）。
8. **Codex CLI 必须是 `auth_mode = "chatgpt"`（OAuth 模式）**才能查用量。API key 模式没有官方用量接口。

---

完。如果要再精简一档，只做 Claude，就只看 `session_usage.rs` + `calculator.rs` + `subscription.rs` 三个文件加起来 ~1800 行的 Rust，对应到 Python 大约 300 行能复制 80% 的功能。
