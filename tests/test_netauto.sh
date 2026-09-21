#!/bin/bash
# netauto 테스트 — 실제 네트워크 설정을 절대 건드리지 않는다.
# networksetup / ipconfig / id 를 모두 모의(mock) 구현으로 대체해 실행.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NETAUTO="$ROOT/bin/netauto"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  ✗ %s\n     기대: %s\n     실제: %s\n' "$1" "$2" "$3"; }
check(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "포함: $2" "$3" ;; esac; }
hasnt(){ case "$3" in *"$2"*) no "$1" "미포함: $2" "$3" ;; *) ok "$1" ;; esac; }

# ── 모의 명령 ─────────────────────────────────────────────────────────
mkdir -p "$TMP/mock"
cat > "$TMP/mock/networksetup" <<'MOCK'
#!/bin/bash
# MOCK_SSID / MOCK_LOCATION / MOCK_POWER / MOCK_LOCATIONS 로 동작 제어
# 위치 전환 시도는 MOCK_SWITCH_LOG 에 기록만 하고 실제로 바꾸지 않음
case "$1" in
  -listallhardwareports) printf 'Hardware Port: Wi-Fi\nDevice: en0\nEthernet Address: 00:00:00:00:00:00\n' ;;
  -getairportpower)      printf 'Wi-Fi Power (en0): %s\n' "${MOCK_POWER:-On}" ;;
  -getairportnetwork)
      if [ -n "${MOCK_SSID:-}" ]; then printf 'Current Wi-Fi Network: %s\n' "$MOCK_SSID"
      else printf 'You are not associated with an AirPort network.\n'; fi ;;
  -getcurrentlocation)   printf '%s\n' "${MOCK_LOCATION:-Automatic}" ;;
  -listlocations)        printf '%s\n' ${MOCK_LOCATIONS:-Office Automatic} ;;
  -switchtolocation)     printf '%s\n' "$2" >> "${MOCK_SWITCH_LOG:-/dev/null}"; printf 'Location was switched.\n' ;;
  -listnetworkserviceorder) printf '(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)\n' ;;
  -setmanualwithdhcprouter) printf '%s\n' "$3" >> "${MOCK_IP_LOG:-/dev/null}" ;;
  -getinfo)
      # MOCK_IPV4_MODE=dhcp|manual — is_dhcp() 판정에 쓰인다
      if [ "${MOCK_IPV4_MODE:-dhcp}" = "dhcp" ]; then printf 'DHCP Configuration\n'
      else printf 'Manual Configuration with DHCP Router\n'; fi
      printf 'IP address: %s\nSubnet mask: 255.255.255.0\nRouter: 10.0.0.1\n' "${MOCK_CURRENT_IP:-10.0.0.9}" ;;
  -setdhcp)              printf 'dhcp\n' >> "${MOCK_IP_LOG:-/dev/null}" ;;
  -getautoproxyurl)      printf 'URL: %s\nEnabled: %s\n' "${MOCK_PAC:-(null)}" "${MOCK_PAC:+Yes}" ;;
  *) exit 1 ;;
esac
MOCK
cat > "$TMP/mock/ipconfig" <<'MOCK'
#!/bin/bash
# getifaddr → 현재 활성 IP (MOCK_CURRENT_IP), getsummary → SSID 폴백
case "$1" in
  getifaddr)  [ -n "${MOCK_CURRENT_IP:-}" ] && printf '%s\n' "$MOCK_CURRENT_IP" || exit 1 ;;
  getsummary) exit 1 ;;
  *) exit 1 ;;
esac
MOCK
cat > "$TMP/mock/scutil" <<'MOCK'
#!/bin/bash
# scutil 모의 — stdin 으로 "show State:/..." 를 받는다.
# MOCK_SCUTIL_SSID   : SSID_STR 로 내보낼 값 (빈 값이면 가려진 상태를 흉내)
# MOCK_SCUTIL_HEX    : ProfileID 에 실을 hex (빈 값이면 ProfileID 자체를 내지 않음)
IFS= read -r cmd
case "$cmd" in
  *AirPort*)
    printf '  BSSID : <data> 0x020000000000\n'
    printf '  SSID : <data> 0x00\n'
    printf '  SSID_STR : %s\n' "${MOCK_SCUTIL_SSID:-}"
    [ -n "${MOCK_SCUTIL_HEX:-}" ] && printf '  ProfileID : wifi.ssid.%s\n' "$MOCK_SCUTIL_HEX"
    ;;
