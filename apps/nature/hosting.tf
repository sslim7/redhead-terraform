# Firebase Hosting 을 Cloud Run 앞단의 rewrite 프록시로 쓴다.
#
# **왜 한 겹이 끼어 있는가** — Cloud Run 도메인 매핑이 asia-northeast3 에서 지원되지 않아
# Cloud Run 에 도메인을 직접 붙일 수 없다. 남은 대안이던 External HTTPS LB 는 트래픽이 0이어도
# 월 약 $18 고정비다. Hosting 은 무료이고 관리형 SSL 인증서까지 붙여 준다.
# 이 문단을 모르는 사람이 "왜 Hosting 이 끼어 있지" 하고 걷어내는데, 걷어내면 도메인이 죽는다.
#
# ── 🔴 apply 직후 이 도메인들은 Firebase 기본 404 다 ────────────────────────
#
# 이 모듈이 만드는 것은 **사이트 리소스와 커스텀 도메인 매핑까지**다. 어떤 Cloud Run 으로
# 넘길지(rewrite)는 Terraform 이 만들지 않는다 — `scripts/hosting-release.sh` 가
# `hosting/{사이트}.json` 을 올린다.
#
# 넘긴 이유는 `appAssociation` 이다. 프로바이더가 그 필드를 노출하지 않는데(7.44·8.0 모두
# config 는 headers/redirects/rewrites 뿐), 기본값 AUTO 는 `/.well-known/assetlinks.json` 을
# Firebase 가 만든 빈 배열로 가로채므로 안드로이드 App Links 를 쓰려면 반드시 NONE 이어야
# 한다. 자세한 논지는 scripts/hosting-release.sh 상단과 modules/firebase-hosting/main.tf 의
# "콘텐츠 소유권의 경계" 주석에 있다.
#
# 그래서 apply 가 성공해도 도메인이 안 뜬다. 스크립트를 사이트마다 한 번 돌려야 한다:
#   scripts/hosting-release.sh redhead-jayeon-app
#   scripts/hosting-release.sh redhead-jayeon-api
#
# ── 🔴 site_id 는 Firebase 전역 유일값이다 ──────────────────────────────────
#
# 프로젝트 안이 아니라 전역이다. `jayeon-app` 같은 흔한 이름은 남이 선점했을 수 있어
# 프로젝트 이름을 접두어로 붙였다(redhead-jayeon-app). 선점된 값이면 apply 가 실패한다.
#
# ── 🔴 shared/ 의 google_firebase_project 에 의존하지만 Terraform 이 강제하지 못한다 ──
#
# Hosting 사이트는 그 프로젝트가 Firebase 프로젝트로 등록돼 있어야 만들어진다. 그 등록은
# shared/ 가 소유하고 **state 가 달라서 여기서 depends_on 을 걸 방법이 없다.**
# apply 순서(shared 먼저)가 유일한 보장이다. 순서를 어기면 여기서 실패하는데, 에러가
# "프로젝트를 찾을 수 없다" 류로 나와 프로젝트 ID 를 의심하게 만든다.

module "hosting_app" {
  source = "../../modules/firebase-hosting"

  # Hosting 사이트·커스텀 도메인은 firebasehosting API 를 타므로 quota project 가 필요하다.
  # 이 배선이 없으면 프로젝트에 API 가 켜져 있어도 403 SERVICE_DISABLED 다.
  # 이유는 providers.tf 의 google-beta.firebase 주석 참고.
  providers = {
    google      = google
    google-beta = google-beta.firebase
  }

  project_id = var.project_id
  site_id    = var.hosting.app_site_id

  custom_domains = distinct([var.domains.app, var.legacy_domains.app])
}

module "hosting_api" {
  source = "../../modules/firebase-hosting"

  # 위와 같은 이유로 firebase 별칭을 배선한다.
  providers = {
    google      = google
    google-beta = google-beta.firebase
  }

  project_id = var.project_id
  site_id    = var.hosting.api_site_id

  custom_domains = distinct([var.domains.api, var.legacy_domains.api])
}
