#!/bin/bash
# Fika 를 빌드하고 친구 공유용 zip 으로 묶습니다.
# 결과: Fika.zip (고정명) → 압축 풀어 /Applications 에 드래그하면 끝.
# 파일명을 버전 없이 고정해, GitHub Releases 의 "최신" 자산을 갈아끼우거나
# .../releases/latest/download/Fika.zip 고정 링크로 받을 수 있게 한다.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist 2>/dev/null || echo 1.0)"
ZIP="Fika.zip"
rm -f "$ZIP"

# ditto 로 .app 압축 (macOS 메타데이터·심볼릭링크 보존 — 일반 zip 보다 안전)
ditto -c -k --keepParent Fika.app "$ZIP"

echo ""
echo "✅ 배포 zip 생성: $ZIP (버전 $VERSION)"
echo "   친구에게 전달하는 법:"
echo "   1) 압축을 풀어 Fika.app 을 '응용 프로그램(Applications)' 으로 드래그"
echo "   2) 처음 열 때 우클릭 → 열기 → '열기' (확인되지 않은 개발자 경고 허용)"
echo "   3) 안 열리면 터미널에:  xattr -dr com.apple.quarantine /Applications/Fika.app"
