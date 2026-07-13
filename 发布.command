#!/bin/bash
# ManaBar 发布脚本：构建 Release → 压缩 zip → 推送 main + tag → 创建 GitHub Release
# 需要:完整 Xcode;推荐安装 GitHub CLI (brew install gh && gh auth login)
set -euo pipefail
cd "$(dirname "$0")"

# 清理沙盒会话可能残留的 git 锁文件
rm -f .git/*.lock .git/objects/*/tmp_obj_* 2>/dev/null || true

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' ManaBar.xcodeproj/project.pbxproj | head -1)
TAG="v$VERSION"
echo "▶ 发布版本: $TAG"

# 0. 提交未提交的改动
if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "▶ 提交本地改动..."
  git add -A
  git commit -m "release: v$VERSION — 适配 Codex 取消 5 小时限制

- CodexQuotaClient 窗口解析改按时长归类(≥24h 归 weekly),不再按 primary/secondary 位置假设,
  修复周额度被画进 5H 槽位、WK 显示 --% 的问题
- 新增 QuotaSnapshot.fiveHourUnlimited:Popover 大数字 / 统计环 / 副账号行显示 ∞ 无限制
- 菜单栏 5H 模式与悬浮窗在无限制时回退显示周额度(fiveHour ?? weekly),恢复限制自动还原
- Popover 网络错误收敛为友好文案,不再显示 NSURLErrorDomain 原始串
- 同步 docs 产品需求 / 技术实现
- 版本号升至 v$VERSION"
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
NOTES="## ManaBar $VERSION

适配 OpenAI 取消 Codex 5 小时限制(2026-07):

- 🔧 **窗口解析重构**:不再按 primary/secondary 位置假设,改按窗口时长归类(≥24h 归周窗口)。修复取消限制后周额度被画进 5H 槽位、WK 显示 \`--%\` 的问题
- ♾️ **无限制状态**:检测到无 5h 窗口时,Popover 大数字 / 统计限额环 / Codex 副账号行显示 \`∞ 无限制\`
- 📊 **菜单栏与悬浮窗回退周额度**:\`∞\` 对常驻小组件没有信息量,菜单栏 5H 模式与悬浮窗自动改显周额度耗量;OpenAI 恢复限制后自动还原
- 💬 **报错友好化**:网络波动时不再显示 NSURLErrorDomain 原始错误串,并明确标注展示的是上次成功数据

### 安装
下载 \`ManaBar.app.zip\`,解压拖入「应用程序」。首次启动被 Gatekeeper 拦下时右键 → 打开,或执行:
\`xattr -d com.apple.quarantine /Applications/ManaBar.app\`"

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
