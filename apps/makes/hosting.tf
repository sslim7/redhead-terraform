# Firebase Hosting 정적 사이트 — makes 저장소의 빌드 결과(dist/)를 그대로 서빙한다.
#
# ── 이 사이트는 Cloud Run rewrite 가 아니다 ─────────────────────────────────
#
# nature 와 달리 앞에 둘 Cloud Run 이 없다. 그래서 `scripts/hosting-release.sh` 를 돌리지
# 않고 `hosting/` 에 이 사이트의 json 도 없다. 콘텐츠는 ~/Projects/makes 의
# `npm run deploy`(= `firebase deploy --only hosting:makes`)가 올린다. 그 저장소의
# `.firebaserc` 가 프로젝트 `redhead-kr`, 타깃 `makes` → 사이트 `redhead-makes` 를 가리킨다.
#
# ── 🔴 apply 직후 도메인은 Hosting 기본 페이지(또는 404)다 ──────────────────
#
# 이 모듈이 만드는 것은 사이트와 커스텀 도메인 매핑까지다(modules/firebase-hosting 의
# "콘텐츠 소유권의 경계"). makes 쪽에서 한 번 deploy 해야 실제 콘텐츠가 뜬다.
#
# 🔴 shared/ 의 google_firebase_project 에 의존하지만 state 가 달라 depends_on 을 걸 수 없다.
# shared 를 먼저 apply 하는 순서가 유일한 보장이다(apps/nature/hosting.tf 참고).

module "hosting" {
  source = "../../modules/firebase-hosting"

  # firebasehosting API 는 quota project 가 필요하다. providers.tf 의 google-beta.firebase 참고.
  providers = {
    google      = google
    google-beta = google-beta.firebase
  }

  project_id = var.project_id
  site_id    = var.site_id

  custom_domains = [var.domain]
}
