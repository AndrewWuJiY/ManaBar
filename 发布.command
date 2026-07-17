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
  git commit -m "release: v$VERSION — 额度时间线自动回退(5H→周) + Claude 凭据失效自愈

- 额度历史监测窗口自动回退:5H 优先,无 5H 窗口(Codex 已取消 5h 限制)时改记周额度;
  样本/事件新增 window 字段,窗口切换只重置基线、不产生跨窗口假事件,旧数据自动兼容
- 时间线 UI:标题改为「额度变化」,账号卡片新增窗口标签(5H/周),「当前」指标同步回退取值;
  表格重置时间非当天显示 MM-dd HH:mm(周窗口约 7 天后重置,只显示时刻会误导),列宽 96→130pt
- Claude 凭据自愈:无 refresh_token 时先重读存储、再后台委托 claude CLI 刷新;
  凭据空壳/刷新被拒时转 CLI 兜底获取额度(10 分钟限频),登录失效给出重新登录提示
- 同步 docs(技术实现/界面布局/产品需求/打包发布)与版本号 v$VERSION"
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

- 📈 **额度时间线自动回退**:适配 Codex 取消 5 小时限制,时间线不再空白——有 5H 额度时监测 5H,否则自动改为监测周额度;账号卡片标注当前窗口(5H / 周),窗口切换不产生假变动,历史数据自动兼容
- 🕐 **重置时间更清晰**:时间线表格中非当天的重置时间显示为 \`MM-dd HH:mm\`(周额度约 7 天后重置,原先只显示时刻容易误读为当天)
- 🔐 **Claude 凭据失效自愈**:凭据缺 refresh_token 或被清空(CLI 登出/掉线)时,自动重读存储并委托 claude CLI 后台刷新,仍不行则改走 CLI 兜底获取额度(10 分钟限频);登录失效时明确提示「请在终端运行 claude 重新登录」

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
