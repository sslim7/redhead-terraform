# 통화 목록은 recordedAt DESC, __name__ DESC의 자동 단일 필드 인덱스를 사용한다.
# 이름 필터는 앱이 받아 온 목록에서 직접 걸러내므로 복합 인덱스가 필요 없다.
# 본문은 ID로만 조회한다. 큰 JSON byte 필드를 검색 인덱스에 복제하지 않는다.
#
# ── 🔴 이 리소스를 지우면 통화 저장이 깨진다 ────────────────────────────────
#
# `index_config {}` 는 "이 필드는 색인하지 않는다" 는 뜻이다. 이 리소스를 destroy 하면
# Firestore 는 해당 필드의 **기본 색인을 되살린다**. 그러면 400 KB 짜리 JSON byte 필드가
# 다시 색인 대상이 되고, 색인되는 필드 값에 걸리는 Firestore 크기 한도 때문에 **쓰기가
# 거부될 수 있다** — 증상은 `PUT /calls/{id}` 의 500 하나뿐이다.
#
# 더 고약한 점: **Firestore 에뮬레이터는 이 한도를 강제하지 않는다.** 단위 테스트도
# 통합 테스트도 전부 통과한 채로 운영에서만 깨진다.
#
# 그래서 배포 순서가 정해져 있다 — **① 이 apply → ② WAS 배포.** 뒤집지 말 것.
# (jayeon-was `docs/call-analysis.md` 에 같은 내용이 있다.)
resource "google_firestore_field" "call_payload" {
  for_each = {
    calls      = "record"
    transcript = "data"
    analysis   = "data"
    todos      = "data"
  }

  project    = var.project_id
  database   = "(default)"
  collection = each.key
  field      = each.value

  index_config {}

  depends_on = [module.firestore]

  # 🔴 실수로 지우는 것을 막는다. 정말로 없애야 한다면 이 블록을 먼저 지우고,
  # 그 전에 위 주석의 결과(운영 쓰기 실패)를 감수할 수 있는지 확인한다.
  lifecycle {
    prevent_destroy = true
  }
}
