#!/bin/bash
# ManaBar 发布脚本：构建 Release → 压缩 zip → 推送 main + tag → 创建 GitHub Release
# 需要:完整 Xcode;推荐安装 GitHub CLI (brew install gh && gh auth login)
set -euo pipefail
cd "$(dirname "$0")"

# 清理沙盒会话可能残留的 git 锁文件
rm -f .git/*.lock .git/objects/*/tmp_obj_* 2>/dev/null || true

# 各 target 的 MARKETING_VERSION 必须一致:Xcode 要求 app extension 的 CFBundleShortVersionString
# 与宿主 App 相同,不一致会在构建期报警告。这里直接卡住,免得 head -1 取到 widget 的旧版本号打错 tag。
VERSIONS=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' ManaBar.xcodeproj/project.pbxproj | tr -d ' ' | sort -u)
if [ "$(echo "$VERSIONS" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "❌ 各 target 的 MARKETING_VERSION 不一致:"
  echo "$VERSIONS" | sed 's/^/   /'
  echo "   主 App 与 ManaBarWidgetExtension 必须同版本,请在 Xcode 里改成一致后重试。"
  exit 1
fi
VERSION="$VERSIONS"
TAG="v$VERSION"
echo "▶ 发布版本: $TAG"

# 0. 提交未提交的改动
if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "▶ 提交本地改动..."
  git add -A
  # ⚠️ 每次发版前更新这段说明,它会成为本次 release commit 的正文。
  git commit -m "release: v$VERSION — 桌面小组件(WidgetKit)

- 新增 macOS 桌面小组件(仅中尺寸):两行显示 Codex / Claude Code 剩余额度、
  重置倒计时与状态色,点按打开用量统计;主 App 未运行时显示「ManaBar 未运行」空态
- 数据通路:新增 App Group 共享容器(group.659P79368S.com.andrewwujiy.manabar),
  quota-cache.json 落点改为容器优先、旧路径回退并做一次单向迁移(只拷不删)
- 小组件不查任何 API,由主 App 在每次额度落盘时写共享状态 + 5 分钟心跳推送 reload;
  空态靠 timeline 预埋的到期 entry 自动翻转,不依赖主 App 退出时的通知
- 新增 URL scheme manabar://stats,由 AppDelegate 处理(冷启动先缓冲再补发)
- 抽出 Shared/ 供两个 target 共用:statusColor / ServiceTile / ProgressBar /
  compactRelativeReset,Main/DesignSystem.swift 只留主窗口专用组件
- 同步 docs(技术实现 §15 / 界面布局 §2A / 设计风格 §4.4 / 产品需求 §4A / README)与版本号 v$VERSION"
fi

# 1. 构建
echo "▶ 构建 Release..."
LOG=build/xcodebuild.log
mkdir -p build
if ! xcodebuild -project ManaBar.xcodeproj -scheme ManaBar -configuration Release \
  -derivedDataPath build/DerivedData build > "$LOG" 2>&1; then
  echo "❌ 构建失败,错误摘要:"; grep -E "error:" "$LOG" | head -20; exit 1
fi
APP="build/DerivedData/Build/Products/Release/ManaBar.app"
[ -d "$APP" ] || { echo "❌ 产物未找到: $APP"; exit 1; }

# 2. 压缩
echo "▶ 打包 ManaBar.app.zip..."
ZIP="build/ManaBar.app.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 3. 推送代码与 tag
echo "▶ 推送 main 与 tag $TAG..."
git push origin main
git tag -f "$TAG"
git push -f origin "$TAG"

# 4. 创建 GitHub Release
# ⚠️ 每次发版前更新这段,它会成为 GitHub Release 的正文。
NOTES="## ManaBar $VERSION

- 🖥️ **桌面小组件**:新增 macOS 系统小组件(中尺寸),两行显示 Codex 与 Claude Code 的剩余额度、重置倒计时与状态色;点按打开用量统计。在桌面空白处右键 →「编辑小组件」,搜索 ManaBar 即可添加
- 🔌 **主 App 未运行时明确提示**:小组件显示「ManaBar 未运行」空态而非过期数字,点按即可启动——不让旧数据被误读为实时额度
- ⚠️ **低额度形状冗余**:macOS 桌面小组件在点击桌面时会被系统去饱和、交通灯颜色失效,因此剩余 \`<20%\` 与耗尽两档额外显示警告符号
- 🔄 小组件不查询任何 API:额度由主 App 写入 App Group 共享容器,小组件只读;主 App 每次额度落盘与 5 分钟心跳推送刷新

### 安装
下载 \`ManaBar.app.zip\`,解压拖入「应用程序」。首次启动被 Gatekeeper 拦下时右键 → 打开,或执行:
\`xattr -d com.apple.quarantine /Applications/ManaBar.app\`

添加小组件需要 App 位于 \`/Applications\`。"

if command -v gh >/dev/null 2>&1; then
  echo "▶ 通过 gh 创建 Release..."
  gh release create "$TAG" "$ZIP" --title "ManaBar $VERSION" --notes "$NOTES"
  echo "✅ 发布完成: $(gh release view "$TAG" --json url -q .url)"
else
  echo "⚠️  未安装 GitHub CLI,改为手动流程:"
  echo "$NOTES" > build/RELEASE_NOTES.md
  open -R "$ZIP"
  open "https://github.com/AndrewWuJiY/ManaBar/releases/new?tag=$TAG&title=ManaBar%20$VERSION"
  echo "   1. 浏览器已打开新建 Release 页(tag: $TAG)"
  echo "   2. 把访达中选中的 ManaBar.app.zip 拖入附件"
  echo "   3. Release 说明见 build/RELEASE_NOTES.md,复制粘贴即可"
fi
