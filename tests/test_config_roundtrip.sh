#!/bin/bash
# 통합 테스트: 설정 창(Swift)이 저장한 JSON 을 데몬(bash/plutil)이 그대로 읽는가.
# 두 언어가 같은 파일을 공유하므로 이 왕복이 깨지면 설정이 조용히 무시된다.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  ✗ %s\n     기대: %s\n     실제: %s\n' "$1" "$2" "$3"; }
check() { [ "$2" = "$3" ] && ok "$1" || no "$1" "$2" "$3"; }

echo
echo "── 설정 파일 왕복 (Swift ↔ bash) ────────────────────────────"

mkdir -p "$TMP/rt"
cat > "$TMP/rt/main.swift" <<'SW'
import Foundation
var c = Config()
c.options = .init(notify: false, respect_manual: true, menubar_text: true, no_wifi: "skip")
c.profiles = [
    .init(location: "Office",     label: "Office", icon: "building.2.fill"),
    .init(location: "Automatic", label: "Auto",  icon: "wifi"),
]
c.rules = [
    .init(ssid: "OfficeWiFi",    location: "Office",     ip_mode: .manual, ip: "192.168.10.50"),
    .init(ssid: "MSK 2G",     location: "Automatic", ip_mode: .dhcp,   ip: ""),
    .init(ssid: "카페 \"별\"", location: "Automatic", ip_mode: .keep,   ip: ""),
    .init(ssid: "*",          location: "Automatic", ip_mode: .dhcp,   ip: ""),
]
// 예전 형식(ip_mode 없음)이 고정으로 추론되는지도 확인한다
let legacy = #"{"version":2,"rules":[{"ssid":"old","location":"Office","ip":"10.1.1.1"},{"ssid":"none","location":"Office","ip":""}]}"#
let lp = CommandLine.arguments[1] + ".legacy"
try? legacy.write(toFile: lp, atomically: true, encoding: .utf8)
if let lc = ConfigStore.load(lp) {
    print(lc.rules[0].mode == .manual && lc.rules[1].mode == .keep ? "LEGACY_OK" : "LEGACY_BAD")
} else { print("LEGACY_LOAD_FAIL") }
c.saved_ips = [
    .init(label: "4층 내 자리", ip: "192.168.10.50"),
    .init(label: "회의실",      ip: "192.168.10.51"),
]
let path = CommandLine.arguments[1]
if let e = ConfigStore.save(c, to: path) { print("SAVE_FAIL \(e)"); exit(1) }
guard let back = ConfigStore.load(path) else { print("LOAD_FAIL"); exit(1) }
print(back.rules == c.rules && back.saved_ips == c.saved_ips
      && back.profiles == c.profiles
      && back.options.menubar_text == c.options.menubar_text ? "SWIFT_OK" : "SWIFT_MISMATCH")
SW

if ! swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
      -target "$(uname -m)-apple-macos13.0" \
      -o "$TMP/rt/rt" "$ROOT/app/NetautoBar/Core.swift" "$TMP/rt/main.swift" 2>"$TMP/rt/err"; then
  no "Swift 테스트 하네스 컴파일" "성공" "$(head -3 "$TMP/rt/err")"
  printf '\n통과 %d · 실패 %d\n' "$PASS" "$FAIL"; exit 1
fi
ok "Swift 테스트 하네스 컴파일"

out=$("$TMP/rt/rt" "$TMP/rt/config.json" 2>&1)
check "예전 형식(ip_mode 없음) 하위호환 추론" "LEGACY_OK" "$(printf '%s' "$out" | sed -n '1p')"
check "Swift 저장 → 되읽기 일치 (id 제외한 내용 비교)" "SWIFT_OK" "$(printf '%s' "$out" | sed -n '2p')"

# ── 셸(plutil) 쪽에서 같은 파일을 읽는다 ──
pl() { /usr/bin/plutil -extract "$1" raw -o - "$TMP/rt/config.json" 2>&1; }
check "options.notify"        "false"                "$(pl options.notify)"
check "options.menubar_text"  "true"                 "$(pl options.menubar_text)"
check "rules.0.ssid"          "OfficeWiFi"              "$(pl rules.0.ssid)"
check "rules.0.ip"            "192.168.10.50"        "$(pl rules.0.ip)"
check "rules.0.ip_mode"       "manual"               "$(pl rules.0.ip_mode)"
check "rules.1.ip_mode"       "dhcp"                 "$(pl rules.1.ip_mode)"
check "rules.2.ip_mode"       "keep"                 "$(pl rules.2.ip_mode)"
check "공백 포함 SSID"         "MSK 2G"               "$(pl rules.1.ssid)"
check "따옴표 포함 SSID 보존"  '카페 "별"'            "$(pl rules.2.ssid)"
check "한글 label"            "회의실"                "$(pl saved_ips.1.label)"
check "profiles.0.label"      "Office"                "$(pl profiles.0.label)"

# ── netauto 가 그 설정으로 규칙을 해석하는지 ──
nr() { NETAUTO_CONF="$TMP/rt/config.json" NETAUTO_STATE_DIR="$TMP/rt/state" \
       NETAUTO_LOG="$TMP/rt/log" "$ROOT/bin/netauto" "$@" 2>&1; }
check "데몬이 고정 IP 규칙을 해석"  "Wi-Fi 'OfficeWiFi' → 프로필 'Office' + IP 고정 192.168.10.50" \
      "$(nr test OfficeWiFi 2>/dev/null | head -1)"
check "데몬이 자동(DHCP) 규칙을 해석" "Wi-Fi '아무거나' → 프로필 'Automatic' + IP 자동(DHCP)" \
      "$(nr test '아무거나' 2>/dev/null | head -1)"
check "데몬이 따옴표 SSID 를 해석" "Wi-Fi '카페 \"별\"' → 프로필 'Automatic' + IP 그대로" \
      "$(nr test '카페 "별"' 2>/dev/null | head -1)"

echo
printf '─────────────────────────────────────────────────────────────\n'
printf '통과 %d · 실패 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
