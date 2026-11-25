#!/bin/bash
# Mdy.app 빌드 (Xcode 없이 Command Line Tools 만으로)
#   ./build.sh            → build/Mdy.app (이 Mac 의 CPU 용)
#   ./build.sh install    → 빌드 후 /Applications 에 설치, .md 기본 앱 지정, 훑어보기 등록
#   ./build.sh dist       → Apple 실리콘 + Intel 유니버설 빌드를 build/Mdy-<버전>.dmg 로 묶고,
#                           업데이트 서명 키가 키체인에 있으면 Mdy-<버전>.dmg.sig 도 만들어요.
#                           MDY_SIGN_IDENTITY="Developer ID Application: …" 를 주면 Apple 서명까지 해요.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP="build/Mdy.app"
QL="$APP/Contents/PlugIns/MdyQuickLook.appex"
ICONSET="build/AppIcon.iconset"
ICNS="build/AppIcon.icns"
MIN_OS="14.0"
IDENTITY="${MDY_SIGN_IDENTITY:--}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"

if [[ "$MODE" == "dist" ]]; then ARCHS=(arm64 x86_64); else ARCHS=("$(uname -m)"); fi

# compile <출력 파일> <추가 swiftc 옵션…> -- <소스…>
compile() {
  local out="$1"; shift
  local opts=() parts=()
  while [[ "$1" != "--" ]]; do opts+=("$1"); shift; done; shift
  for arch in "${ARCHS[@]}"; do
    swiftc -O -parse-as-library -swift-version 5 -target "$arch-apple-macos$MIN_OS" \
      ${opts[@]+"${opts[@]}"} "$@" -o "build/obj-$arch-$(basename "$out")"
    parts+=("build/obj-$arch-$(basename "$out")")
  done
  lipo -create "${parts[@]}" -output "$out"
  rm -f "${parts[@]}"
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ko.lproj" "$APP/Contents/Resources/en.lproj" \
         "$QL/Contents/MacOS" "$QL/Contents/Resources"

echo "▸ 컴파일: 앱 $VERSION (${ARCHS[*]})"
compile "$APP/Contents/MacOS/Mdy" -- Sources/*.swift

echo "▸ 컴파일: 훑어보기 확장"
compile "$QL/Contents/MacOS/MdyQuickLook" -application-extension -module-name MdyQuickLook \
  -Xlinker -e -Xlinker _NSExtensionMain -- QuickLook/*.swift

echo "▸ 리소스"
WEB=(Resources/preview.html Resources/markdown.js Resources/highlight.js)
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "${WEB[@]}" Resources/convert.js Resources/Help.md Resources/en.json "$APP/Contents/Resources/"
[[ -f Resources/Help.en.md ]] && cp Resources/Help.en.md "$APP/Contents/Resources/"
[[ -d Resources/Templates ]] && cp -R Resources/Templates "$APP/Contents/Resources/"
[[ -d Resources/vendor ]] && cp -R Resources/vendor "$APP/Contents/Resources/"
cp Resources/en.lproj/InfoPlist.strings "$APP/Contents/Resources/en.lproj/"
cp QuickLook/Info.plist "$QL/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$QL/Contents/Info.plist"
cp "${WEB[@]}" "$QL/Contents/Resources/"
mkdir -p "$QL/Contents/Resources/en.lproj" && cp QuickLook/en.lproj/InfoPlist.strings "$QL/Contents/Resources/en.lproj/"
if [[ ! -f "$ICNS" || scripts/make_icon.swift -nt "$ICNS" ]]; then
  rm -rf "$ICONSET"
  swift scripts/make_icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ 서명 (${IDENTITY/#-/ad-hoc}, hardened runtime)"
# hardened runtime 은 ad-hoc 서명에도 켜요: 다른 프로그램이 Mdy 안에 코드를 끼워 넣지 못하게.
SIGN_OPTS=(--force --sign "$IDENTITY" --options runtime)
[[ "$IDENTITY" != "-" ]] && SIGN_OPTS+=(--timestamp)
codesign "${SIGN_OPTS[@]}" --entitlements QuickLook/QuickLook.entitlements "$QL"
codesign "${SIGN_OPTS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP"

if [[ "$MODE" == "install" ]]; then
  DEST="/Applications/Mdy.app"
  echo "▸ 설치: $DEST"
  osascript -e 'tell application id "com.eddieee.Mdy" to quit' 2>/dev/null || true
  osascript -e 'tell application id "app.mdy.Mdy" to quit' 2>/dev/null || true
  if pgrep -f "/Applications/Mdy.app/Contents/MacOS/Mdy" >/dev/null; then
    echo "  ※ Mdy 가 아직 켜져 있어요(저장 안 한 문서가 있을 수 있어요). Mdy 를 종료한 뒤 다시 열면 새 버전이 돼요."
  fi
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  pluginkit -a "$DEST/Contents/PlugIns/MdyQuickLook.appex" 2>/dev/null || true
  qlmanage -r >/dev/null 2>&1 || true
  echo "▸ .md 파일 기본 앱으로 지정"
  swift scripts/set_default.swift "$DEST"
  echo "✓ 설치 완료 — Finder 에서 .md 파일을 더블클릭하면 Mdy 로 열리고, 스페이스 바로 훑어볼 수 있어요."
fi

if [[ "$MODE" == "dist" ]]; then
  DMG="build/Mdy-$VERSION.dmg"
  STAGING="$(mktemp -d)"
  trap 'rm -rf "$STAGING"' EXIT
  ditto "$APP" "$STAGING/Mdy.app"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG" "$DMG.sig"
  hdiutil create -quiet -volname Mdy -srcfolder "$STAGING" -format UDZO "$DMG"
  lipo -info "$APP/Contents/MacOS/Mdy"
  echo "✓ $DMG"
  PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print MdyUpdatePublicKey' Resources/Info.plist 2>/dev/null || true)"
  if [[ -n "$PUBLIC_KEY" ]] && swift scripts/update-signing.swift sign "$DMG" > "$DMG.sig" 2>/dev/null; then
    swift scripts/update-signing.swift verify "$DMG" "$DMG.sig" "$PUBLIC_KEY"
    echo "✓ $DMG.sig (업데이트 서명)"
  else
    rm -f "$DMG.sig"
    echo "  ※ 업데이트 서명 키가 없어 .sig 를 만들지 않았어요 (swift scripts/update-signing.swift keygen)."
  fi
  if [[ "$IDENTITY" != "-" ]]; then
    echo "  공증(notarize):"
    echo "    xcrun notarytool submit $DMG --keychain-profile <프로필> --wait && xcrun stapler staple $DMG"
  fi
fi
