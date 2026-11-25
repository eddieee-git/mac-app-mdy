#!/bin/zsh
# 자체 점검: 번역 빠짐, 공통 파일, 미리보기 JS 문법, 앱 컴파일, 편집기 동작 시험.
# 사용: ./scripts/test.sh
set -e
cd "$(dirname "$0")/.."

echo "▸ 번역"
missing=$(python3 -I scripts/l10n.py keys 2>/dev/null | grep -c '^빠짐' || true)
python3 -I scripts/l10n.py keys | tail -1
if [[ "$missing" != "0" ]]; then
    python3 -I scripts/l10n.py keys | grep '^빠짐'
    echo "✗ 빠진 영어 번역이 있어요 (Resources/en.json)"
    exit 1
fi

echo "▸ 공통 파일"
if [[ -d ../mac-app/shared ]]; then
    for f in AppUpdater.swift AppAbout.swift; do
        cmp -s "../mac-app/shared/$f" "Sources/$f" || { echo "✗ Sources/$f 가 mac-app/shared 원본과 달라요"; exit 1; }
    done
    echo "mac-app/shared 와 같아요"
else
    echo "(../mac-app 없음 — 건너뜀)"
fi

echo "▸ 미리보기 JS 문법"
for f in Resources/markdown.js Resources/highlight.js Resources/convert.js; do
    osascript -l JavaScript -e "new Function($(python3 -I -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read()))' "$f"))" >/dev/null \
        || { echo "✗ $f 문법 오류"; exit 1; }
done
echo "문법 이상 없어요"

echo "▸ 컴파일"
swiftc -parse-as-library -swift-version 5 -typecheck Sources/*.swift
swiftc -parse-as-library -swift-version 5 -typecheck -application-extension -module-name MdyQuickLook QuickLook/*.swift
echo "컴파일 이상 없어요"

echo "▸ 편집기 동작 시험"
out=$(mktemp -d -t mdy-test)
trap 'rm -rf "$out"' EXIT
sources=(${(f)"$(ls Sources/*.swift | grep -v MdyApp.swift)"})
swiftc -parse-as-library -swift-version 5 -o "$out/mdy-test" $sources Tests/harness/main.swift
"$out/mdy-test" Resources/Help.md "$out" | grep -E '✗|got:|want:|PASSED|FAILED'
