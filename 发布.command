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
  git commit -m "release: v$VERSION — GPT-5.6 新模型价格 + Claude 桌面 App 用量统计

- Pricing 表新增 gpt-5.6-sol / gpt-5.6-terra / gpt-5.6-luna(官方 Standard 短上下文档价),
  修复 Codex 更新后新模型花费计 0、每日用量柱状图空白的问题
- ClaudeJSONLScanner 新增桌面 App(Cowork)会话日志扫描根,Claude 用量不再仅限 CLI;
  未公开内部目录,结构变化时静默降级为仅 CLI
- Popover 花费口径 caption 改为「仅本机」(cliOnlySpend → localOnlySpend),统计页提示同步
- 依赖 Pricing.fingerprint 自动失效缓存,历史桶全量重算,无需手动迁移
- 同步 docs 产品需求 / 技术实现 / 界面布局
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

修复 Codex 新模型花费统计,并新增 Claude 桌面 App 用量统计:

- 💰 **价格表更新**:新增 \`gpt-5.6-sol\` / \`gpt-5.6-terra\` / \`gpt-5.6-luna\`(官方 Standard 价)。修复 Codex 更新后新模型花费显示 \$0.00、每日用量柱状图空白的问题
- 🖥️ **Claude 桌面 App 用量统计**:用量统计不再仅限 CLI,Claude 桌面 App(Cowork)的本地会话 token 与花费也会计入;网页 / 移动端消耗仍只反映在额度环
- 🔄 **历史自动补算**:升级后首次启动自动重扫本地用量日志,已有的 App 端历史会话与今天的 Codex 花费都会自动补上

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
