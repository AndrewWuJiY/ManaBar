#!/bin/bash
# 一键:退出旧实例 → 跑发布流程 → 安装到 /Applications → 启动
# 由 发布.command 完成构建/提交/推送/GitHub Release,本脚本只负责前后两头。
set -uo pipefail
cd "$(dirname "$0")"

echo "═══ 1/3 退出正在运行的 ManaBar ═══"
osascript -e 'quit app "ManaBar"' 2>/dev/null || true
sleep 2

echo
echo "═══ 2/3 执行发布 ═══"
if ! ./发布.command; then
  echo
  echo "❌ 发布流程失败,已中止,未安装新版本。"
  echo "按任意键关闭…"; read -n 1 -s
  exit 1
fi

echo
echo "═══ 3/3 安装到 /Applications ═══"
APP="build/DerivedData/Build/Products/Release/ManaBar.app"
if [ ! -d "$APP" ]; then
  echo "❌ 未找到构建产物: $APP"
  echo "按任意键关闭…"; read -n 1 -s
  exit 1
fi
osascript -e 'quit app "ManaBar"' 2>/dev/null || true
sleep 1
rm -rf /Applications/ManaBar.app
cp -R "$APP" /Applications/ManaBar.app
xattr -dr com.apple.quarantine /Applications/ManaBar.app 2>/dev/null || true
open /Applications/ManaBar.app

echo
echo "✅ 全部完成。启动台里的 ManaBar 已是新版本。"
echo "   小组件若仍显示旧样式,把它从桌面删掉重新拖一个(系统需重新加载 extension)。"
echo
echo "按任意键关闭…"; read -n 1 -s
