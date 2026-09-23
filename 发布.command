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
  git commit -m "release: v$VERSION — 价格表自动更新(LiteLLM 远程表) + 未定价标记

- 新增 RemotePricing:运行时从 LiteLLM model_prices_and_context_window.json 拉取 anthropic / openai
  价格(GitHub raw → jsDelivr 兜底),12h 内不重复拉,Scheduler 每小时检查;解析结果缓存到
  Application Support/ManaBar/remote-pricing.json,启动先用缓存
- 远程优先、内置表兜底;PricingStore 加锁保存远程表与合并指纹;指纹变化 → 清空聚合并全量重算历史花费
- scanNow 在扫描开始时固定指纹落盘,扫描中途价格更新时下一轮必然重算
- 统计页明细 / 按模型:价格表查不到的模型显示「未定价」,不再显示 \$0.00
- 内置表新增 Claude Opus 5.5、GPT-6 Sol / Luna
- 同步 docs(产品需求、技术实现 §7.5 / §8 / §11 / §13、界面布局、设计风格词表、打包发布)与版本号 v$VERSION

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SnsfSLe3mRit5yXMhoFvpX"
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

- 💰 **价格表自动更新**:启动时和之后每 12 小时从 LiteLLM 社区价格表拉取 Claude / OpenAI 模型价格,新模型、调价不用等发版;拉取失败沿用上次价格,离线也能用
- 🔁 价格变化后自动按新价格重算全部历史花费
- 🏷️ 查不到价格的模型显示「未定价」,不再显示 \$0.00 被误当成免费
- ➕ 内置价格表新增 Claude Opus 5.5、GPT-6 Sol / Luna

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
