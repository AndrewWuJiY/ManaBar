# ManaBar

> ManaBar —— macOS 菜单栏小工具 —— 一眼看清 Codex 与 Claude Code 的用量与花费。

> 作者:[XiaoWuu](https://github.com/AndrewWuJiY) · 项目主页:https://github.com/AndrewWuJiY/ManaBar · 许可:MIT

<p>
  <img alt="platform" src="https://img.shields.io/badge/macOS-14+-blue.svg">
  <img alt="swift" src="https://img.shields.io/badge/Swift-5.9-orange.svg">
  <img alt="version" src="https://img.shields.io/badge/version-0.9.0-brightgreen.svg">
</p>

<p align="center">
  <img src="docs/Screenshots/popover.png" width="380" alt="ManaBar Popover 总览">
</p>

## 功能

- **用量显示** —— Codex 与 Claude Code 的 5 小时 / 周窗口剩余额度,实时同步
- **菜单栏 + 悬浮窗** —— 状态栏图标显示剩余百分比;可选桌面悬浮 HUD,可拖动、边缘吸附、置顶不抢焦
- **多 Codex 账号** —— 支持导入多个 Codex 账号,主副账号在 Popover 同屏展示
- **Token 与费用统计** —— 按今天 / 昨天 / 本周 / 本月 / 本年 / 7 天 / 30 天 / 全部 / 自定义切换;KPI、堆叠柱状图、按服务占比、按模型明细
- **丰富的设置** —— 账号开关、菜单栏显示项、悬浮窗、刷新间隔、重置时间显示、中英双语、开机自动启动

## 界面

<p align="center">
  <img src="docs/Screenshots/stats-overview.png" width="860" alt="用量统计 · 概览"><br>
  <sub>用量统计 · 概览</sub>
</p>

<p align="center">
  <img src="docs/Screenshots/timeline.png" width="860" alt="用量统计 · 时间线"><br>
  <sub>用量统计 · 时间线(5H 额度变化)</sub>
</p>

<p align="center">
  <img src="docs/Screenshots/breakdown.png" width="860" alt="用量统计 · 明细"><br>
  <sub>用量统计 · 明细(可排序 + 导出 CSV)</sub>
</p>

<p align="center">
  <img src="docs/Screenshots/floating.png" width="300" alt="桌面悬浮窗 HUD"><br>
  <sub>桌面悬浮窗 HUD</sub>
</p>

## 安装

要求 macOS 14 Sonoma 或更新版本。已通过终端完成 `codex login` 与 `claude` 登录。

1. 到 [Releases](https://github.com/AndrewWuJiY/ManaBar/releases) 下载最新 `ManaBar.app.zip`,解压后把 `ManaBar.app` 拖入 `/Applications`。

2. 首次启动会被 Gatekeeper 拦下。在「应用程序」里**右键 → 打开**,或在终端执行:

   ```bash
   xattr -d com.apple.quarantine /Applications/ManaBar.app
   ```

3. 若本机无 `~/.claude/.credentials.json`,会弹出说明后请求 Keychain 授权,请选「**始终允许**」。

## 反馈

请到 [Issues](https://github.com/AndrewWuJiY/ManaBar/issues) 留言。

## 致谢

ManaBar 在 [cc-bar](https://github.com/nanvon/cc-bar) 的基础上二次开发,在此特别感谢原项目作者。

同时在设计与实现上参考了以下优秀的开源项目:

- [cc-switch](https://github.com/farion1231/cc-switch) —— 多 Provider 账号切换器,启发了本项目的多账号管理与导入流程
- [cockpit-tools](https://github.com/jlcodes99/cockpit-tools) —— 多平台 AI 编码助手仪表盘,在额度与刷新策略上提供了参考
- [CodexBar](https://github.com/steipete/CodexBar) —— macOS 菜单栏 AI 用量监控,在菜单栏交互与本地解析思路上多有借鉴

## 许可

本项目基于 [MIT License](LICENSE) 开源,© 2026 XiaoWuu。
