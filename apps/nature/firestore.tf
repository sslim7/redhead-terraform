# Firestore Native 데이터베이스. jayeon-was 의 **유일한** 데이터 저장소다.
# Cloud SQL 을 쓰지 않는 이유는 트래픽이 0이어도 인스턴스 고정비를 받기 때문이다.
#
# 🔴 **왜 shared 가 아니라 앱 루트에 두는가.** 데이터는 앱의 것이다. 이 DB 를 쓰는 것은
# jayeon-was 뿐이고, 스키마·인덱스·보안 규칙이 전부 그 저장소의 코드와 함께 움직인다.
# shared 에 두면 앱 코드가 쿼리 하나를 추가할 때마다 도메인 전체를 소유한 state 를 고쳐야 한다.
#
# 대신 앱 루트에 두는 대가를 아래 두 설정이 막는다 — **이게 없으면 앱 실험용
# `terraform destroy` 한 번이 운영 데이터를 지운다.**
#   delete_protection_state = DELETE_PROTECTION_ENABLED : 콘솔·API 삭제를 API 가 거부한다
#   deletion_policy         = ABANDON                   : destroy 가 state 에서만 뺀다
# 둘은 서로를 대신하지 못한다. deletion_policy 는 Terraform 의 행동이고,
# delete_protection_state 는 Terraform 밖에서 온 삭제까지 막는다.
#
# 🔴 위치(location_id)는 **생성 후 변경 불가**다. 바꾸려면 DB 를 지우고 다시 만들어야 하고,
# 그건 데이터를 버리는 일이다 — delete protection 때문에 그마저도 한 단계를 더 거친다.
#
# API 활성화(firestore·firebaserules)는 shared/ 의 project-services 가 소유한다.
# 이 모듈은 API 를 켜지 않는다(§modules/firestore/main.tf 상단).
module "firestore" {
  source = "../../modules/firestore"

  # 보안 규칙(google_firebaserules_*)은 firebaserules API 를 타므로 quota project 가 필요하다.
  # 데이터베이스·인덱스는 GA 프로바이더라 영향이 없다. 이유는 providers.tf 참고.
  providers = {
    google      = google
    google-beta = google-beta.firebase
  }

  project_id  = var.project_id
  location_id = var.firestore.location_id

  database = {
    delete_protection_state = var.firestore.delete_protection_state
    deletion_policy         = var.firestore.deletion_policy
  }

