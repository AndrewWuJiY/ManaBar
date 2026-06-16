#!/bin/bash
# ManaBar 一键构建安装脚本：双击运行，或在终端执行 bash 打包安装.command
# 构建 Release 版 ManaBar.app 并安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

# 确认 xcodebuild 指向完整 Xcode
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ xcodebuild 不可用。请先安装完整 Xcode 并执行:"
  echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "▶ 开始构建 ManaBar (Release)..."
xcodebuild -project ManaBar.xcodeproj \
  -scheme ManaBar \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  build | tail -5

APP="build/DerivedData/Build/Products/Release/ManaBar.app"
if [ ! -d "$APP" ]; then
  echo "❌ 构建产物未找到: $APP"
  exit 1
fi

echo "▶ 安装到 /Applications/ManaBar.app ..."
rm -rf /Applications/ManaBar.app
ditto "$APP" /Applications/ManaBar.app

if [ -d /Applications/CCBar.app ]; then
  echo "⚠️  检测到旧版 /Applications/CCBar.app,建议手动删除以免两个同时运行。"
fi

echo "▶ 启动 ManaBar..."
open /Applications/ManaBar.app
echo "✅ 完成。菜单栏应出现 ManaBar 图标。"
