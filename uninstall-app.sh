#!/bin/bash
# NetautoBar 메뉴바 앱 제거 — 데몬(netauto)은 그대로 둡니다
set -uo pipefail
APP_NAME="NetautoBar"
LABEL="dev.devpaulie.netauto.bar"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

[ "$(id -u)" != "0" ] || { echo "sudo 없이 실행하세요" >&2; exit 1; }

echo "▸ 자동 시작 해제"
/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$AGENT"

echo "▸ 앱 종료 · 제거"
/usr/bin/pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"

echo
echo "✓ 메뉴바 앱 제거 완료"
echo "  데몬은 계속 동작합니다 (자동 전환 유지). 데몬까지 지우려면: sudo ./uninstall.sh"