  # ── 복합 인덱스 ───────────────────────────────────────────────────────────
  #
  # 출처: jayeon-was/internal/admin/audit.go:298-311 (비테스트 코드의 쿼리를 전부 훑어 실측).
  #
  # 활동 로그 조회(GET /admin/audit-logs)가 `adminId`·`targets` 등가 필터를 **선택적으로**
  # 걸고 `createdAt` 으로 정렬한다. 아래 여섯 개가 그 조합의 전부다.
  #
  # 🔴 **정렬 방향이 요청 파라미터다.** 그래서 같은 필터 조합마다 asc/desc 두 벌이 필요하다.
  # 한 벌만 두면 그 방향으로 정렬하는 요청만 500(FAILED_PRECONDITION)이 되고, 반대 방향은
  # 멀쩡하다 — 화면의 정렬 토글을 누른 사람만 깨진 것을 본다.
  #
  # 🔴 `createdAt` 은 범위 조건(>= / <)이자 정렬 키다. Firestore 는 범위를 건 필드로 먼저
  # 정렬할 것을 요구하므로 **필드 순서가 강제된다.** 순서를 바꾸면 그것은 다른 인덱스이고
  # 쿼리는 그 인덱스를 타지 못한다.
  #
  # ⚠️ 집계 카운트(NewAggregationQuery().WithCount())가 같은 쿼리를 탄다. 인덱스가 없으면
  # 목록과 총 개수가 **함께** 죽는다 — 목록만 빈 채로 뜨는 식의 부분 실패가 아니다.
  #
  # 필터를 아무것도 걸지 않은 조회(날짜 범위 + createdAt 정렬만)는 여기 없다.
  # Firestore 가 자동으로 만드는 단일 필드 인덱스로 돈다.
  indexes = [
    # ── adminId(담당자) 하나만 걸었을 때 ──
    {
      collection = "audit_logs"
      fields = [
        { field_path = "adminId", order = "ASCENDING" },
        { field_path = "createdAt", order = "ASCENDING" },
      ]
    },
    {
      collection = "audit_logs"
      fields = [
        { field_path = "adminId", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },

    # ── targets(대상) 하나만 걸었을 때 ──
    {
      collection = "audit_logs"
      fields = [
        { field_path = "targets", order = "ASCENDING" },
        { field_path = "createdAt", order = "ASCENDING" },
      ]
    },
    {
      collection = "audit_logs"
      fields = [
        { field_path = "targets", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },

    # ── 두 필터를 **동시에** 걸었을 때 ──
    #
    # 🔴 위 네 개가 이 경우를 덮어 주지 않는다. 등호 조건이 둘이면 (adminId, targets,
    # createdAt) 3필드 인덱스가 따로 필요하다. 화면에서 담당자와 대상을 같이 고르는 순간
    # 500 이 나는데, 각 필터를 하나씩 쓸 때는 잘 되기 때문에 원인을 찾기 어렵다.
    {
      collection = "audit_logs"
      fields = [
        { field_path = "adminId", order = "ASCENDING" },
        { field_path = "targets", order = "ASCENDING" },
        { field_path = "createdAt", order = "ASCENDING" },
      ]
    },
    {
      collection = "audit_logs"
      fields = [
        { field_path = "adminId", order = "ASCENDING" },
        { field_path = "targets", order = "ASCENDING" },
        { field_path = "createdAt", order = "DESCENDING" },
      ]
    },

    # ── 통화분석 작업 스윕(callJobs) ─────────────────────────────────────────
    #
    # tick 이 1분마다 거는 쿼리는 하나다(§call-jobs.tf):
    #   status == "pending" AND nextAttemptAt <= now ORDER BY nextAttemptAt ASC LIMIT n
    #
    # 🔴 **이건 단순 쿼리가 아니다.** 등가 조건(status)과 범위 조건(nextAttemptAt)이 서로
    # 다른 필드에 걸리는 순간 Firestore 의 자동 단일 필드 인덱스로는 덮이지 않는다.
    # 인덱스가 없으면 tick 이 매분 FAILED_PRECONDITION 으로 죽는데, WAS 기동·헬스체크·
    # 나머지 API 는 전부 정상이라 **알람이 울리지 않는다.** 증상은 "녹음은 올라가는데
    # 분석이 영원히 pending" 하나뿐이다.
    #
    # 🔴 필드 순서가 강제된다. Firestore 는 범위를 건 필드(nextAttemptAt)로 정렬할 것을
    # 요구하고, 등가 조건 필드가 그 앞에 와야 한다. 순서를 바꾸면 그것은 다른 인덱스이고
    # 위 쿼리는 그 인덱스를 타지 못한다.
    #
    # 방향은 ASCENDING 하나뿐이다. "가장 오래 기다린 작업부터" 가 이 쿼리의 전부이고,
    # 감사 로그와 달리 정렬 방향이 요청 파라미터가 아니다. DESCENDING 벌을 넣지 마라 —
    # 쓰지 않는 인덱스도 쓰기마다 갱신 비용을 낸다.
    #
    # ⚠️ WAS 가 이 쿼리에 필터를 하나라도 더하면(예: 공급자별 분리) 여기에 인덱스를
    # 같은 호흡으로 더해야 한다. 등가 조건이 둘이 되는 순간 이 인덱스는 그 쿼리를 덮지 못한다.
    {
      collection = "callJobs"
      fields = [
        { field_path = "status", order = "ASCENDING" },
        { field_path = "nextAttemptAt", order = "ASCENDING" },
      ]
    },
  ]

  # ── 단일 필드 collection group 인덱스 ─────────────────────────────────────
  #
  # 빈 리스트다. 현재 코드에 `CollectionGroup()` 호출이 **한 건도 없고**, 여기 넣을 것은
  # 그 쿼리가 거는 필드뿐이다. `admins`·`admins_by_email` 컬렉션의 쿼리는 전부 자동 인덱스로
  # 덮인다(단일 필드 등가 / 단일 필드 정렬 / 문서 ID 직접 조회).
  #
  # users 이메일 조회도 단일 필드 등가 조건이며, users_by_email 은 문서 ID 직접 조회다.
  # 따라서 사용자 로그인 경로에도 추가 복합/collection-group 인덱스는 필요하지 않다.
  single_field_indexes = []

  # 보안 규칙. **전면 거부**이며 그 이유는 firestore.rules 파일 상단에 적었다.
  # 이 저장소가 규칙의 유일한 소유자다 — firebase CLI 로 따로 배포하면 서로 덮어쓴다.
  rules_file = "${path.module}/firestore.rules"
}
