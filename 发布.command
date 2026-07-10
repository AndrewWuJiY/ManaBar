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
  git commit -m "release: v$VERSION — 悬浮窗快捷操作与版本发布

- 全局快捷键 ⌃⌥F 显示/隐藏悬浮窗 (Carbon RegisterEventHotKey,后台可用、无需辅助功能授权,设置可关)
- 悬浮窗右键菜单:关闭悬浮窗 / 打开设置
- Popover 顶栏新增悬浮窗开关按钮,开启时高亮强调色
- 打包安装.command 构建失败时输出错误摘要;新增 发布.command
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

cc-bar 正式更名 **ManaBar**,并带来一批体验升级:

- 🪄 **全新品牌**:更名 ManaBar,全新「双法力条」图标;旧版 CCBar 设置自动迁移
- 🌓 **外观切换**:浅色 / 深色 / 跟随系统,全窗口生效
- ⌨️ **悬浮窗快捷操作**:全局快捷键 \`⌃⌥F\` 一键显隐;右键悬浮窗弹出菜单;Popover 顶栏新增悬浮窗开关
- 👀 **可读性优化**:状态色按浅/深色分别调校(浅色警告黄改深琥珀)、字体层级整体提档、图表坐标轴标签加深
- 🔴 **额度告急提示**:悬浮窗额度 <10% 时百分比加危险色底

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
