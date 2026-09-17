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
  git commit -m "release: v$VERSION — CLI 凭据改为只读,修复 Claude CLI 隔几天掉线

- 根因:ManaBar 过期时自行用 refresh_token 续期并回写钥匙串,而 refresh_token 一次性旋转,
  与内存里持有旧 token 的 claude CLI 会话冲突,CLI 被 invalid_grant 顶掉线需重新 /login
- ClaudeTokenRefresher 改只读:删除 OAuth 续期、回写、Coordinator / 软恢复;过期时重读存储,
  仍过期则后台委托 claude CLI 刷新并走 CLI 兜底,保留已有快照
- Codex 默认账号(~/.codex/auth.json)同样只读,过期时提示运行一次 codex;
  手动导入的副账号是 ManaBar 自有副本,仍由 ManaBar 续期并只回写其 Keychain 条目
- QuotaError 新增 tokenExpired(app),给出等待 CLI 续期的提示
- 同步 docs(技术实现 §5 / §6.3 / §11 / §13 / §14.3、产品需求、打包发布)与版本号 v$VERSION

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q55iS3m5Hp9Ei7EVrdsCb9"
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

- 🔐 **修复 Claude Code CLI 隔几天就要重新登录**:ManaBar 以前会在 token 过期时自己续期,和正在运行的 claude 会话抢同一个一次性 refresh_token,把 CLI 顶掉线。现在对 CLI 的登录凭据**只读不写**,续期完全交给 CLI
- 🔐 **Codex 同样只读**:不再改写 \`~/.codex/auth.json\`;手动导入的 Codex 副账号仍由 ManaBar 自行续期(只写自己的钥匙串副本)
- ⏳ CLI 长时间没运行、凭据过期时,额度保留上次数据并提示「运行一次 claude / codex 即可恢复」;Claude 会在后台自动唤起 CLI 刷新
- 💰 价格表新增 GPT-6 Astra

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
