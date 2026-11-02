# 덱 편집본 공유 저장소 — named Firestore 데이터베이스 `makes`.
#
# 🔴 **(default) 를 쓰지 않는다.** (default) 는 nature(apps/nature/firestore.tf)가 소유하고,
# 그 규칙 release `cloud.firestore` 도 nature 것이다. 같은 DB·release 를 두 state 가 주장하면
# 나중 apply 가 앞의 규칙을 덮어쓴다. 그래서 별도 DB 를 두고 규칙 release 도
# `cloud.firestore/makes` 로 갈린다(modules/firestore/main.tf).
#
# ⚠️ named 데이터베이스는 무료 쿼터가 없다(전액 과금). 덱 편집본 몇 개의 읽기·쓰기라 금액은
# 미미하지만 0 은 아니다.
#
# 보호값은 nature 와 같다 — 앱 실험용 destroy 한 번이 편집본을 지우지 않게 한다.
#   delete_protection_state = DELETE_PROTECTION_ENABLED : 콘솔·API 삭제를 API 가 거부한다
#   deletion_policy         = ABANDON                   : destroy 가 state 에서만 뺀다
#
# 🔴 database_id · location_id 는 **생성 후 변경 불가**다. 바꾸면 DB 교체(데이터 버림)다.
#
# API 활성화(firestore·firebaserules)는 shared/ 의 project-services 가 소유한다.
module "firestore" {
  source = "../../modules/firestore"

  # 보안 규칙(google_firebaserules_*)은 firebaserules API 를 타므로 quota project 가 필요하다.
  # providers.tf 의 google-beta.firebase 참고.
  providers = {
    google      = google
    google-beta = google-beta.firebase
  }

  project_id  = var.project_id
  database_id = var.firestore.database_id
  location_id = var.firestore.location_id

  database = {
    delete_protection_state = var.firestore.delete_protection_state
    deletion_policy         = var.firestore.deletion_policy
  }

  # 규칙: `decks/{deck}` 은 누구나 읽고, 쓰기는 이메일 검증된 편집자만. 나머지는 전면 거부.
  # 편집자 목록은 variables.auto.tfvars 의 editors 다 — 바꾸면 새 ruleset 이 만들어지고
  # release 가 그쪽으로 옮겨 간다. 이 저장소가 규칙의 유일한 소유자다(firebase CLI 로
  # `firestore:rules` 를 따로 배포하지 마라 — 서로 덮어쓴다).
  rules_content = templatefile("${path.module}/firestore.rules.tftpl", {
    editors = jsonencode(var.editors)
  })
}
