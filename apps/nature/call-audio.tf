# 통화 녹음 원본을 담는 버킷. 서버 통화분석 파이프라인(ASR → LLM)의 입력이다.
#
# ── 무엇이 남고 무엇이 사라지는가 ───────────────────────────────────────────
#
# 🔴 **분석 결과는 남고, 원본 오디오만 사라진다.**
# 전사문(transcript)·분석 JSON(analysis)·할 일(todos)은 Firestore 에 있고 보관 기간이 없다
# (§firestore.tf). 이 버킷의 lifecycle 이 지우는 것은 녹음 파일 그 자체뿐이다.
# 366일이 지난 통화를 열면 요약·전사문은 그대로 보이고 **오디오 재생만 404 가 된다.**
# 화면이 그 상태를 "분석 실패" 로 보여 주면 안 된다 — 정상적으로 만료된 것이다.
#
# 🔴 그래서 **재분석(re-run)은 보관 기간 안에서만 가능하다.** 모델을 바꿔 과거 통화를 다시
# 돌리는 일은 366일치까지만 되고, 그보다 오래된 통화는 원본이 없어 영원히 불가능하다.
# 이건 되돌릴 수 없는 결정이고, 사용자가 확정한 값이다(§var.call_audio.retention_days).
#
# ── 용량 감각 ───────────────────────────────────────────────────────────────
#
# 30분 통화 ≈ 28MB. 하루 10통이면 월 8GB 남짓, 1년 누적 100GB 안쪽이다.
# 이 규모에서 버전 관리·CMEK·Autoclass 는 관리 비용만 늘리고 얻는 것이 없어 넣지 않는다.
resource "google_storage_bucket" "call_audio" {
  project = var.project_id

  # 🔴 버킷 이름은 **전역 유일값**이다. 이미 쓰이는 이름이면 apply 가 409 로 실패한다.
  # shared/state.tf 의 tfstate 버킷과 같은 방식으로 project_id 에서 파생시킨다 —
  # 프로젝트 ID 를 바꾸면 이름도 함께 따라오게 하려는 것이다.
  name = local.call_audio_bucket

  # Cloud Run·Firestore 와 같은 리전. 다른 리전에 두면 업로드는 같아도 WAS 가 파일을
  # 읽어 ASR 에 넘기는 왕복마다 리전 간 네트워크 요금과 지연이 붙는다.
  location = var.region

  # ACL 을 끄고 IAM 하나로만 접근을 통제한다. 둘이 공존하면 IAM 을 아무리 좁혀도
  # 오브젝트 ACL 로 뚫린 구멍이 남는다(shared/state.tf 와 같은 이유).
  uniform_bucket_level_access = true

  # 🔴 통화 녹음은 그 자체로 개인정보다. 실수로 allUsers/allAuthenticatedUsers 를 붙이는
  # 경로 자체를 막는다 — enforced 는 프로젝트·조직 정책보다 우선하고, 되돌리려면 이 코드를
  # 고쳐야 한다. 서명 URL 로 내려주는 구조라 공개 읽기가 필요한 순간이 아예 없다.
  public_access_prevention = "enforced"

  # ── 🔴 보관 기간: 1년 ──────────────────────────────────────────────────────
  #
  # age 는 **객체 생성 시각 기준**이며(마지막 접근이 아니다), 366일은 윤년을 포함한 1년이다.
  #
  # ⚠️ lifecycle 규칙은 즉시 실행되지 않는다. GCS 가 비동기로 하루 한 번쯤 훑으므로
  # 실제 삭제는 366일에서 최대 하루쯤 늦다. "정확히 366일" 을 감사 요건으로 약속하지 마라.
  #
  # ⚠️ 이 값과 WAS 의 CALL_AUDIO_RETENTION_DAYS 는 **같은 변수에서 나온다**(§run.tf).
  # 따로 적으면 앱이 화면에 약속하는 보관 기간과 버킷이 실제로 지키는 기간이 갈라지고,
  # 그 불일치는 366일 뒤에야 "있다고 한 파일이 없다" 로 드러난다.
  lifecycle_rule {
    condition {
      age = var.call_audio.retention_days
    }
    action {
      type = "Delete"
    }
  }

  # ── 🔴 soft delete 를 끈다 ────────────────────────────────────────────────
  #
  # GCS 는 신규 버킷에 **기본 7일 soft delete** 를 켠다. 그대로 두면 위 규칙이 지운 녹음이
  # 7일 더 살아 있고(복구 가능한 상태로), 그동안 저장 요금도 계속 나간다.
  # "1년 뒤 삭제" 라고 말해 놓고 실제로는 373일간 보관하는 셈이 된다.
  #
  # 0 이 비활성화를 뜻한다. 1~604799 같은 중간값은 API 가 거부한다(0 또는 7~90일).
  #
  # 대가: 실수로 지운 녹음을 되살릴 방법이 없다. 이 버킷의 객체는 사람이 지우지 않고
  # lifecycle 만 지우므로 되살릴 상황 자체가 거의 없다고 보고 고른 값이다.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  # 버전 관리를 켜지 않는다.
  #
  # 🔴 켜면 보관 기간 규칙이 조용히 무력화된다. 위 `age` 조건은 **live 객체**에만 걸리고
  # noncurrent 버전은 `days_since_noncurrent_time` 규칙이 따로 있어야 지워진다. 즉
  # 버전 관리만 켜고 규칙을 하나 더 넣지 않으면, 지웠다고 믿은 녹음이 영구히 남는다.
  # 오디오는 한 번 쓰고 읽기만 하는 불변 객체라 덮어쓸 일도 없다.

  # force_destroy 를 켜지 않는다(기본값 false).
  # 객체가 남아 있는 한 `terraform destroy` 가 이 버킷에서 멈춘다. 실수로 1년치 녹음을
  # 지우는 것을 막는 마지막 방어선이고, 정말 지워야 한다면 사람이 명시적으로 비워야 한다.

  # ── 🔴 CORS: 브라우저가 GCS 로 **직접** 올린다 ────────────────────────────
  #
  # 업로드는 서버를 통과하지 않는다. WAS 는 서명 URL(또는 resumable 세션 URL)만 발급하고,
  # 실제 바이트는 웹뷰 → GCS 로 간다. 그 요청은 오리진이 다른 cross-origin 요청이라
  # 이 설정이 없으면 **브라우저가 막는다.**
  #
  # 🔴 실패 모양이 고약하다 — GCS 로그·응답 코드·WAS 로그가 전부 정상이고, 막히는 것은
  # 브라우저뿐이다. curl 로는 100% 재현되지 않는다. 증상은 웹뷰 콘솔의 CORS 에러 하나다.
  # 네이티브(RN fetch)에서 올리면 Origin 헤더가 없어 CORS 가 적용되지 않으므로,
  # "안드로이드에서는 되는데 웹에서만 안 된다" 로 보이기도 한다.
  #
  # 🔴 `response_header` 는 Access-Control-Expose-Headers 다. **resumable 업로드는
  # `Location` 을 여기서 노출하지 않으면 동작 자체가 불가능하다** — 세션 시작 응답의
  # Location 헤더가 그 다음 PUT 을 보낼 주소인데, 노출하지 않으면 브라우저 JS 가 읽지 못한다.
  # 이때 응답 코드는 200 이고 에러도 없다. "업로드가 시작은 되는데 진행이 안 된다" 가 된다.
  #
  # OPTIONS 는 목록에 넣지 않는다. preflight 는 GCS 가 직접 처리하며, 이 목록은 preflight
  # 이후 **실제로 보낼 메서드**를 뜻한다.
  #   POST : resumable 세션 시작(x-goog-resumable: start)
  #   PUT  : 서명 URL 단순 업로드 및 resumable 청크 업로드
  #   GET/HEAD : 서명 URL 재생·이어올리기 진행 조회
  cors {
    origin          = var.call_audio.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST"]
    response_header = ["Content-Type", "Content-Length", "Content-Range", "Range", "ETag", "Location", "x-goog-resumable"]
    max_age_seconds = 3600
  }

  # storage.googleapis.com 은 shared/ 의 project-services 가 켠다(§modules/firestore/main.tf
  # 상단과 같은 이유로 여기서 API 를 켜지 않는다). 전제를 보장하는 것은 apply 순서뿐이다.
}

