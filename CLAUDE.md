> 문서·UI 규칙은 ../mac-app/STYLE.md를 따른다. 다르게 할 때는 여기에 이유를 적는다.

# Mdy

Finder에서 더블클릭으로 여는 마크다운 뷰어 겸 편집기. SwiftUI `DocumentGroup` 문서 앱(Dock 앱)이고, 미리보기는 WKWebView, 훑어보기 확장이 따로 있다.
Xcode 없이 Command Line Tools의 `swiftc`로 빌드한다(SwiftPM·Xcode 프로젝트 없음).

## 명령

```bash
./scripts/test.sh                 # 자체 점검: 번역 빠짐, 공통 파일, JS 문법, 편집기 동작 시험
./build.sh install                # 이 Mac에 설치(/Applications), .md 기본 앱 지정, 훑어보기 등록
./scripts/build-app.sh            # 유니버설(arm64+x86_64) build/Mdy.app + build/Mdy-<버전>.dmg(+.sig)
./scripts/release.sh              # 점검 → dmg + .sig → 태그 push → gh release (main에서만, 하기 전에 사용자 확인)
python3 scripts/l10n.py keys      # 번역 키 목록·빠진 번역
python3 scripts/l10n.py wrap      # 새 한국어 화면 글자를 tr("…")로 감싸기
./scripts/fetch_vendor.sh         # KaTeX·Mermaid 다시 받기 (Resources/vendor)
swift scripts/make_icon.swift <iconset> [docs/images/icon.png]   # 아이콘 다시 그리기
```

## 구조

- `Sources/` 앱. `DocumentSession`이 창 하나의 `EditorController`(NSTextView, TextKit 1)와 `PreviewController`(WKWebView)를 잇는다.
  위치 표시·스크롤 동기화는 markdown.js가 HTML에 남기는 `data-line`/`data-line-end`(원본 줄 번호, 0부터)로 맞춘다.
- `Resources/preview.html` 미리보기 페이지. `markdown.js`(변환기), `highlight.js`(코드 색칠), `convert.js`(HTML→마크다운)를 앱이 `/*MARKDOWN_JS*/` 자리에 넣는다.
- `QuickLook/` Finder 훑어보기(데이터 기반, JavaScriptCore로 markdown.js 실행, 스크립트 없음).
- `Resources/vendor` KaTeX·Mermaid(MIT). 미리보기는 파일을 직접 못 읽어서 앱이 `needLib` 메시지를 받으면 내용을 `mdyProvideLib`로 넘긴다(eval로 실행하면 Mermaid가 시작하지 못함).
- `Resources/Templates/{ko,en}` 기본 템플릿, `Resources/Help.md`·`Help.en.md` 도움말(모든 문법 예제 겸용).

## 지켜야 할 것

- **미리보기 보안**: preview.html의 CSP(nonce)는 앱이 불러올 때마다 새 nonce로 바꾼다. 새로 만드는 `<script>`에는 `NONCE`를 붙인다. `sanitize()`를 거치지 않은 HTML을 문서에 넣지 않는다.
  링크는 `LinkSafety`로만 연다(실행 파일은 막고, http·https·mailto 말고는 묻는다). git은 `GitBase`의 안전한 옵션(`cat-file`, fsmonitor·hooks 끔)으로만 부른다.
- **화면 글자**: 한국어 원문을 `tr("…")`로 감싸고 영어는 `Resources/en.json`. 미리보기 안의 글자는 `PreviewController.pageStrings`와 preview.html의 `T('…')`. 말투는 ~어요/~해요.
- **공통 파일**: `Sources/AppUpdater.swift`, `Sources/AppAbout.swift`는 `../mac-app/shared` 복사본. 여기서 고치지 않는다(l10n.py도 건드리지 않게 빼 두었다).
- **업데이트 서명 키**: 비밀 키는 로그인 키체인 "Mdy Update Signing"(백업 `~/.config/mdy/update-signing.key`). 공개 키는 Info.plist `MdyUpdatePublicKey`.
  **읽어서 출력하거나 커밋하지 않는다.**
- **GitHub에 올리기(push)와 새 버전 내기(release)는 하기 전에 꼭 사용자에게 확인받는다.**

## 공통 규칙과 다른 점 (이유)

- **번역은 `L()` 대신 `tr()` + en.json**: 같은 Dock 앱인 Gitty와 같은 방식(문자열 보간을 그대로 키로 쓸 수 있음).
- **업데이트 키 도구 이름 `scripts/update-signing.swift`**: Gitty에서 가져와 키체인에 키를 둔다(STYLE의 `sign-update.swift`와 이름만 다름).
- **설정에 단축키 탭 없음**: 전역 단축키가 없고 메뉴 단축키만 있어서. 탭은 일반 · 편집기 · 미리보기 · 정보.
- **Intel도 지원**: 문서 앱이라 Gitty처럼 유니버설로 낸다.
- **빌드 스크립트가 `build.sh` + `scripts/build-app.sh`**: SwiftPM 없이 swiftc로 앱·훑어보기 확장을 따로 컴파일하고 lipo로 합친다. `build.sh install`은 개발용 설치.

## 릴리스 순서

Info.plist 버전(+`CFBundleVersion`) 올리기 → `docs/releases/v<버전>.md` → `CHANGELOG.md`·`CHANGELOG.en.md` 맨 위 → `./scripts/test.sh` → 커밋·main push → `./scripts/release.sh`.