esac
exit 0
MOCK
cat > "$TMP/mock/wdutil" <<'MOCK'
#!/bin/bash
# wdutil 모의 — MOCK_WDUTIL_SSID 가 있으면 그 값을, 없으면 가려진 값을 낸다
[ "$1" = "info" ] || exit 1
if [ -n "${MOCK_WDUTIL_SSID:-}" ]; then
  printf '    SSID : %s\n' "$MOCK_WDUTIL_SSID"
else
  printf '    SSID : <redacted>\n'
fi
exit 0
MOCK
cat > "$TMP/mock/id_root" <<'MOCK'
#!/bin/bash
echo 0
MOCK
cat > "$TMP/mock/id_user" <<'MOCK'
#!/bin/bash
echo 501
MOCK
chmod +x "$TMP/mock"/*

cat > "$TMP/netauto.json" <<'CONF'
{
  "version": 2,
  "options": { "notify": false, "no_wifi": "skip", "respect_manual": true, "ssid_retry": 1 },
  "profiles": [
    { "location": "Office",     "label": "Office", "icon": "building.2.fill" },
    { "location": "Automatic", "label": "Auto",  "icon": "wifi" }
  ],
  "rules": [
    { "ssid": "OfficeWiFi",  "location": "Office",     "ip_mode": "manual", "ip": "192.168.10.50" },
    { "ssid": "MSK 2G",   "location": "Automatic", "ip_mode": "keep",   "ip": "" },
    { "ssid": "home",     "location": "Automatic", "ip_mode": "dhcp",   "ip": "" },
    { "ssid": "legacy",   "location": "Office",                          "ip": "10.9.9.9" },
    { "ssid": "*",        "location": "Automatic", "ip_mode": "keep",   "ip": "" }
  ],
  "saved_ips": [
    { "label": "사무실 기본", "ip": "192.168.10.50" },
    { "label": "회의실",     "ip": "192.168.10.51" }
  ]
}
CONF

# 모의 환경으로 netauto 실행
run() { # 나머지 인자는 netauto 서브커맨드
  local idmock="$TMP/mock/id_user"
  [ -n "${AS_ROOT:-}" ] && idmock="$TMP/mock/id_root"
  NETAUTO_CONF="$TMP/netauto.json" \
  NETAUTO_STATE_DIR="$TMP/state" \
  NETAUTO_LOG="$TMP/netauto.log" \
  NETAUTO_NETWORKSETUP="$TMP/mock/networksetup" \
  NETAUTO_IPCONFIG="$TMP/mock/ipconfig" \
  NETAUTO_ID="$idmock" \
  NETAUTO_SCUTIL="$TMP/mock/scutil" NETAUTO_WDUTIL="$TMP/mock/wdutil" \
  MOCK_SCUTIL_SSID="${MOCK_SCUTIL_SSID:-}" MOCK_SCUTIL_HEX="${MOCK_SCUTIL_HEX:-}" \
  MOCK_WDUTIL_SSID="${MOCK_WDUTIL_SSID:-}" \
  MOCK_SSID="${MOCK_SSID:-}" MOCK_LOCATION="${MOCK_LOCATION:-Automatic}" \
  MOCK_POWER="${MOCK_POWER:-On}" MOCK_SWITCH_LOG="$TMP/switched" MOCK_IP_LOG="$TMP/ipset" \
  MOCK_CURRENT_IP="${MOCK_CURRENT_IP:-10.0.0.9}" MOCK_IPV4_MODE="${MOCK_IPV4_MODE:-dhcp}" \
  "$NETAUTO" "$@" 2>&1
}
reset() { rm -rf "$TMP/state" "$TMP/switched" "$TMP/ipset" "$TMP/netauto.log"; mkdir -p "$TMP/state"; }
ipset() { [ -r "$TMP/ipset" ] && tr '\n' ' ' < "$TMP/ipset" | sed 's/ $//' || printf ''; }
switched() { [ -r "$TMP/switched" ] && tr '\n' ' ' < "$TMP/switched" | sed 's/ $//' || printf ''; }
logtail() { [ -r "$TMP/netauto.log" ] && cat "$TMP/netauto.log" || printf ''; }

echo
echo "── 1. 규칙 조회 ──────────────────────────────────────────────"
reset
check "정확히 일치하는 SSID → 프로필 + 고정 IP" \
  "Wi-Fi 'OfficeWiFi' → 프로필 'Office' + IP 고정 192.168.10.50" "$(run test OfficeWiFi 2>/dev/null | head -1)"
check "규칙 없는 SSID → 와일드카드 기본값" \
  "Wi-Fi 'CafeWiFi' → 프로필 'Automatic' + IP 그대로" "$(run test CafeWiFi 2>/dev/null | head -1)"
check "공백 포함 SSID도 매칭" \
  "Wi-Fi 'MSK 2G' → 프로필 'Automatic' + IP 그대로"  "$(run test "MSK 2G" 2>/dev/null | head -1)"
check "자동(DHCP) 모드 규칙" \
  "Wi-Fi 'home' → 프로필 'Automatic' + IP 자동(DHCP)" "$(run test home 2>/dev/null | head -1)"
check "예전 설정(ip_mode 없음) → 고정으로 추론" \
  "Wi-Fi 'legacy' → 프로필 'Office' + IP 고정 10.9.9.9" "$(run test legacy 2>/dev/null | head -1)"

echo
echo "── 2. 멱등성 (자기 트리거 루프 차단) ─────────────────────────"
reset
out=$(MOCK_SSID=CafeWiFi MOCK_LOCATION=Automatic run apply)
has   "이미 일치하면 '변경 없음'" "변경 없음" "$(logtail)"
check "이미 일치하면 위치 전환을 시도하지 않음" "" "$(switched)"

echo
echo "── 3. 실제 전환 ──────────────────────────────────────────────"
reset
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "OfficeWiFi 접속 시 전환 로그" "→ 'Office'" "$(logtail)"
check "Office 위치로 전환 호출" "Office" "$(switched)"
reset
out=$(AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Office run apply)
check "다른 SSID면 Automatic으로 복귀" "Automatic" "$(switched)"

echo
echo "── 4. root 권한 없이 전환 시도 ───────────────────────────────"
reset
out=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "root 아니면 명확히 거부" "root 권한이 필요" "$out"
check "권한 없으면 전환하지 않음" "" "$(switched)"

echo
echo "── 5. 수동 변경 존중 ─────────────────────────────────────────"
reset
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null   # Office 적용됨
rm -f "$TMP/switched"
# 사용자가 같은 SSID에서 직접 Automatic으로 되돌린 상황
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "수동 변경을 감지" "수동 변경 감지" "$(logtail)"
check "수동 변경을 되돌리지 않음" "" "$(switched)"
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
check "반복 실행에도 전환 시도 없음" "" "$(switched)"
has   "status 가 수동 지정 유지를 표시" "수동 지정 유지 중" \
      "$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run status)"
check "감지 로그는 한 번만 (30초 주기 실행 시 로그 폭주 방지)" "1" \
      "$(logtail | grep -c '수동 변경 감지' | tr -d ' ')"
# 다른 네트워크로 이동 → 자동 재개
out=$(AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Automatic run apply)
# OfficeWiFi 으로 복귀 → 다시 자동 적용
rm -f "$TMP/switched"
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
check "다른 망 경유 후 복귀하면 자동 재개" "Office" "$(switched)"

echo
echo "── 6. --force 로 수동 지정 무시 ──────────────────────────────"
reset
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null  # 수동 감지
rm -f "$TMP/switched"
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply --force >/dev/null
check "--force 는 수동 지정을 무시하고 적용" "Office" "$(switched)"

echo
echo "── 7. 일시중지 / 비활성 ──────────────────────────────────────"
reset
run pause 30 >/dev/null
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "일시중지 중 건너뜀" "일시중지" "$(logtail)"
check "일시중지 중 전환 없음" "" "$(switched)"
run resume >/dev/null
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
check "resume 후 정상 적용" "Office" "$(switched)"
reset
printf '%s\n' "$(( $(date +%s) - 10 ))" > "$TMP/state/paused-until"   # 이미 만료된 일시중지
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
check "만료된 일시중지는 자동 해제" "Office" "$(switched)"
reset
run off >/dev/null
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "off 상태에서 건너뜀" "비활성" "$(logtail)"
check "off 상태에서 전환 없음" "" "$(switched)"
run on >/dev/null
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
check "on 후 정상 적용" "Office" "$(switched)"

echo
echo "── 8. Wi-Fi 전원 꺼짐 / 이름을 못 읽는 경우 ──────────────────"
reset
out=$(AS_ROOT=1 MOCK_POWER=Off MOCK_SSID="" MOCK_LOCATION=Office run apply)
has   "전원 꺼짐은 미연결로 기록" "Wi-Fi 미연결" "$(logtail)"
check "전원 꺼짐이면 전환 없음" "" "$(switched)"
reset
out=$(AS_ROOT=1 MOCK_POWER=Off MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
check "전원 꺼짐이면 SSID 가 있어도 전환 없음" "" "$(switched)"
reset
# Wi-Fi 는 켜져 있는데 모든 방법이 이름을 못 읽는 상황 (macOS 15+ 위치 권한)
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Office run apply)
has   "켜져 있지만 이름을 못 읽으면 그렇게 기록" "이름을 읽을 수 없음" "$(logtail)"
check "이름을 못 읽으면 전환하지 않음" "" "$(switched)"

echo
echo "── 8b. SSID 감지 대체 경로 ───────────────────────────────────"
reset
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_SCUTIL_SSID=OfficeWiFi \
      MOCK_LOCATION=Automatic run apply)
check "scutil SSID_STR 로 감지 → 전환" "Office" "$(switched)"
reset
# SSID_STR 까지 가려져도 ProfileID hex 로 복호한다
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_SCUTIL_SSID="" \
      MOCK_SCUTIL_HEX="$(printf 'OfficeWiFi' | xxd -p)" MOCK_LOCATION=Automatic run apply)
check "ProfileID hex 복호로 감지 → 전환" "Office" "$(switched)"
reset
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_WDUTIL_SSID=OfficeWiFi \
      MOCK_LOCATION=Automatic run apply)
check "wdutil 로 감지 → 전환" "Office" "$(switched)"
reset
# 가려진 값(<redacted>)은 SSID 로 받아들이지 않는다
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_SCUTIL_SSID="<redacted>" \
      MOCK_LOCATION=Automatic run apply)
has   "가려진 값은 거부" "이름을 읽을 수 없음" "$(logtail)"
check "가려진 값으로 전환하지 않음" "" "$(switched)"

echo
echo "── 8c. 앱이 넘겨주는 SSID (macOS 15+ 유일한 경로) ────────────"
# macOS 15+ 에서는 데몬이 어떤 방법으로도 SSID 를 읽을 수 없다.
# 사용자 권한으로 도는 앱이 CoreWLAN 으로 읽어 파일에 적어주고, 데몬은 그걸 쓴다.
reset
printf '%s\nOfficeWiFi\nauthorizedAlways\n' "$(date +%s)" > "$TMP/state/ssid"
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Automatic run apply)
check "앱이 적어준 이름으로 전환" "Office" "$(switched)"
reset
# 시스템 방법이 살아 있어도 앱 값을 먼저 쓴다 (가장 신뢰할 수 있는 출처)
printf '%s\nOfficeWiFi\n' "$(date +%s)" > "$TMP/state/ssid"
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="MSK 2G" MOCK_LOCATION=Automatic run apply)
check "앱 값이 시스템 방법보다 우선" "Office" "$(switched)"
reset
# 앱이 꺼져 오래된 값이 남아 있으면 쓰지 않는다 (엉뚱한 프로필 적용 방지)
printf '%s\nOfficeWiFi\n' "$(( $(date +%s) - 600 ))" > "$TMP/state/ssid"
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Automatic run apply)
has   "오래된 값은 버린다" "이름을 읽을 수 없음" "$(logtail)"
check "오래된 값으로 전환하지 않음" "" "$(switched)"
reset
# 앱은 살아 있지만 권한이 없어 이름이 빈 경우
printf '%s\n\nnotDetermined\n' "$(date +%s)" > "$TMP/state/ssid"
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Automatic run apply)
has   "이름이 비면 감지 실패로 다룬다" "이름을 읽을 수 없음" "$(logtail)"
check "빈 이름으로 전환하지 않음" "" "$(switched)"
reset
# 깨진 파일은 무시한다
printf 'not-a-timestamp\nOfficeWiFi\n' > "$TMP/state/ssid"
out=$(AS_ROOT=1 MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Automatic run apply)
check "깨진 파일로 전환하지 않음" "" "$(switched)"

echo
echo "── 9. 없는 위치를 가리키는 규칙 ──────────────────────────────"
reset
printf '{"options":{"notify":false,"ssid_retry":1},"rules":[{"ssid":"ghostnet","location":"NoSuchLocation","ip_mode":"keep","ip":""},{"ssid":"*","location":"Automatic","ip_mode":"keep","ip":""}]}' > "$TMP/netauto.bad.json"
out=$(NETAUTO_CONF="$TMP/netauto.bad.json" NETAUTO_STATE_DIR="$TMP/state" \
      NETAUTO_LOG="$TMP/netauto.log" NETAUTO_NETWORKSETUP="$TMP/mock/networksetup" \
      NETAUTO_IPCONFIG="$TMP/mock/ipconfig" NETAUTO_ID="$TMP/mock/id_root" \
      MOCK_SSID=ghostnet MOCK_LOCATION=Automatic MOCK_POWER=On \
      MOCK_SWITCH_LOG="$TMP/switched" MOCK_CURRENT_IP=10.0.0.9 "$NETAUTO" apply 2>&1)
has   "존재하지 않는 위치는 명확히 오류" "가 없습니다" "$out"
check "오류 시 전환하지 않음" "" "$(switched)"
# (설정 파일 원복 — 위 bad 테스트가 별도 파일을 썼으므로 그대로 유지됨)

echo
echo "── 10. status 출력 ───────────────────────────────────────────"
reset
out=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run status)
has "status 에 현재 SSID"    "OfficeWiFi"   "$out"
has "status 에 기대 위치"    "Office"     "$out"
has "status 에 규칙 목록"    "→ Office"   "$out"
has "status 에 저장된 IP"    "회의실"     "$out"
has "status 에 프로필 이름표" "(Auto)"    "$out"

echo
echo "── 11. 요청 큐 (GUI → root 데몬) ─────────────────────────────"
reset; mkdir -p "$TMP/state/queue"
# 일시중지 중에도 사용자가 메뉴에서 직접 누른 요청은 우선한다
run pause 60 >/dev/null
printf 'force\n' > "$TMP/state/queue/req1"
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
check "force 요청은 일시중지보다 우선" "Office" "$(switched)"
check "처리한 요청 파일은 반드시 삭제 (launchd 무한 재기동 방지)" "0" \
      "$(ls -1 "$TMP/state/queue" 2>/dev/null | wc -l | tr -d ' ')"

reset; mkdir -p "$TMP/state/queue"
printf 'pick Office\n' > "$TMP/state/queue/req1"
AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
check "pick 요청은 규칙을 무시하고 그 위치로" "Office" "$(switched)"
check "pick 은 수동 지정으로 기록" "CafeWiFi" \
      "$(awk -F= '$1=="override_ssid"{print $2}' "$TMP/state/state")"
rm -f "$TMP/switched"
AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Office run apply >/dev/null
check "pick 후 자동이 되돌리지 않음" "" "$(switched)"

reset; mkdir -p "$TMP/state/queue"
printf 'rm -rf /\n' > "$TMP/state/queue/evil"
AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
has   "알 수 없는 요청은 무시하고 기록" "알 수 없는 요청 무시" "$(logtail)"
check "알 수 없는 요청도 삭제" "0" \
      "$(ls -1 "$TMP/state/queue" 2>/dev/null | wc -l | tr -d ' ')"

reset; mkdir -p "$TMP/state/queue"
# 규칙만으로는 전환이 없는 조합(CafeWiFi → Automatic, 이미 일치)을 써서
# .part 를 읽었을 때만 전환이 발생하도록 만든다.
printf 'pick Office\n' > "$TMP/state/queue/req.part"
AS_ROOT=1 MOCK_SSID=CafeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
check "쓰는 중인 .part 파일은 읽지 않음" "" "$(switched)"
check ".part 파일은 큐에 남겨둠 (다음 회차에 처리)" "1" \
      "$(ls -1 "$TMP/state/queue" 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "── 12. root 아닐 때 큐로 위임 ────────────────────────────────"
reset; mkdir -p "$TMP/state/queue"
out=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "큐가 있으면 요청을 전달" "요청을 전달했습니다" "$out"
check "요청 파일이 큐에 생성됨" "1" \
      "$(ls -1 "$TMP/state/queue" 2>/dev/null | wc -l | tr -d ' ')"
check "직접 전환하지는 않음" "" "$(switched)"
reset   # 큐 디렉터리 없음
out=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply)
has   "큐가 없으면 root 필요 안내" "root 권한이 필요" "$out"

echo
echo "── 13. status --json ─────────────────────────────────────────"
reset
json=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office MOCK_PAC="http://x/proxy.pac" run status --json)
python3 -c "import json,sys; json.loads(sys.stdin.read())" <<< "$json" \
  && ok "유효한 JSON 을 출력" || no "유효한 JSON 을 출력" "파싱 성공" "파싱 실패"
jget() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" <<< "$json"; }
check "ssid 필드"              "OfficeWiFi"  "$(jget ssid)"
check "location 필드"          "Office"    "$(jget location)"
check "expected_location 필드" "Office"    "$(jget expected_location)"
check "default_location 필드"  "Automatic" "$(jget default_location)"
check "ipv4_address 파싱"      "10.0.0.9" "$(jget ipv4_address)"
check "pac_url 파싱"           "http://x/proxy.pac" "$(jget pac_url)"
check "locations 목록"         "['Office', 'Automatic']" "$(jget locations)"
check "expected_ip_mode 필드"  "manual"   "$(jget expected_ip_mode)"

# 상태 문자열이 앱의 아이콘 분기와 일치해야 한다
reset
json=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run status --json); check "state=auto"     "auto"     "$(jget state)"
reset; run off >/dev/null
json=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run status --json); check "state=disabled" "disabled" "$(jget state)"
reset; run pause 30 >/dev/null
json=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run status --json); check "state=paused"   "paused"   "$(jget state)"
reset
json=$(MOCK_POWER=Off MOCK_SSID="" MOCK_LOCATION=Office run status --json)
check "state=nowifi (전원 꺼짐)" "nowifi" "$(jget state)"
reset
json=$(MOCK_POWER=On MOCK_SSID="" MOCK_LOCATION=Office run status --json)
check "state=nossid (켜졌지만 이름 못 읽음)" "nossid" "$(jget state)"
reset
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run apply >/dev/null
json=$(MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic run status --json); check "state=manual" "manual" "$(jget state)"

echo
echo "── 14. 특수문자 SSID 의 JSON 이스케이프 ──────────────────────"
reset
json=$(MOCK_SSID='Cafe "Best" \ Wifi' MOCK_LOCATION=Automatic run status --json)
python3 -c "import json,sys; json.loads(sys.stdin.read())" <<< "$json" \
  && ok "따옴표·백슬래시 포함 SSID 도 유효한 JSON" \
  || no "따옴표·백슬래시 포함 SSID 도 유효한 JSON" "파싱 성공" "파싱 실패"
check "SSID 값이 온전히 보존" 'Cafe "Best" \ Wifi' "$(jget ssid)"

echo
echo "── 15. 규칙의 IP 방식 (그대로 / 자동 / 고정) ────────────────"
reset
# 고정: 현재 IP 가 다르면 적용
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic MOCK_CURRENT_IP=10.0.0.9 run apply)
check "고정 모드 → 그 주소로 설정" "192.168.10.50" "$(ipset)"
reset
# 고정: 이미 그 주소이고 DHCP 가 아니면 아무것도 쓰지 않는다
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office \
      MOCK_CURRENT_IP=192.168.10.50 MOCK_IPV4_MODE=manual run apply)
check "고정 모드 + 이미 동일 → 쓰지 않음" "" "$(ipset)"
check "이때 프로필 전환도 없음" "" "$(switched)"
reset
# 고정: 주소는 같지만 아직 DHCP 라면 고정으로 바꿔야 한다
out=$(AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office \
      MOCK_CURRENT_IP=192.168.10.50 MOCK_IPV4_MODE=dhcp run apply)
check "주소가 같아도 DHCP면 고정으로 전환" "192.168.10.50" "$(ipset)"
reset
# 자동: 현재 수동이면 DHCP 로 되돌린다
out=$(AS_ROOT=1 MOCK_SSID=home MOCK_LOCATION=Automatic MOCK_IPV4_MODE=manual run apply)
check "자동 모드 → DHCP 로 전환" "dhcp" "$(ipset)"
reset
# 자동: 이미 DHCP 면 아무것도 쓰지 않는다 (자기 트리거 루프 차단)
out=$(AS_ROOT=1 MOCK_SSID=home MOCK_LOCATION=Automatic MOCK_IPV4_MODE=dhcp run apply)
check "자동 모드 + 이미 DHCP → 쓰지 않음" "" "$(ipset)"
reset
# 그대로: 어떤 상태여도 IP 를 건드리지 않는다
out=$(AS_ROOT=1 MOCK_SSID="MSK 2G" MOCK_LOCATION=Automatic MOCK_IPV4_MODE=manual run apply)
check "그대로 모드 → IP 를 건드리지 않음" "" "$(ipset)"

echo
echo "── 16. 메뉴에서 IP 직접 바꾸기 (setip / setdhcp) ─────────────"
reset
out=$(AS_ROOT=1 MOCK_CURRENT_IP=10.0.0.9 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run setip 192.168.10.51)
check "setip 이 그 주소로 고정" "192.168.10.51" "$(ipset)"
reset
out=$(AS_ROOT=1 MOCK_IPV4_MODE=manual MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run setdhcp)
check "setdhcp 가 자동으로 전환" "dhcp" "$(ipset)"
reset
out=$(AS_ROOT=1 MOCK_IPV4_MODE=dhcp run setdhcp)
check "이미 자동이면 setdhcp 는 쓰지 않음" "" "$(ipset)"
reset
out=$(AS_ROOT=1 MOCK_CURRENT_IP=10.0.0.9 run setip "1.2.3; rm -rf /")
has  "IP 형식 검증으로 이상한 입력 거부" "IP 형식이 아닙니다" "$out"
check "거부된 입력은 적용되지 않음" "" "$(ipset)"
reset; mkdir -p "$TMP/state/queue"
out=$(MOCK_CURRENT_IP=10.0.0.9 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office run setip 192.168.10.51)
has  "root 아니면 큐로 위임" "요청을 전달했습니다" "$out"
check "직접 적용하지 않음" "" "$(ipset)"
reset; mkdir -p "$TMP/state/queue"
printf 'setip 192.168.10.52\n' > "$TMP/state/queue/req1"
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office MOCK_CURRENT_IP=10.0.0.9 run apply >/dev/null
check "큐의 setip 요청 처리" "192.168.10.52" "$(ipset)"
reset; mkdir -p "$TMP/state/queue"
printf 'setdhcp\n' > "$TMP/state/queue/req1"
AS_ROOT=1 MOCK_SSID=OfficeWiFi MOCK_LOCATION=Office MOCK_IPV4_MODE=manual run apply >/dev/null
check "큐의 setdhcp 요청 처리" "dhcp" "$(ipset)"

echo "── 17. 깨진 설정 파일 ────────────────────────────────────────"
reset
printf '{ "rules": [ broken' > "$TMP/netauto.broken.json"
out=$(NETAUTO_CONF="$TMP/netauto.broken.json" NETAUTO_STATE_DIR="$TMP/state" \
      NETAUTO_LOG="$TMP/netauto.log" NETAUTO_NETWORKSETUP="$TMP/mock/networksetup" \
      NETAUTO_IPCONFIG="$TMP/mock/ipconfig" NETAUTO_ID="$TMP/mock/id_root" \
      MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic MOCK_CURRENT_IP=10.0.0.9 \
      MOCK_SWITCH_LOG="$TMP/switched" MOCK_IP_LOG="$TMP/ipset" "$NETAUTO" apply 2>&1)
check "깨진 설정이면 아무것도 바꾸지 않음" "" "$(switched)$(ipset)"
json=$(NETAUTO_CONF="$TMP/netauto.broken.json" NETAUTO_STATE_DIR="$TMP/state" \
      NETAUTO_LOG="$TMP/netauto.log" NETAUTO_NETWORKSETUP="$TMP/mock/networksetup" \
      NETAUTO_IPCONFIG="$TMP/mock/ipconfig" NETAUTO_ID="$TMP/mock/id_user" \
      MOCK_SSID=OfficeWiFi MOCK_LOCATION=Automatic "$NETAUTO" status --json 2>/dev/null)
python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d['conf_valid']==False else 1)" <<< "$json" \
  && ok "깨진 설정을 conf_valid=false 로 앱에 알림" \
  || no "깨진 설정을 conf_valid=false 로 앱에 알림" "false" "true 또는 파싱 실패"

echo
printf '─────────────────────────────────────────────────────────────\n'
printf '통과 %d · 실패 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
