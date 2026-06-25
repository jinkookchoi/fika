#!/bin/bash
# Fika 를 빌드하고 .app 번들로 조립합니다. (Command Line Tools 만으로 동작)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Fika.app"
BIN="fika"

echo "▶ swift build ($CONFIG)…"
swift build -c "$CONFIG"

BINPATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN"

echo "▶ .app 번들 조립…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINPATH" "$APP/Contents/MacOS/Fika"
cp Info.plist "$APP/Contents/Info.plist"

# 로그인 항목 등록(SMAppService)을 위해 임시 ad-hoc 서명.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅ 완료: $APP"
echo "   실행:  open $APP   (또는 ./$APP/Contents/MacOS/Fika 로 콘솔 로그 확인)"
