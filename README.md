# cc-bar

> macOS 菜单栏小工具,把 Codex 和 Claude Code 的额度、刷新状态、本地用量统计一眼看清。
> A macOS menu bar utility that shows your Codex and Claude Code quota, refresh status, and local usage at a glance.

![menu bar](docs/screenshots/menubar.png)
![popover](docs/screenshots/popover.png)
![stats](docs/screenshots/stats.png)

> 截图会在 0.1 正式发布前补齐。
> Screenshots will be filled in before the 0.1 release.

## 功能 · Features

- 自动识别本机 Codex (`~/.codex/auth.json`) 与 Claude Code (`~/.claude/.credentials.json` 或 macOS Keychain) 登录账号
- 菜单栏图标 + 5 小时 / 周窗口剩余百分比,服务可独立显隐
- Popover 展示双服务额度、倒计时、今日 cost(基于本地 JSONL 增量扫描)
- 主窗口统计 tab:今天 / 昨天 / 本周 / 本月 / 本年 / 7 天 / 30 天 / 全部 / 自定义,按模型拆分 token 与花费
- 可选桌面悬浮窗,可拖、屏幕边缘 20pt 自动吸附、位置记忆
- 全局快捷键:⌘1 打开统计 · ⌘, 打开设置 · ⌘R 立即刷新 · ⌘Q 退出
- 状态指示三态:live / stale / offline 圆点
- 网络失败时保留上次成功的快照,不清空 UI

## 安装 · Install

1. 从 [Releases](https://github.com/nanvon/cc-bar/releases) 下载最新 `CCBar.app.zip`,解压后把 `CCBar.app` 拖到 `/Applications`。
   Download `CCBar.app.zip` from Releases, unzip, drag `CCBar.app` into `/Applications`.

2. 首次启动会被 macOS Gatekeeper 拦下("无法验证开发者")。**请按这个顺序绕过**:
   First launch is blocked by Gatekeeper ("cannot verify developer"). **Bypass like this**:

   - 在 `应用程序` 里**右键 → 打开**(不是双击)
   - 弹窗里点**打开**
   - 之后就可以双击启动了

   或者在终端跑:
   Or run in Terminal:

   ```bash
   xattr -d com.apple.quarantine /Applications/CCBar.app
   ```

3. 首次启动如果本机没有 Claude 凭据文件,会先弹一个**双语提示**说明接下来 macOS 会请求 Keychain 访问权限,点击「继续」后请选择「**始终允许**」。
   On first launch, if no local Claude credentials file is present, a **bilingual prompt** appears explaining that macOS will ask for Keychain access — choose **Always Allow**.

## 凭据来源 · Credential Sources

| 服务 Service | 来源 Source |
|---|---|
| Codex | `~/.codex/auth.json` |
| Claude Code | `~/.claude/.credentials.json`,若不存在则读 macOS Keychain `Claude Code-credentials` |

cc-bar **只读取**这些凭据,不上传、不复制。Quota 查询用各自的官方 API,本地 cost 来自 `~/.claude/projects/**/*.jsonl` 与 `~/.codex/sessions/**/*.jsonl` 的增量扫描。

cc-bar reads these credentials **only locally** — they are never uploaded or copied. Quota queries hit each vendor's official API. Local cost numbers come from incrementally scanning JSONL session logs under each tool's home directory.

## 反馈 · Feedback

bug 或建议请发邮件到 nanvon.hsu@gmail.com,或在 [Issues](https://github.com/nanvon/cc-bar/issues) 留言。
Bugs or suggestions: nanvon.hsu@gmail.com, or open a GitHub Issue.
