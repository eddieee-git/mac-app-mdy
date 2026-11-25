<p align="center"><img src="docs/images/icon.png" width="96" alt="Mdy 아이콘"></p>

<h1 align="center">Mdy</h1>

<p align="center">Finder에서 더블클릭으로 바로 여는 macOS 마크다운 뷰어 겸 편집기<br>왼쪽은 원본, 오른쪽은 다듬어진 미리보기. 어느 쪽에서든 고치면 바로 맞춰져요.</p>

<p align="center">
  <a href="https://github.com/eddieee-git/mac-app-mdy/releases/latest">최신 버전 내려받기</a> ·
  <a href="#설치">설치</a> ·
  <a href="#쓰는-방법">쓰는 방법</a> ·
  <a href="#단축키">단축키</a> ·
  <a href="#자주-묻는-질문">자주 묻는 질문</a> ·
  <a href="CHANGELOG.md">변경 기록</a> ·
  <a href="README.en.md">English</a>
</p>

## 특징

- **더블클릭으로 열기**: `.md` 파일의 기본 앱이 되고, Finder에서 스페이스 바를 누르면 Mdy 스타일로 훑어볼 수 있어요.
- **원본과 미리보기를 나란히**: 비율 버튼(1:3 · 1:1 · 3:1)이나 가운데 구분선으로 폭을 바꾸고, 한쪽을 접을 수 있어요.
- **양쪽이 서로 따라가요**: 한쪽에서 커서를 두거나 글자를 고르면 다른 쪽의 같은 곳이 표시되고, 스크롤도 함께 움직여요.
- **미리보기에서 바로 고치기**: 미리보기를 두 번 클릭하면 그 블록이 마크다운 입력 칸으로 바뀌어요. 체크리스트 상자도 바로 눌러요.
- **편하게 쓰기**: 문법 색칠, 서식 단축키, 목록·표 자동 이어쓰기, 괄호 짝 맞추기, 제목 접기, 줄 번호, 집중 모드.
- **붙여 넣기와 복사**: 웹·구글 문서·워드에서 복사한 서식은 마크다운으로, 엑셀 칸은 표로 들어가요. 미리보기에서 복사하면 메일·슬랙에 서식째 붙어요. 이미지는 문서 옆 폴더에 저장돼요.
- **여러 문서**: 폴더 사이드바, 빠른 열기, 폴더 전체 검색, 문서 간 링크와 뒤로·앞으로, 템플릿.
- **GitHub 스타일 문법**: 표, 체크리스트, 각주, 알림, 코드 색칠, `[TOC]` 목차, 수식(KaTeX), 다이어그램(Mermaid). 수식과 다이어그램도 인터넷 없이 그려요.
- **내보내기**: HTML, PDF, Word, RTF, 프린트.
- **바뀐 줄 표시**: git 저장소의 문서는 마지막 커밋과 비교해서 추가·수정·삭제된 줄을 표시해요. 다른 앱에서 파일이 바뀌면 다시 불러와요.
- **안전하게 보기**: 받은 문서 안의 스크립트는 실행하지 않고, 실행 파일을 가리키는 링크는 열지 않아요. 외부 이미지도 막을 수 있어요.
- **앱 안 업데이트**: 새 버전이 나오면 알려 주고, 서명을 확인한 뒤 바꿔 넣어요.
- **한국어·영어**: 처음에는 Mac의 언어를 따르고, 설정에서 바꿀 수 있어요.

## 설치

macOS 14(Sonoma) 이상이 필요해요. Apple 실리콘과 Intel Mac 모두 지원해요.

