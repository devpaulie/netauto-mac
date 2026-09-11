#!/bin/bash
# NetautoBar 메뉴바 앱 설치 — sudo 불필요
#   · /Applications 는 admin 그룹 쓰기 가능
#   · 자동 시작은 사용자 LaunchAgent (~/Library/LaunchAgents)
# 위치 전환 자체는 root 데몬이 하므로 먼저 sudo ./install.sh 가 되어 있어야 한다.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NetautoBar"
LABEL="dev.devpaulie.netauto.bar"
APP="/Applications/$APP_NAME.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

[ "$(id -u)" != "0" ] || { echo "이 스크립트는 sudo 없이 실행하세요 (일반 사용자 권한)" >&2; exit 1; }

# 데몬이 먼저 설치돼야 앱이 할 일이 있다
if [ ! -x /usr/local/libexec/netauto ]; then
  echo "경고: netauto 데몬이 아직 설치되지 않았습니다."
  echo "      먼저 실행하세요:  sudo $SRC/install.sh"
  echo
fi

echo "▸ 빌드"
"$SRC/build-app.sh" >/dev/null

echo "▸ 실행 중이면 종료"
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "▸ 앱 설치 → $APP"
rm -rf "$APP"
/bin/cp -R "$SRC/dist/$APP_NAME.app" "$APP"

echo "▸ 로그인 시 자동 시작 등록 → $AGENT"
/bin/mkdir -p "$HOME/Library/LaunchAgents"
/bin/cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP/Contents/MacOS/$APP_NAME</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<!-- 사용자가 메뉴에서 '종료'를 누르면 다시 띄우지 않는다 -->
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$AGENT" >/dev/null

/bin/launchctl bootstrap "gui/$(id -u)" "$AGENT"
/bin/launchctl enable "gui/$(id -u)/$LABEL"

echo
echo "✓ 설치 완료 — 메뉴바 오른쪽에 아이콘이 나타납니다"
echo
echo "아이콘 읽는 법:"
echo "  🏢 building.2   사내 프로필 적용 중"
echo "  📶 wifi         기본 프로필(Automatic)"
echo "  ✋ hand.raised  내가 수동으로 지정한 상태 — 자동이 양보 중"
echo "  ⏸  pause.circle 일시중지"
echo "  🚫 nosign       자동 전환 꺼짐"
echo "  ⚠️  wifi.slash   Wi-Fi 미연결"
echo
echo "제거:  ./uninstall-app.sh"
