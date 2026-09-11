#!/bin/bash
# netauto 설치 — sudo 로 1회만 실행하면 이후 비밀번호 프롬프트 없음
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
LABEL="dev.devpaulie.netauto"
BIN=/usr/local/libexec/netauto
CONF_DIR=/usr/local/etc/netauto
CONF=$CONF_DIR/config.json
STATE_DIR=/usr/local/var/netauto
PLIST="/Library/LaunchDaemons/$LABEL.plist"
LINK=/usr/local/bin/netauto
LOG=/var/log/netauto.log

[ "$(id -u)" = "0" ] || { echo "sudo 로 실행하세요:  sudo $0" >&2; exit 1; }

echo "▸ 디렉터리 준비"
install -d -o root -g wheel -m 755 /usr/local/libexec /usr/local/etc /usr/local/var

# 설정 디렉터리는 admin 쓰기 가능 — 메뉴바 앱의 설정 창이 원자적으로 저장할 수 있어야 한다.
# (/usr/local/etc 자체는 root 전용이라 그 안에 임시 파일을 만들 수 없다)
install -d -o root -g admin -m 775 "$CONF_DIR"

# 상태 디렉터리와 요청 큐는 admin 그룹 쓰기 허용.
# 메뉴바 앱(사용자 권한)이 일시중지 플래그와 요청 파일을 쓸 수 있어야 하고,
# 그래야 GUI에서 비밀번호를 묻지 않는다.
#   · 실행 파일과 설정 파일은 root 전용으로 유지 → 임의 코드 실행 경로 없음
#   · admin 사용자는 시스템 설정에서 이미 네트워크를 바꿀 수 있으므로 권한 상승 아님
install -d -o root -g admin -m 775 "$STATE_DIR" "$STATE_DIR/queue"

echo "▸ 스크립트 설치 → $BIN"
install -o root -g wheel -m 755 "$SRC/bin/netauto" "$BIN"

echo "▸ 설정 파일 → $CONF"
if [ -e "$CONF" ]; then
  if cmp -s "$SRC/etc/netauto.json" "$CONF"; then
    echo "   동일 — 유지"
  else
    cp -p "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
    echo "   기존 설정 보존 (백업 생성). 새 기본값은 $SRC/etc/netauto.json 참고"
  fi
else
  # root:admin 664 — 메뉴바 앱의 '설정 파일 열기'로 바로 편집·저장할 수 있게.
  # 이 파일은 SSID→위치 이름 매핑만 담고, 위치는 전환 전에 존재 여부를 검증하므로
  # 임의 명령 실행 경로가 되지 않는다.
  install -o root -g admin -m 664 "$SRC/etc/netauto.json" "$CONF"
fi

echo "▸ CLI 링크 → $LINK"
install -d -m 755 /usr/local/bin
ln -sfn "$BIN" "$LINK"

echo "▸ 로그 파일 → $LOG"
: > /dev/null; [ -e "$LOG" ] || { : > "$LOG"; chown root:wheel "$LOG"; chmod 644 "$LOG"; }

echo "▸ 요청 큐 비우기"
rm -f "$STATE_DIR/queue"/* 2>/dev/null || true

echo "▸ LaunchDaemon 등록 → $PLIST"
launchctl bootout "system/$LABEL" 2>/dev/null || true
install -o root -g wheel -m 644 "$SRC/launchd/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
launchctl enable "system/$LABEL"

echo
echo "✓ 설치 완료"
echo
"$BIN" status
echo
echo "다음 명령으로 언제든 제어할 수 있습니다:"
echo "  netauto status          현재 상태"
echo "  sudo netauto pause 60   60분 일시중지"
echo "  sudo netauto off        완전 중지"
echo "  netauto log             로그 확인"
