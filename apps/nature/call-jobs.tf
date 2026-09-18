# 통화분석 작업 스윕(tick). Cloud Scheduler 가 1분마다 WAS 의 내부 엔드포인트를 두드리고,
# WAS 는 **그 요청 안에서** 밀린 작업을 처리한다.
#
# ── 왜 tick 방식인가 ────────────────────────────────────────────────────────
#
# Cloud Run 은 요청이 없는 동안 인스턴스를 내린다. 백그라운드 워커를 띄우려면
# `cpu_idle = false` + `min_instance_count >= 1` 이 필요한데, 그러면 1 vCPU 를 월 730시간
# 상시 점유해 무료 한도(180,000 vCPU-초/월)를 크게 넘는다(§variables.tf 의 cloud_run).
#
# tick 은 그 비용을 내지 않는다. "요청 안에서만 일한다" 는 제약을 지키는 대신
# cpu_idle 과 min_instances 를 지금 값 그대로 둘 수 있다(§run.tf).
#
# 🔴 **그 제약이 곧 설계 규칙이다.** tick 핸들러는 응답을 보내기 전에 할 일을 끝내야 한다.
# 고루틴을 띄워 놓고 200 을 먼저 돌려주면 cpu_idle = true 때문에 응답 직후 CPU 가 스로틀되고,
# 그 작업은 중간에 끊긴다. 증상은 "가끔 분석이 안 끝나 있다" 뿐이고 에러 로그가 없다.
#
# 🔴 한 tick 이 Cloud Run 요청 타임아웃(§var.cloud_run.timeout, 현재 60s)을 넘기면 안 된다.
# 한 번에 처리할 작업 수를 WAS 가 스스로 제한해야 하고, 남은 것은 다음 tick 이 가져간다.
# 넘기면 504 로 끊기는데 그때 이미 외부 API 비용은 나간 뒤다.
#
# ⚠️ tick 이 느려져 1분을 넘기면 **다음 tick 과 겹친다.** Cloud Scheduler 는 앞 실행이
# 끝날 때까지 기다려 주지 않고, concurrency 80 / max_instances 3 이라 같은 작업을 두
# 인스턴스가 동시에 집을 수 있다. 중복 처리를 막는 것은 Terraform 이 아니라 WAS 의
# 작업 클레임(callJobs 문서의 status·nextAttemptAt 을 트랜잭션으로 바꿔 잡는 것)이다.

# tick 호출자 전용 서비스 계정.
#
# 런타임 SA(jayeon-was-run)를 재사용하지 않는 이유 — 호출자와 피호출자가 같은 신원이면
# WAS 가 "이 요청이 Scheduler 에서 왔는가" 를 토큰만으로 구분할 수 없다. 자기 자신이 낸
# 토큰과 Scheduler 가 낸 토큰이 같아 보이기 때문이다.
module "call_scheduler_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = var.call_jobs.scheduler_sa_id
  display_name = "Nature 통화분석 tick 호출자"
  description  = "Cloud Scheduler 가 이 계정의 OIDC 토큰으로 WAS 의 tick 엔드포인트를 부른다"

  # 프로젝트 역할이 없다. 이 계정이 하는 일은 자기 OIDC 토큰으로 HTTP 요청 하나를 보내는
  # 것뿐이고, 그 권한은 아래 run.invoker 바인딩이 대상 서비스 단위로 준다.
  project_roles = []
}

# ── 🔴 지금 이 바인딩은 방어선이 아니다 ─────────────────────────────────────
#
# jayeon-was 는 `allow_unauthenticated = true` 다. Firebase Hosting rewrite 가 앞단이라
# Cloud Run 자체는 공개여야 하고(§run.tf, §hosting.tf), 그 결과 **allUsers 에 이미
# run.invoker 가 붙어 있다.** 즉 Cloud Run IAM 은 `/internal/calls/tick` 을 막아 주지 않는다.
#
# **실제 방어선은 WAS 안에 있다.** tick 핸들러는 Authorization 헤더의 OIDC ID 토큰을
# 직접 검증해야 한다:
#   1. 구글이 서명했는가(https://www.googleapis.com/oauth2/v3/certs)
#   2. `aud` 가 아래 audience 와 같은가
#   3. `email` 이 이 스케줄러 SA 의 이메일인가 (outputs.tf 의 call_tick_caller 참고)
#   4. `email_verified` 가 true 인가
# 이 검증을 빼먹으면 **누구나 curl 한 줄로 tick 을 때릴 수 있고**, 그 요청마다 외부
# ASR/LLM API 비용이 나간다. 인증 없이도 200 이 돌아오므로 테스트에서는 아무 문제가 없어 보인다.
#
# 그런데도 이 바인딩을 두는 이유 — Hosting 을 걷어내거나 tick 전용으로 서비스를 가르는 날
# `allow_unauthenticated` 를 false 로 내리게 되는데, 그때 이 줄이 없으면 tick 이 403 으로
# 조용히 죽는다. 매분 실패라 알람을 걸지 않으면 "분석이 안 돌아간다" 로만 보인다.
resource "google_cloud_run_v2_service_iam_member" "call_tick_invoker" {
  project  = var.project_id
  location = var.region
  name     = module.was.name

  role   = "roles/run.invoker"
  member = module.call_scheduler_service_account.member
}

