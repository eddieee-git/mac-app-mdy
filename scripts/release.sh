#!/bin/zsh
# GitHub 릴리스를 만들어요: 점검 → 빌드(dmg + .sig) → 태그 → 릴리스에 dmg·서명 첨부.
# 버전은 Resources/Info.plist 의 CFBundleShortVersionString, 릴리스 노트는 docs/releases/v<버전>.md.
# 사용: ./scripts/release.sh   (main 브랜치에서, 하기 전에 꼭 확인받기 — 자동 업데이트로 사용자에게 바로 가요)
set -e
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
notes="docs/releases/$tag.md"
dmg="build/Mdy-$version.dmg"

[[ -f "$notes" ]] || { echo "릴리스 노트가 없어요: $notes"; exit 1; }
grep -q "^## $version (20" CHANGELOG.md || { echo "CHANGELOG.md 에 '## $version (날짜)' 줄이 없어요"; exit 1; }
grep -q "^## $version (20" CHANGELOG.en.md || { echo "CHANGELOG.en.md 에 '## $version (date)' 줄이 없어요"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "main 브랜치에서만 릴리스해요"; exit 1; }
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "이미 있는 태그예요: $tag (Info.plist 의 버전을 올려 주세요)"
    exit 1
fi
[[ -z "$(git status --porcelain)" ]] || { echo "커밋하지 않은 변경이 있어요. 먼저 커밋해 주세요."; exit 1; }

./scripts/test.sh
./scripts/build-app.sh
[[ -f "$dmg.sig" ]] || { echo "업데이트 서명(.sig)이 없어요: 키체인의 'Mdy Update Signing' 키를 확인해 주세요"; exit 1; }

git tag -a "$tag" -m "Mdy $version"
git push origin "$tag"
gh release create "$tag" "$dmg" "$dmg.sig" --title "Mdy $version" --notes-file "$notes"
echo "릴리스를 만들었어요: $tag"