1. [Releases](https://github.com/eddieee-git/mac-app-mdy/releases/latest)에서 `Mdy-x.y.z.dmg`를 내려받아 열어요.
2. **Mdy**를 **Applications** 폴더로 끌어다 놓아요.
3. Mdy를 열어요. Apple 개발자 서명이 없는 앱이라 처음 한 번은 열 수 없다는 경고가 나와요. **완료**를 누른 뒤:
   - **macOS 15(Sequoia) 이상**: 시스템 설정 → 개인정보 보호 및 보안을 맨 아래까지 내려서 Mdy 옆의 **그래도 열기**를 누르고, 한 번 더 **열기**를 눌러요.
   - **macOS 14(Sonoma)**: 응용 프로그램 폴더에서 Mdy를 **오른쪽 클릭 → 열기**를 눌러요.

   터미널이 편하면 `xattr -dr com.apple.quarantine /Applications/Mdy.app`을 실행해도 돼요.
4. `.md` 파일을 더블클릭했는데 다른 앱이 열리면, Finder에서 `.md` 파일을 고르고 ⌘I → **다음으로 열기**에서 Mdy를 고른 뒤 **모두 변경**을 눌러요.

## 쓰는 방법

1. Finder에서 `.md` 파일을 더블클릭해요. 문서 없이 Mdy를 열면 **시작 창**에서 새 문서, 최근 문서, 템플릿을 고를 수 있어요.
2. 왼쪽 원본에 쓰거나, 오른쪽 미리보기를 두 번 클릭해서 그 자리에서 고쳐요. 고친 내용은 자동으로 저장돼요.
3. 툴바 왼쪽 **사이드바** 버튼으로 목차·파일·검색을 열고, 오른쪽 비율 버튼으로 원본과 미리보기의 폭을 바꿔요.
4. 자세한 사용법은 **도움말 → Mdy 도움말**(⌘?)에 있어요. 도움말 문서 자체가 모든 문법의 예제예요.

## 단축키

| 키 | 동작 |
|---|---|
| ⌘1 · ⌘2 · ⌘3 | 원본만 · 나란히 · 미리보기만 |
| ⌥⌘1 · ⌥⌘2 · ⌥⌘3 | 원본 : 미리보기 비율 1:3 · 1:1 · 3:1 |
| ⌃⌘S | 사이드바 (목차 · 파일 · 검색) |
| ⇧⌘O | 빠른 열기 |
| ⇧⌘F | 폴더에서 찾기 |
| ⌘F · ⌘G · ⇧⌘G | 찾기 · 다음 · 이전 (원본과 미리보기 모두) |
| ⌘B · ⌘I · ⌘K | 굵게 · 기울임 · 링크 |
| ⇧⌘K · ⇧⌘X · ⇧⌘H | 코드 · 취소선 · 형광펜 |
| ⌃⌘1~6 · ⌃⌘0 | 제목 1~6 · 본문 |
| ⇧⌘T | 표 정렬 |
| ⌥⌘← · ⌥⌘→ | 제목 접기 · 펴기 |
| ⌘[ · ⌘] | 문서 링크 뒤로 · 앞으로 |
| ⌥⇧⌘C | 서식 있는 텍스트로 복사 |
| ⇧⌘J | 집중 모드 |
| ⌥⌘L | 스크롤 동기화 |
| ⇧⌘E · ⌥⌘P | HTML · PDF로 내보내기 |
| ⌘? | 도움말 |

## 설정

| 항목 | 설명 |
|---|---|
| 화면 모드 | 시스템 설정 따르기 / 밝게 / 어둡게 |
| 문서를 열 때 보기 | 원본만 / 나란히 / 미리보기만 (기본: 마지막으로 쓴 모드) |
| 문서를 한 창의 탭으로 열기 | 여러 문서를 탭으로 모아요 (기본 켬) |
| 작업 폴더 | 사이드바·빠른 열기·검색이 볼 폴더 (기본: 지금 문서가 있는 폴더) |
| 편집기 | 글꼴·크기, 문법 색칠, 맞춤법 검사, 자동 이어쓰기, 짝 맞추기, 서식 붙여 넣기 변환, 줄 번호, 바뀐 줄 표시, 이미지 폴더 이름 |
| 미리보기 | 글꼴, 본문 폭, 테마(GitHub / 종이), 수식·다이어그램, 외부 이미지 막기(기본 끔) |
| 로그인 시 실행 | Mac을 켤 때 자동으로 실행 (기본 끔) |
| 언어 | 시스템 / 한국어 / English |
| 새 버전 자동으로 확인 | 하루 한 번 GitHub에서 새 버전을 확인해요 (기본 켬) |
| 새 버전 자동으로 설치 | 확인한 새 버전을 앱을 쓰지 않을 때 알아서 설치하고 다시 켜요 (기본 켬) |

## 자주 묻는 질문

**어떤 정보를 보내나요?**
업데이트 확인 때 GitHub 공개 API에 최신 릴리스를 묻는 요청 하나만 보내요. 문서 내용은 어디에도 보내지 않아요. 설정에서 자동 확인을 끄면 그것도 보내지 않아요. 단, 문서 안에 인터넷 주소의 이미지가 있으면 그 이미지는 그 주소에서 불러와요. 설정 → 미리보기 → **외부 이미지 막기**를 켜면 문서마다 직접 **불러오기**를 누를 때만 불러와요.

**받은 마크다운 파일을 열어도 안전한가요?**
미리보기는 문서 안의 스크립트를 실행하지 않아요. 링크가 앱이나 스크립트 같은 실행 파일을 가리키면 열지 않고, 다른 앱을 여는 주소는 먼저 물어봐요. git 저장소의 문서를 열 때도 저장소 설정이 다른 명령을 실행하지 못하게 해서 git을 불러요.

**문서·데스크탑 폴더에 접근을 허용하라고 물어요.**
사이드바의 파일 목록과 폴더 검색이 그 폴더를 읽을 때 macOS가 물어요. 허용하지 않아도 문서를 열고 고치는 데는 문제없어요.

**수식이나 다이어그램이 글자로만 보여요.**
설정 → 미리보기 → **수식·다이어그램 그리기**가 켜져 있는지 확인해 주세요. Finder 훑어보기(스페이스 바)에서는 스크립트가 돌지 않아서 원문 그대로 보여요.

**Word로 내보내면 다이어그램이 없어요.**
Word는 다이어그램 그림을 받을 수 없어서 빠져요. 수식은 TeX 글자로 바뀌어요. 모양을 그대로 두려면 PDF로 내보내 주세요.

## 지우기

1. Mdy 메뉴 → **Mdy 종료**
2. 응용 프로그램 폴더에서 Mdy를 휴지통으로
3. (선택) 설정까지 지우려면 `defaults delete com.eddieee.Mdy`, 템플릿과 도움말 사본은 `~/Library/Application Support/Mdy`

## 직접 빌드하기

macOS 14 이상, Xcode Command Line Tools가 필요해요(Xcode는 없어도 돼요).

```bash
./scripts/test.sh        # 자체 점검
./scripts/build-app.sh   # build/Mdy.app + build/Mdy-<버전>.dmg (Apple 실리콘 + Intel)
./build.sh install       # 이 Mac에 설치하고 .md 기본 앱으로 지정
```

## 라이선스

[MIT](LICENSE). 앱에 들어 있는 [KaTeX](https://katex.org)와 [Mermaid](https://mermaid.js.org)도 MIT 라이선스예요(`Resources/vendor`).

<!-- more-apps:start -->
## 다른 앱

| | 앱 | |
|---|---|---|
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-clocky/main/docs/images/icon.png" width="32" alt=""> | [Clocky](https://github.com/eddieee-git/mac-app-clocky) | 메뉴바에서 꺼내 쓰는 넘김시계 타이머·알람·일정 알림 |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-floaty/main/docs/images/icon.png" width="32" alt=""> | [Floaty](https://github.com/eddieee-git/mac-app-floaty) | 메뉴바에서 바로 꺼내 쓰는 플로팅 스티커 메모 |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-gitty/main/docs/images/icon.png" width="32" alt=""> | [Gitty](https://github.com/eddieee-git/mac-app-gitty) | Git 저장소를 파일 관리자처럼 다루는 앱 |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-grabby/main/docs/images/icon.png" width="32" alt=""> | [Grabby](https://github.com/eddieee-git/mac-app-grabby) | 찍고, 그 자리에서 그리고, 바로 붙여 넣는 화면 캡처 |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-keepy/main/docs/images/icon.png" width="32" alt=""> | [Keepy](https://github.com/eddieee-git/mac-app-keepy) | 복사한 내용을 모아 두고 다시 붙여 넣는 클립보드 기록 |
| <img src="https://raw.githubusercontent.com/eddieee-git/mac-app-peeky/main/docs/images/icon.png" width="32" alt=""> | [Peeky](https://github.com/eddieee-git/mac-app-peeky) | 노치에 가려진 메뉴바 아이콘을 꺼내 보는 앱 |
<!-- more-apps:end -->
