#!/bin/zsh
# 배포용 빌드: build/Mdy.app + build/Mdy-<버전>.dmg (Apple 실리콘 + Intel).
# 업데이트 서명 키가 키체인에 있으면 build/Mdy-<버전>.dmg.sig 도 만들고 확인해요.
set -e
cd "$(dirname "$0")/.."
./build.sh dist
