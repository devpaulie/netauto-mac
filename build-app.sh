#!/bin/bash
# NetautoBar 메뉴바 앱 빌드 — Xcode 없이 Command Line Tools 만으로 .app 번들 생성
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetautoBar"
BUNDLE_ID="dev.devpaulie.netauto.bar"
VERSION="$(/usr/bin/sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SRC/bin/netauto" | head -1)"
OUT="$SRC/dist/$APP_NAME.app"
MIN_MACOS="13.0"   # MenuBarExtra 요구 버전

SDK="$(xcrun --sdk macosx --show-sdk-path)"
# 유니버설(애플 실리콘 + 인텔)로 만든다.
# 한 아키텍처만 넣으면 다른 맥에 줬을 때 실행되지 않는다.
ARCHS="arm64 x86_64"

echo "▸ 정리"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

SWIFT_V="$(swift --version 2>/dev/null | /usr/bin/sed -n 's/.*version \([0-9.]*\).*/\1/p' | head -1)"
echo "▸ 컴파일  (swift $SWIFT_V · $ARCHS · macOS $MIN_MACOS+)"
TMPBIN="$(mktemp -d "${TMPDIR:-/tmp}/netauto-app.XXXXXX")"
trap 'rm -rf "$TMPBIN"' EXIT
SLICES=""
for arch in $ARCHS; do
  printf '   %s ... ' "$arch"
  swiftc -O -parse-as-library \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    -sdk "$SDK" \
    -o "$TMPBIN/$arch" \
    "$SRC/app/$APP_NAME/Core.swift" "$SRC/app/$APP_NAME/UI.swift"
  echo "완료"
  SLICES="$SLICES $TMPBIN/$arch"
done
lipo -create $SLICES -output "$OUT/Contents/MacOS/$APP_NAME"
echo "   합침: $(lipo -info "$OUT/Contents/MacOS/$APP_NAME" | /usr/bin/sed 's/.*are: //')"

echo "▸ Info.plist"
/bin/cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundleDisplayName</key><string>netauto</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
	<!-- 메뉴바 전용 앱: Dock 아이콘·앱 스위처에 나타나지 않는다 -->
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>netauto — by devpaulie</string>
	<!-- macOS 15 부터 Wi-Fi 이름을 읽으려면 위치 권한이 필요하다.
	     백그라운드 서비스는 이 권한을 받을 수 없어서 앱이 대신 읽는다. -->
	<key>NSLocationUsageDescription</key>
	<string>지금 연결된 Wi-Fi 이름을 확인해 알맞은 네트워크 프로필로 전환하기 위해 필요합니다. 위치를 수집하거나 어디에도 보내지 않습니다.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>지금 연결된 Wi-Fi 이름을 확인해 알맞은 네트워크 프로필로 전환하기 위해 필요합니다. 위치를 수집하거나 어디에도 보내지 않습니다.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Wi-Fi 가 바뀔 때마다 이름을 확인해 프로필을 전환하려면 항상 허용이 필요합니다. 위치를 수집하거나 어디에도 보내지 않습니다.</string>
</dict>
</plist>
PLIST

echo "▸ 애드혹 코드서명"
# 개발자 인증서가 없으므로 애드혹(-). 로컬 실행에는 충분하다.
codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT" >/dev/null 2>&1
codesign --verify --deep --strict "$OUT" && echo "   서명 검증 통과"

echo
echo "✓ 빌드 완료: $OUT"
/usr/bin/du -sh "$OUT" | /usr/bin/awk '{print "  크기: " $1}'
echo "  아키텍처: $(lipo -info "$OUT/Contents/MacOS/$APP_NAME" | /usr/bin/sed 's/.*are: //')"
