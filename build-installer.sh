#!/bin/bash
# 설치 프로그램 빌드 — 코딩을 몰라도 설치할 수 있는 .pkg 와 .dmg 를 만든다.
#   dist/netauto-<버전>.pkg   더블클릭하면 설치 마법사가 뜬다
#   dist/netauto-<버전>.dmg   그 pkg 와 안내문을 담은 디스크 이미지
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetautoBar"
DAEMON=dev.devpaulie.netauto
AGENT=dev.devpaulie.netauto.bar
VERSION="$(/usr/bin/sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SRC/bin/netauto" | head -1)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

# 빌드 작업은 프로젝트 밖 임시 디렉터리에서 한다.
# (설치 테스트 중 root 소유 파일이 프로젝트에 남아 정리 못하는 일을 막는다)
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/netauto-build.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
STAGE="$BUILD/stage"
COMPONENT="$BUILD/component.pkg"
PKG="$SRC/dist/netauto-$VERSION.pkg"
DMG="$SRC/dist/netauto-$VERSION.dmg"
VOLNAME="netauto $VERSION"

echo "▸ 메뉴바 앱 빌드"
"$SRC/build-app.sh" >/dev/null

echo "▸ 정리"
rm -f "$PKG" "$DMG"
mkdir -p "$STAGE" "$SRC/dist"

echo "▸ 설치 내용 구성"
# 실행 파일
install -d -m 755 "$STAGE/usr/local/libexec"
install -m 755 "$SRC/bin/netauto" "$STAGE/usr/local/libexec/netauto"
install -m 755 "$SRC/bin/netauto-uninstall" "$STAGE/usr/local/libexec/netauto-uninstall"
# 기본 설정은 share 에 두고, postinstall 이 처음 설치일 때만 etc 로 복사한다
install -d -m 755 "$STAGE/usr/local/share/netauto"
install -m 644 "$SRC/etc/netauto.json" "$STAGE/usr/local/share/netauto/config.default.json"
# 서비스 등록 파일
install -d -m 755 "$STAGE/Library/LaunchDaemons" "$STAGE/Library/LaunchAgents"
install -m 644 "$SRC/launchd/$DAEMON.plist" "$STAGE/Library/LaunchDaemons/$DAEMON.plist"
install -m 644 "$SRC/installer/$AGENT.plist" "$STAGE/Library/LaunchAgents/$AGENT.plist"
# 앱
install -d -m 755 "$STAGE/Applications"
cp -R "$SRC/dist/$APP_NAME.app" "$STAGE/Applications/$APP_NAME.app"

echo "▸ 앱 번들 재배치 끄기"
# pkgbuild 는 페이로드의 .app 을 기본적으로 "재배치 가능"으로 표시한다.
# 그러면 설치 시 macOS 가 같은 번들 ID 를 가진 기존 앱을 찾아 그 위치에 덮어쓴다
# (예: 개발 중 실행해 본 build/ 안의 복사본). 결과적으로 /Applications 에
# 아무것도 설치되지 않아 메뉴바에 나타나지 않는다.
# BundleIsRelocatable=false 로 항상 /Applications 에 설치되게 고정한다.
pkgbuild --analyze --root "$STAGE" "$BUILD/component.plist" >/dev/null
i=0
while /usr/bin/plutil -extract "$i.BundleIsRelocatable" raw -o - "$BUILD/component.plist" >/dev/null 2>&1; do
  plutil -replace "$i.BundleIsRelocatable" -bool false "$BUILD/component.plist"
  i=$((i + 1))
done
echo "   번들 $i 개 고정"

echo "▸ 컴포넌트 패키지 (pkgbuild)"
# --ownership recommended: 빌드한 사용자 소유가 아니라 설치 시 root:wheel 로 배치된다
pkgbuild \
  --root "$STAGE" \
  --component-plist "$BUILD/component.plist" \
  --scripts "$SRC/installer/scripts" \
  --identifier "$DAEMON" \
  --version "$VERSION" \
  --ownership recommended \
  --install-location / \
  "$COMPONENT" >/dev/null

echo "▸ 설치 화면 아이콘 렌더링"
# 설치 화면은 HTML 이라 SF Symbol 을 직접 쓸 수 없다.
# 앱에서 쓰는 것과 똑같은 심볼을 PNG 로 구워 base64 로 심는다 (라이트/다크 2종).
RES="$BUILD/resources"
mkdir -p "$RES"
# 템플릿(.in)은 제외하고 나머지 리소스를 복사
for f in "$SRC/installer/resources/"*; do
  case "$f" in *.html.in) continue ;; esac
  cp "$f" "$RES/"
done
swiftc -O -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos13.0" \
  -o "$BUILD/render-symbol" "$SRC/tools/render-symbol.swift"
python3 "$SRC/tools/build-html.py" "$BUILD/render-symbol" "$VERSION" "$RES" \
  "$SRC/installer/resources/welcome.html.in" \
  "$SRC/installer/resources/conclusion.html.in"

echo "▸ 설치 마법사 (productbuild)"
cat > "$BUILD/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>netauto</title>
    <organization>dev.devpaulie</organization>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="true" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <volume-check>
        <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="netauto"><pkg-ref id="$DAEMON"/></choice>
    <pkg-ref id="$DAEMON" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

productbuild \
  --distribution "$BUILD/distribution.xml" \
  --resources "$RES" \
  --package-path "$BUILD" \
  "$PKG" >/dev/null

echo "▸ 디스크 이미지 (hdiutil)"
DMGROOT="$BUILD/dmg"
mkdir -p "$DMGROOT"
cp "$PKG" "$DMGROOT/netauto 설치.pkg"
cp "$SRC/installer/resources/READ-ME-FIRST.rtf" "$DMGROOT/처음 읽어주세요.rtf" 2>/dev/null || true
hdiutil create -quiet -srcfolder "$DMGROOT" -volname "$VOLNAME" \
  -fs HFS+ -format UDZO -ov "$DMG"

echo
echo "✓ 완성"
printf '  %s  (%s)\n' "$PKG" "$(du -h "$PKG" | awk '{print $1}')"
printf '  %s  (%s)\n' "$DMG" "$(du -h "$DMG" | awk '{print $1}')"
