#!/bin/bash
# netauto 완전 제거 — 네트워크 위치 자체는 그대로 남습니다
set -uo pipefail

LABEL="dev.devpaulie.netauto"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
KEEP_CONF="${KEEP_CONF:-1}"

[ "$(id -u)" = "0" ] || { echo "sudo 로 실행하세요:  sudo $0" >&2; exit 1; }

echo "▸ LaunchDaemon 해제"
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

echo "▸ 실행 파일·링크 제거"
rm -f /usr/local/libexec/netauto /usr/local/bin/netauto

echo "▸ 상태 파일 · 요청 큐 제거"
rm -rf /usr/local/var/netauto

if [ "$KEEP_CONF" = "1" ]; then
  echo "▸ 설정 파일 유지: /usr/local/etc/netauto/config.json  (지우려면 KEEP_CONF=0 sudo $0)"
else
  rm -f /usr/local/etc/netauto/config.json
  echo "▸ 설정 파일 제거"
fi

echo
echo "✓ 제거 완료 — 네트워크 위치(Office / Automatic 등)는 손대지 않았습니다."
echo "  현재 위치: $(networksetup -getcurrentlocation)"
