#!/bin/bash
# 수식(KaTeX)·다이어그램(Mermaid)을 앱 안에 넣어, 인터넷 없이도 그리게 합니다.
# 둘 다 MIT 라이선스이며, 받은 파일은 Resources/vendor 에 저장됩니다. 받은 뒤 ./build.sh install
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Resources/vendor"
KATEX="https://cdn.jsdelivr.net/npm/katex@0.16.11"
MERMAID="https://cdn.jsdelivr.net/npm/mermaid@11.4.1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT" "$TMP/fonts"

echo "▸ KaTeX"
curl -fsSL "$KATEX/dist/katex.min.js" -o "$OUT/katex.min.js"
curl -fsSL "$KATEX/dist/katex.min.css" -o "$TMP/katex.min.css"
curl -fsSL "$KATEX/LICENSE" -o "$OUT/KATEX-LICENSE"
for font in $(grep -o 'fonts/KaTeX_[A-Za-z0-9_-]*\.woff2' "$TMP/katex.min.css" | sort -u); do
  curl -fsSL "$KATEX/dist/$font" -o "$TMP/$font"
done

# 글꼴을 CSS 안에 넣어 파일 하나로 만듭니다 (미리보기는 앱 폴더의 파일을 직접 읽을 수 없으므로).
python3 -I - "$TMP" "$OUT/katex.css" <<'PY'
import base64, re, sys, pathlib
tmp, out = pathlib.Path(sys.argv[1]), sys.argv[2]
css = (tmp / "katex.min.css").read_text()
def inline(m):
    data = base64.b64encode((tmp / "fonts" / (m.group(1) + ".woff2")).read_bytes()).decode()
    return f'src:url(data:font/woff2;base64,{data}) format("woff2")'
css = re.sub(r'src:url\(fonts/(KaTeX_[\w-]+)\.woff2\) format\("woff2"\)[^;}]*', inline, css)
pathlib.Path(out).write_text(css)
PY

echo "▸ Mermaid"
curl -fsSL "$MERMAID/dist/mermaid.min.js" -o "$OUT/mermaid.min.js"
curl -fsSL "$MERMAID/LICENSE" -o "$OUT/MERMAID-LICENSE"

ls -la "$OUT"
echo "✓ 받기 완료 — ./build.sh install 로 앱에 넣으세요."
