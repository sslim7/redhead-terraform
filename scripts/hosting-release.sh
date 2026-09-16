#!/usr/bin/env bash
#
# Firebase Hosting 의 버전을 만들고 릴리스한다. rewrite 사이트(app·api) 전용이다.
#
# **왜 Terraform 이 아니라 여기인가.** Hosting 버전 설정에는 `appAssociation` 이 있는데
# 프로바이더가 그 필드를 노출하지 않는다(7.44·8.0 모두 `config` 는 headers/redirects/rewrites
# 뿐). 기본값 AUTO 는 `/.well-known/assetlinks.json` 을 Firebase 가 만든 빈 배열로 가로채므로,
# 안드로이드 App Links 를 쓰려면 반드시 `NONE` 이어야 한다. Terraform 으로는 표현할 수 없다.
#
# 공존시키지 않고 통째로 옮긴 이유는 modules/firebase-hosting/main.tf 의 경계 주석에 있다 —
# 한 줄만 고쳐 apply 해도 Terraform 이 자기 버전을 새로 릴리스하면서 이 설정을 지우는데,
# 직접 설치한 앱에서는 계속 열려서 **테스트로는 드러나지 않는다.**
#
# 쓰는 법
#
#     scripts/hosting-release.sh redhead-jayeon-app
#     scripts/hosting-release.sh redhead-jayeon-api "메시지"
#
# 설정은 `hosting/{사이트}.json` 이다. 밑줄(`_`)로 시작하는 키는 주석이라 보내기 전에 걷어낸다.
#
# 릴리스는 원자적이다 — 새 버전을 완성한 뒤 한 번에 갈아끼우므로 중간에 끊기는 순간이 없다.
set -euo pipefail

SITE="${1:-}"
MESSAGE="${2:-hosting-release.sh}"
PROJECT="${GOOGLE_CLOUD_PROJECT:-redhead-kr}"

if [[ ! "$SITE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "쓰는 법: $0 <사이트ID> [메시지]" >&2
  echo "  예: $0 redhead-jayeon-app" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT/hosting/$SITE.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "설정 파일이 없다: $CONFIG_FILE" >&2
  exit 1
fi

# HTTP 오류는 다음 단계로 진행하지 않는다. 응답 내용도 각 단계에서 검증한다.
TOKEN="$(gcloud auth print-access-token)"
API="https://firebasehosting.googleapis.com/v1beta1"

# 주석 키를 걷어내고 `{"config": …}` 로 감싼다.
BODY="$(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding='utf-8'))
cfg = {k: v for k, v in cfg.items() if not k.startswith('_')}
print(json.dumps({"config": cfg}))
PY
)"

echo "▸ $SITE 에 새 버전을 만든다"
VERSION="$(curl --fail-with-body -sS -X POST "$API/sites/$SITE/versions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d "$BODY" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("name") or sys.exit("만들지 못했다: " + json.dumps(d, ensure_ascii=False)))')"
echo "  $VERSION"

# 파일이 없는 rewrite 전용 버전이라 업로드 단계가 없다. 곧바로 완성 처리한다.
echo "▸ 완성 처리"
curl --fail-with-body -sS -X PATCH "$API/$VERSION?updateMask=status" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d '{"status":"FINALIZED"}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); d.get("status") == "FINALIZED" or sys.exit("완성 실패: " + json.dumps(d, ensure_ascii=False)); print("  상태:", d["status"])'

echo "▸ 릴리스"
curl --fail-with-body -sS -X POST "$API/sites/$SITE/releases?versionName=$VERSION" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: $PROJECT" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"message": sys.argv[1]}))' "$MESSAGE")" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  ", d.get("name") or sys.exit("릴리스 실패: " + json.dumps(d, ensure_ascii=False)))'

echo "▸ 확인 — 지금 서빙 중인 설정"
curl --fail-with-body -sS "$API/sites/$SITE/releases?pageSize=1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-goog-user-project: $PROJECT" \
  | python3 -c '
import sys, json
d = json.load(sys.stdin)
v = (d.get("releases") or [{}])[0].get("version", {})
cfg = v.get("config", {})
expected = json.load(open(sys.argv[1], encoding="utf-8"))
if v.get("name") != sys.argv[2]:
    sys.exit("현재 릴리스가 방금 만든 버전과 다릅니다")
if cfg.get("appAssociation") != expected.get("appAssociation") or cfg.get("rewrites") != expected.get("rewrites"):
    sys.exit("현재 릴리스 설정이 요청한 설정과 다릅니다")
print("  appAssociation:", cfg["appAssociation"])
print("  rewrites:", json.dumps(cfg.get("rewrites", []), ensure_ascii=False))
' "$CONFIG_FILE" "$VERSION"
