# 보안 · Security

[한국어](#한국어) · [English](#english)

## 한국어

### 지원하는 버전

가장 최근 릴리스만 고쳐요. Mdy는 하루에 한 번 새 버전을 확인하니 최신 버전으로 업데이트해 주세요.

### 취약점 알리기

보안 문제는 공개 이슈에 올리지 말고, 저장소의 **Security → Report a vulnerability**로 비공개로 알려 주세요. 다음을 적어 주시면 도움이 돼요.

- Mdy와 macOS 버전
- 무엇이 문제인지, 다시 일으키는 방법
- 예상되는 피해

혼자 만드는 무료 앱이라 답이 늦을 수 있지만, 확인되면 고친 버전을 릴리스하고 변경 기록에 적어요.

### Mdy가 지키는 것

- 미리보기는 문서 안의 스크립트를 실행하지 않아요(콘텐츠 보안 정책). 실행 파일을 가리키는 링크는 열지 않고, 다른 앱을 여는 주소는 먼저 물어봐요.
- 문서는 이 Mac에서만 다루고 어디에도 보내지 않아요. 네트워크는 GitHub 업데이트 확인과, 막지 않았을 때 문서가 가리키는 외부 이미지에만 써요.
- git 저장소의 문서를 비교할 때 저장소 설정이 다른 명령을 실행하지 못하게 해서 git을 불러요.
- 업데이트는 https GitHub 주소에서만 받고, GitHub가 알려 준 SHA-256과 만든 사람의 Ed25519 서명이 맞을 때만 설치해요.
- Apple 공증은 받지 않았어요. 처음 실행할 때 보안 경고가 나오는 이유예요([설치](README.md#설치)).

## English

### Supported versions

Only the latest release gets fixes. Mdy checks for a new version once a day, so please keep it up to date.

### Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately with **Security → Report a vulnerability** in this repository. It helps to include:

- Your Mdy and macOS versions
- What the problem is and how to reproduce it
- What an attacker could do

Mdy is a free app made by one person, so replies may take a while. Confirmed problems are fixed in a new release and noted in the changelog.

### What Mdy protects

- The preview never runs scripts inside documents (Content Security Policy). Links to executables aren't opened, and Mdy asks before opening addresses that launch other apps.
- Documents stay on this Mac and are never sent anywhere. The network is used only to check GitHub for updates and, unless blocked, to load remote images a document points to.
- When comparing documents in a git repository, git is run so that the repository's settings can't run other commands.
- Updates come only from https GitHub addresses and are installed only when they match the SHA-256 from GitHub and the developer's Ed25519 signature.
- Mdy isn't notarized by Apple, which is why macOS shows a security warning on first launch ([Install](README.en.md#install)).