locals {
  # 버킷 이름을 tfvars 에서 명시하지 않으면 project_id 에서 파생시킨다.
  call_audio_bucket = coalesce(var.call_audio.bucket_name, "${var.project_id}-call-audio")
}

# ── WAS 런타임의 객체 읽기·쓰기 ─────────────────────────────────────────────
#
# 🔴 **프로젝트 레벨 roles/storage.objectAdmin 이나 roles/storage.admin 을 쓰지 마라.**
# 이 프로젝트에는 `redhead-kr-tfstate` 버킷이 함께 산다. 그 안의 state 에는 WAS 의 JWT
# 서명키가 평문으로 들어 있다(§secrets.tf). 프로젝트 레벨로 스토리지 권한을 주는 순간
# WAS 런타임이 자기 서명키를 읽을 수 있게 되고, 그건 곧 WAS 가 뚫리면 토큰 위조까지
# 한 번에 간다는 뜻이다. 그래서 **이 버킷 하나에만** 붙인다.
#
# `_iam_member` 를 쓴다. `_iam_binding`/`_iam_policy` 는 authoritative 라서 콘솔이나
# 서비스 에이전트가 붙인 바인딩을 다음 apply 가 조용히 지운다(§iam.tf 와 같은 논지).
#
# objectAdmin 을 고른 이유 — WAS 는 올리고(create), 읽고(get), 보관 기간과 별개로 사용자가
# 통화를 삭제하면 지워야(delete) 한다. objectViewer + objectCreator 조합으로는 delete 가
# 빠지고, 삭제가 조용히 실패해 지운 줄 안 녹음이 366일 동안 남는다.
#
# objectAdmin 에는 `storage.buckets.get` 이 없다. 서명 URL 발급에도, 객체 입출력에도
# 필요하지 않다. 버킷 메타데이터를 읽어야 하는 코드를 새로 쓰지 마라 — 그 순간 여기에
# 권한을 더해야 하고, 그건 이 최소 권한을 넓히는 일이다.
resource "google_storage_bucket_iam_member" "was_call_audio" {
  bucket = google_storage_bucket.call_audio.name
  role   = "roles/storage.objectAdmin"
  member = module.was_service_account.member
}