# ── tick 잡 ─────────────────────────────────────────────────────────────────
#
# 🔴 **paused 기본값이 true 이고, 그 이유가 순서다.** WAS 에 `/internal/calls/tick` 이
# 배포되기 전에 잡을 켜면 매분 404 가 쌓인다. 잡 자체는 실패로 남고, Cloud Scheduler 로그가
# 실패로 도배돼 진짜 고장이 묻힌다.
#
# 순서: paused = true 로 apply → WAS 배포 → tfvars 에서 false 로 바꿔 다시 apply.
# (§variables.auto.tfvars 의 enable_was_startup_probe 와 같은 관례다.)
resource "google_cloud_scheduler_job" "call_tick" {
  project = var.project_id

  # ⚠️ Cloud Scheduler 의 리전은 생성 후 변경 불가다. 바꾸려면 잡을 지우고 다시 만들어야 한다.
  #
  # ⚠️ 이 프로젝트에는 App Engine 앱이 없다(README 의 "기본 VPC 없음" 과 같은 상태).
  # 지금의 Cloud Scheduler 는 HTTP 타깃에 App Engine 앱을 요구하지 않지만, 만약 apply 가
  # "App Engine app does not exist" 류로 실패하면 그건 프로젝트 ID 문제가 아니라 이 제약이다.
  region = var.region
  name   = var.call_jobs.job_name

  description = "통화분석 작업 스윕. WAS 가 요청 안에서 밀린 callJobs 를 처리한다"

  # 매분. 무료 한도는 결제 계정당 잡 3개이고 호출 수에는 과금이 없다.
  schedule = var.call_jobs.schedule

  # 매분 실행이라 시간대가 결과를 바꾸지 않는다. 그래도 명시한다 — 나중에 `0 3 * * *` 같은
  # 일정으로 바꾸는 순간 의미가 생기고, 그때 기본값이 무엇이었는지 찾게 된다.
  time_zone = var.call_jobs.time_zone

  paused = var.call_jobs.paused

  # Cloud Run 이 요청을 끊는 시점과 같은 값을 쓴다. 한 곳(var.cloud_run.timeout)에서 나오게
  # 해야 둘이 갈라지지 않는다. Scheduler 쪽이 더 길면 이미 504 로 끊긴 요청을 계속 기다리고,
  # 더 짧으면 WAS 가 정상 처리 중인 작업을 Scheduler 가 실패로 기록한다.
  attempt_deadline = var.cloud_run.timeout

  # 🔴 재시도하지 않는다.
  #
  # 어차피 1분 뒤에 다음 tick 이 온다. 재시도를 켜면 실패한 tick 의 재시도와 다음 tick 이
  # 겹쳐 같은 작업을 두 번 집을 확률만 올라간다. **작업 단위의 재시도는 Scheduler 가 아니라
  # Firestore 의 nextAttemptAt 이 소유한다** — 그래야 "몇 번 시도했는가" 가 작업 문서에 남는다.
  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"

    # 🔴 **Cloud Run 서비스 URL 로 직접 부른다. Hosting 도메인(nature-api.redhead.kr)이 아니다.**
    #
    # 이유 둘:
    #   1. OIDC 의 audience 는 아래처럼 Cloud Run URL 이어야 한다. Hosting 을 경유하면
    #      호출 주소와 audience 가 달라져 검증 설계가 꼬인다.
    #   2. tick 이 Hosting 릴리스 상태에 묶인다. rewrite 가 비어 있으면 도메인은 404 를
    #      돌려주는데(§README 의 Hosting rewrite), 그건 Terraform 이 소유하지 않는 상태다.
    #
    # ⚠️ 이 URL 은 서비스를 지우고 다시 만들면 바뀐다. 문자열로 박지 말고 모듈 출력을 쓴다.
    uri = "${module.was.uri}${var.call_jobs.tick_path}"

    oidc_token {
      service_account_email = module.call_scheduler_service_account.email

      # 🔴 audience 에 **경로를 붙이지 마라.** Cloud Run 이 토큰을 직접 검증하는 구성
      # (allow_unauthenticated = false)에서는 audience 가 서비스 URL 과 정확히 같아야 하고,
      # 경로가 붙으면 403 이 된다. 지금은 WAS 가 검증하지만 같은 규칙을 지켜 둔다 —
      # 나중에 서비스를 닫는 날 이 한 줄 때문에 tick 이 죽는 것을 피하려는 것이다.
      #
      # 🔴 **`module.was.uri` 가 아니라 var 를 쓴다.** 토큰을 발급하는 쪽(여기)과
      # 검증하는 쪽(WAS 의 CALL_TICK_AUDIENCE, §run.tf)은 반드시 **같은 출처**에서 값을
      # 받아야 한다. WAS 쪽은 순환 참조 때문에 module.was.uri 를 쓸 수 없으므로
      # (§variables.tf 의 call_jobs.audience), 여기서 module.was.uri 를 쓰면 두 값이
      # 서로 다른 출처가 되어 갈라질 수 있다. 갈라진 결과는 매분 403 이고, 스케줄러 잡도
      # WAS 도 "정상 동작 중" 으로 보인다.
      audience = var.call_jobs.audience
    }
  }

  # ── 🔴 이 설계의 안전장치 ────────────────────────────────────
  #
  # audience 가 tfvars 에 문자열로 박혀 있는 것은 순환 참조를 피하기 위한 타협이고
  # (§variables.tf 의 call_jobs.audience), 타협의 대가는 "언젠가 실제 URL 과 어긋난다" 다.
  # 어긋난 순간 스케줄러는 옛 URL 로 `aud` 를 채운 토큰을 발급하고 WAS 는 새 URL 을
  # 기대하므로 매분 403 이다. 잡은 "실행됨" 으로 남고 서비스는 건강하며, 보이는 증상은
  # 통화가 분석되지 않는 것뿐이다.
  #
  # 아래 precondition 이 그 상태를 **apply 시점에 큰 소리로** 잡는다. 여기서 module.was.uri
  # 를 읽는 것은 사이클이 아니다 — 이 리소스는 module.was 의 입력이 아니라 그 출력을
  # 소비하는 별개의 리소스다(위 uri 도 이미 같은 출력을 쓴다).
  #
  # ⚠️ 이 블록을 지우면 tfvars 의 오타 한 글자가 아무 경고 없이 배포된다.
  lifecycle {
    precondition {
      condition     = var.call_jobs.audience == module.was.uri
      error_message = <<-EOT
        call_jobs.audience 가 jayeon-was 의 실제 서비스 URL 과 다르다.

        이대로 apply 하면 Cloud Scheduler 는 이 값으로 OIDC 토큰을 발급하고 WAS 는
        자기 URL 을 기대하므로, tick 이 매분 403 으로 죽는다. 잡도 서비스도 정상으로
        보이고 증상은 "통화 분석이 진행되지 않는다" 하나뿐이다.

        고치는 법:
          1) 실제 URL 을 확인한다:
             gcloud run services describe ${var.cloud_run.was_name} --project ${var.project_id} --region ${var.region} --format='value(status.url)'
          2) apps/nature/variables.auto.tfvars 의 call_jobs.audience 를 그 값으로 바꾼다.
             경로를 붙이지 않는 서비스 URL 이어야 한다(끝 슬래시도 없이).
          3) 다시 plan/apply.

        (module.was.uri 로 바꿔서 해결하려 들지 마라. WAS 쪽 CALL_TICK_AUDIENCE 가
         module.was 의 입력이라 순환 참조가 되고 plan 이 Cycle 로 거부된다.)
      EOT
    }
  }

  # 잡이 만들어진 직후 첫 실행이 곧바로 나갈 수 있다. 그 시점에 호출 권한이 없으면
  # 첫 tick 이 403 으로 실패한다.
  depends_on = [google_cloud_run_v2_service_iam_member.call_tick_invoker]
}
