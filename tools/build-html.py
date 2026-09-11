#!/usr/bin/env python3
"""설치 화면 HTML 을 템플릿에서 생성한다.

{{ICON:key}}  → 앱에서 쓰는 SF Symbol 을 PNG 로 구워 base64 로 심는다.
                라이트/다크 두 버전을 넣고 CSS 로 전환한다.
{{ICON_CSS}}  → 위 아이콘용 CSS
{{VERSION}}   → 버전 문자열

사용법: build-html.py <renderer> <version> <out_dir> <template...>
"""
import base64
import subprocess
import sys
import tempfile
from pathlib import Path

# 설치 화면에서 쓰는 아이콘 — 앱의 Model.symbol 과 같은 심볼이어야 한다
ICONS = {
    "office":  "building.2.fill",
    "auto":    "globe",
    "manual":  "hand.raised.fill",
    "paused":  "pause.circle",
    "off":     "nosign",
    "nowifi":  "wifi.slash",
}
POINTS = "16"
INK_LIGHT = "1D1D1F"   # 라이트 모드 배경용 (거의 검정)
INK_DARK = "F5F5F7"    # 다크 모드 배경용 (거의 흰색)

ICON_CSS = """
  .ic { display: inline-flex; align-items: center; }
  .ic img { width: 16px; height: 16px; }
  .ic .d { display: none; }
  @media (prefers-color-scheme: dark) {
    .ic .l { display: none; }
    .ic .d { display: inline; }
  }
"""


def render(renderer: str, symbol: str, ink: str, tmp: Path) -> str:
    out = tmp / f"{symbol}-{ink}.png"
    subprocess.run([renderer, symbol, POINTS, ink, str(out)], check=True)
    return base64.b64encode(out.read_bytes()).decode("ascii")


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    renderer, version, out_dir = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    templates = sys.argv[4:]
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        tags = {}
        for key, symbol in ICONS.items():
            light = render(renderer, symbol, INK_LIGHT, tmp)
            dark = render(renderer, symbol, INK_DARK, tmp)
            tags[key] = (
                f'<span class="ic">'
                f'<img class="l" alt="" src="data:image/png;base64,{light}">'
                f'<img class="d" alt="" src="data:image/png;base64,{dark}">'
                f'</span>'
            )

        for t in templates:
            src = Path(t)
            html = src.read_text(encoding="utf-8")
            html = html.replace("{{ICON_CSS}}", ICON_CSS.strip())
            html = html.replace("{{VERSION}}", version)
            for key, tag in tags.items():
                html = html.replace(f"{{{{ICON:{key}}}}}", tag)

            # 치환되지 않은 자리표시자가 남아 있으면 빌드를 멈춘다
            if "{{" in html:
                leftover = html[html.index("{{"):][:40]
                print(f"치환되지 않은 자리표시자: {leftover}", file=sys.stderr)
                return 1

            dest = out_dir / src.name.replace(".html.in", ".html")
            dest.write_text(html, encoding="utf-8")
            print(f"   {dest.name}  ({len(html) // 1024}KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
