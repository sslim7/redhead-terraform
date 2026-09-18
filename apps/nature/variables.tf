# 공개 이름은 Nature다. hosting/cloud_run/cicd 물리 ID와 기존 GitHub 연결은 파괴적 재생성을 피하기 위해 유지한다.
# ── shared/ 와의 결합 ───────────────────────────────────────────────────────
#
# 🔴 **shared 의 remote state 를 읽지 않는다.** `terraform_remote_state` 로 프로젝트 ID·존
# 이름·저장소 ID 를 가져오는 방법도 있지만 쓰지 않았다. 이유는 두 가지다.
#
#   1. 앱 루트가 shared state 파일 **전체**를 읽을 권한을 갖게 된다. 그 안에는 다른 앱의
#      값도, 그리고 shared 가 관리하는 모든 것의 속성이 평문으로 들어 있다.
#   2. shared 의 출력 구조가 바뀌는 순간 **모든 앱의 plan 이 동시에 깨진다.** 앱을 늘리는
#      것이 목적인 저장소에서 앱 수에 비례해 깨지는 결합을 만들 이유가 없다.
#
# 대신 문자열로 직접 받는다. 존 이름·프로젝트 ID·리전은 **생성 후 변경 불가**한 값이라
# 어차피 바뀌지 않고, 틀리면 apply 가 곧바로 실패한다(존재하지 않는 존을 가리키면 404).
# 조용히 잘못될 여지가 없는 값이라 느슨한 결합이 더 안전하다.

variable "project_id" {
  description = "GCP 프로젝트 ID. shared/ 가 만든 우산 프로젝트다"
  type        = string
  default     = "redhead-kr"
}

variable "region" {
  description = "Cloud Run·Cloud Build·Artifact Registry 리전. 이미지 pull 이 리전 내부에서 끝나도록 전부 같은 값을 쓴다"
  type        = string
  default     = "asia-northeast3"
}

variable "zone_name" {
  description = "shared/ 가 만든 Cloud DNS 관리 영역의 리소스 이름. 이 루트는 영역을 만들지 않고 자기 서브도메인 레코드만 넣는다"
  type        = string
  default     = "redhead"
}

variable "dns_name" {
  description = "관리 영역의 도메인. 끝 점을 포함해야 한다 (예: redhead.kr.)"
  type        = string
  default     = "redhead.kr."

  validation {
    condition     = endswith(var.dns_name, ".")
    error_message = "dns_name 은 끝 점을 포함해야 한다 (예: redhead.kr.)."
  }
}

variable "artifact_registry_repository_id" {
  description = <<-EOT
    shared/ 가 만든 Artifact Registry 저장소 ID. 이미지 경로는
    {region}-docker.pkg.dev/{project_id}/{이 값}/{서비스} 가 된다.

    저장소 자체는 shared 소유다. 이 루트는 저장소를 만들지 않고, 배포 SA 에게 writer 권한만
    _iam_member 로 덧붙인다(§iam.tf).
  EOT
  type        = string
  default     = "redhead"
}

variable "firestore" {
  description = "Firestore 데이터베이스 설정. 데이터는 앱의 것이라 앱 루트가 소유한다(§firestore.tf)"
  type = object({
    # 🔴 생성 후 변경 불가. Cloud Run 과 같은 리전에 둔다.
    location_id = optional(string, "asia-northeast3")
    # 운영 데이터 보호. 아래 두 값이 terraform destroy 로부터 DB 를 지킨다.
    delete_protection_state = optional(string, "DELETE_PROTECTION_ENABLED")
    deletion_policy         = optional(string, "ABANDON")
  })
  default = {}
}

variable "domains" {
  description = <<-EOT
    이 앱이 쓰는 도메인. redhead.kr 하위의 서브도메인 둘뿐이다.

    apex(redhead.kr)는 여기 없다. apex 레코드는 shared/ 소유이며, 그 자리에는 purelymail
    메일 레코드(MX·SPF·DKIM·DMARC)가 살고 있다 — 자세한 경고는 dns.tf 상단을 보라.
  EOT
  type = object({
    app = optional(string, "nature.redhead.kr")
    api = optional(string, "nature-api.redhead.kr")
  })
  default = {}
}

variable "hosting" {
  description = <<-EOT
    Firebase Hosting 사이트 ID.

    🔴 site_id 는 프로젝트가 아니라 **Firebase 전역**에서 유일해야 한다. `jayeon-app` 같은
    흔한 이름은 남이 선점했을 수 있어 프로젝트 이름을 접두어로 둔다. 이미 쓰이는 값이면
    apply 가 실패한다.

    ⚠ 이 값을 바꾸면 사이트가 새로 만들어진다. 커스텀 도메인 매핑과 dns.tf 의 CNAME 대상까지
    함께 갈아엎어야 하고, 그 사이 도메인이 죽는다.
  EOT
  type = object({
    app_site_id = optional(string, "redhead-jayeon-app")
    api_site_id = optional(string, "redhead-jayeon-api")
  })
  default = {}
}

variable "cloud_run" {
  description = <<-EOT
    Cloud Run 서비스 공통 설정.

    둘 다 cpu_idle 은 기본값(true)이다 — jayeon-app 은 nginx 정적 서빙이고, jayeon-was 도
    현재 응답 후에 도는 백그라운드 작업이 없다. 그런 작업이 생기면 그 서비스만 false 로
    내려야 하고(§run.tf), 그때까지는 요청 처리 시간만 과금한다.

    min_instance_count 는 0 이다. 1 로 올리면 1 vCPU 를 월 730시간 상시 점유해 무료 한도
    (180,000 vCPU-초/월)를 크게 넘는다. 대가는 첫 요청의 콜드스타트다.
  EOT
  type = object({
    app_name = optional(string, "jayeon-app")
    was_name = optional(string, "jayeon-was")
    # 🔴 최초 apply 용 부트스트랩 이미지. 실제 이미지는 Cloud Build 가 밀어 넣고
    # 모듈의 lifecycle.ignore_changes 가 재적용을 막는다(§run.tf).
    bootstrap_image = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")
    cpu             = optional(string, "1")
    # jayeon-app(nginx 정적 서빙)의 메모리. 정적 파일을 내주는 데 더 필요한 것이 없다.
    memory = optional(string, "512Mi")
    # 🔴 jayeon-was 만 따로 받는다. **공통 memory 를 올리지 마라** — 그러면 nginx 컨테이너까지
    # 같이 올라가 아무 이득 없이 요청당 메모리 과금만 두 배가 된다.
    #
    # 1Gi 로 올리는 이유: 서버 통화분석이 30분 통화의 전사문 전체와 분석 JSON 을 메모리에서
    # 조립한다(§run.tf 의 CALL_* 환경변수). 512Mi 에서 넘치면 Cloud Run 은 에러가 아니라
    # **컨테이너를 죽인다** — 클라이언트는 503 을 받고 로그에는 "Memory limit exceeded" 한 줄만
    # 남아, 원인이 코드 버그처럼 보인다. 그리고 그 리비전에 붙어 있던 다른 요청까지 함께 끊긴다.
    was_memory         = optional(string, "1Gi")
    timeout            = optional(string, "60s")
    max_instance_count = optional(number, 3)
    # 컨테이너가 리스닝하는 포트. 두 서비스 모두 8080 이다
    # (WAS 는 PORT 환경변수를 읽고 미설정일 때만 8080 으로 떨어진다. Cloud Run 이 PORT 를
    # 주입하므로 실제로는 항상 이 값을 본다).
    container_port = optional(number, 8080)
  })
  default = {}
}

variable "enable_was_startup_probe" {
  description = <<-EOT
    jayeon-was 에 startup probe(/healthz)를 붙일지 여부.

    🔴 **기본값은 false 이고, 그 이유가 순서다.** 부트스트랩 이미지
    (us-docker.pkg.dev/cloudrun/container/hello)에는 /healthz 가 없다. 프로브를 켠 채로 첫
    apply 를 하면 리비전이 Ready 가 되지 못해 **apply 자체가 실패한다** — 서비스 껍데기조차
    만들어지지 않으므로 Cloud Build 가 배포할 대상도 없어진다.

    순서: false 로 apply → Cloud Build 가 WAS 실제 이미지를 배포 → 이 값을 true 로 바꿔
    다시 apply. 그때부터 배포 실패가 리비전 단계에서 걸러진다.
  EOT
  type        = bool
  default     = false
}

variable "cicd" {
  description = <<-EOT
    Cloud Build 트리거 설정.

    🔴 선행 조건 — GitHub 저장소 연결은 Terraform 으로 만들 수 없다. 콘솔에서 Cloud Build
    GitHub App 을 1회 설치하고 저장소를 연결해야 하며, 연결 전에 apply 하면 트리거 생성이
    실패한다(§cicd.tf).
  EOT
  type = object({
    # 1세대 GitHub 연결은 global에 존재한다. Cloud Run 리전과 별개로 같은 연결 리전을 사용한다.
    location     = optional(string, "global")
    github_owner = optional(string, "sslim7")
    app_repo     = optional(string, "jayeon-app")
    was_repo     = optional(string, "jayeon-was")
    # release 브랜치 커밋에 v 태그를 붙여 push 하면 배포된다.
    # 앵커(^)가 없으면 의도보다 넓게 잡힌다 — 자세한 한계는 cicd.tf 주석에.
    tag_regex = optional(string, "^v.*$")
    disabled  = optional(bool, false)
  })
  default = {}
}

variable "enable_was_trigger" {
  description = <<-EOT
    jayeon-was 의 Cloud Build 트리거를 만들지 여부.

    기본값은 false 다. 콘솔에서 GitHub 저장소를 연결한 뒤 활성화한다.
    연결되지 않은 저장소의 트리거 생성은 실패한다. Terraform apply 는 원자적이지 않아
    그때까지 성공한 리소스는 남고, 연결을 완료한 뒤 재실행해야 한다.

    sslim7/jayeon-was 를 콘솔에서 연결한 뒤 true 로 바꾼다.
  EOT
  type        = bool
  default     = false
}

# 리브랜딩 이행 동안 이전 웹/API 도메인과 인증서를 유지한다.
variable "legacy_domains" {
  description = "기존 클라이언트 호환 도메인. 새 도메인 검증 및 별도 정리 승인 전 유지한다"
  type        = object({ app = string, api = string })
  default     = { app = "jayeon.redhead.kr", api = "jayeon-api.redhead.kr" }
}

# ── 통화분석 서버 파이프라인 ────────────────────────────────────────────────

variable "call_audio" {
  description = <<-EOT
    통화 녹음 원본 버킷 설정(§call-audio.tf).

    🔴 retention_days 는 **버킷의 lifecycle 규칙과 WAS 의 CALL_AUDIO_RETENTION_DAYS 가
    함께 읽는 단일 출처**다. 여기만 고치면 둘이 같이 움직인다. 따로 적으면 앱이 약속하는
    보관 기간과 버킷이 실제로 지키는 기간이 갈라지고, 그 불일치는 1년 뒤에 드러난다.

    🔴 cors_origins 에 없는 오리진은 **에러를 내지 않는다.** GCS 는 CORS 헤더를 조용히
    안 붙일 뿐이고, 막는 것은 브라우저다. curl 로는 재현되지 않으며 증상은 웹뷰 콘솔의
    CORS 에러 하나뿐이다. 스킴을 포함한 정확한 오리진이어야 하고 끝에 슬래시를 붙이면
    매칭되지 않는다. 포트가 다르면 다른 오리진이다.
  EOT
  type = object({
    # null 이면 "{project_id}-call-audio" 로 파생시킨다. 이름은 전역 유일값이다.
    bucket_name = optional(string)
    # 🔴 사용자 확정값: 1년(윤년 포함 366일). 이 값을 줄이면 그만큼 과거 통화의 재분석이
    # 불가능해진다 — 되돌릴 수 없다.
    retention_days = optional(number, 366)
    cors_origins = optional(list(string), [
      "https://nature.redhead.kr",
      # 로컬 개발. 🔴 운영 버킷에 붙는 설정이므로 이 줄은 개발 머신의 브라우저가 운영
      # 녹음을 올릴 수 있다는 뜻이다. 서명 URL 없이는 아무것도 못 하므로 실질 위험은
      # 서명 URL 발급 권한에 있고, 그건 WAS 의 인증이 지킨다.
      "http://localhost:3103",
    ])
  })
  default = {}

  validation {
    condition     = var.call_audio.retention_days >= 1
    error_message = "retention_days 는 1 이상이어야 한다."
  }

  validation {
    condition     = alltrue([for o in var.call_audio.cors_origins : can(regex("^https?://", o)) && !endswith(o, "/")])
    error_message = "cors_origins 는 스킴(http:// 또는 https://)을 포함하고 끝에 슬래시가 없어야 한다."
  }
}

variable "call_ai" {
  description = <<-EOT
    통화분석 공급자 설정. 값은 전부 평문 환경변수로 WAS 에 간다(키는 Secret Manager 다).

    🔴 **1차 공급자는 Alibaba Model Studio 지만 교체 가능하게 설계 중이다.** provider 와
    model 을 나눠 둔 것이 그 이음매다 — Vertex AI/Bedrock 으로 옮길 때 고칠 곳은
    이 값들과 WAS 의 어댑터이고, 인프라(버킷·시크릿·tick)는 그대로 쓴다.

    🔴 ASR 과 LLM 을 따로 두는 이유: 둘은 같은 공급자일 이유가 없다. 전사만 먼저 다른
    공급자로 옮기는 상황이 실제로 생긴다(음질·언어·가격이 모델마다 다르다).
  EOT
  type = object({
    asr_provider = optional(string, "alibaba")
    asr_model    = optional(string, "qwen-audio-3.0-asr-flash-filetrans")
    llm_provider = optional(string, "alibaba")
    llm_model    = optional(string, "qwen3.7-plus")

    # 🔴 **싱가포르(국제) 엔드포인트다.** 중국 본토 엔드포인트(dashscope.aliyuncs.com)와
    # API 키가 서로 호환되지 않는다 — 싱가포르에서 발급한 키로 본토를 부르면 401 이고
    # 그 반대도 마찬가지다. 에러가 "인증 실패" 로만 나와 키가 잘못된 줄 알고 다시 발급받게
    # 만드는데, 실제로는 이 URL 이 틀린 것이다.
    #
    # ⚠️ compatible-mode 는 OpenAI 호환 경로다. WAS 가 DashScope 네이티브 SDK 를 쓰면
    # 경로가 /api/v1 이어야 한다. 이 값과 WAS 의 클라이언트 모드가 반드시 짝이어야 한다.
    base_url = optional(string, "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")

    # 기본 워크스페이스를 쓰면 빈 문자열이다. 빈 값이면 WAS 가 워크스페이스 헤더를
    # 붙이지 않아야 한다 — 빈 값을 그대로 헤더에 실으면 공급자가 400 을 돌려준다.
    workspace_id = optional(string, "")

    # ── 원가 단가 ────────────────────────────────────────────────────────────
    #
    # 통화 한 건에 실제로 든 돈을 원화로 계산해 앱에 보여 주기 위한 값이다.
    # 계산은 WAS 가 한다 — 단가가 바뀌어도 앱 배포가 필요 없어야 하기 때문이다.
    #
    # 🔴 **이 네 값이 asr_model / llm_model 바로 옆에 있는 것이 요점이다.** 모델을 바꾸면
    # 단가도 함께 바꿔야 하는데, 다른 파일에 두면 모델만 갈고 단가는 옛 것으로 남는다.
    # 그러면 새 공급자의 사용량에 옛 공급자 단가가 곱해진 금액이 **조용히** 뜬다 —
    # 화면은 멀쩡하고 숫자만 틀리므로 알아챌 방법이 없다.
    #
    # 🔴 **기본값을 두지 않는다.** 그럴듯한 단가를 박아 두면 설정 실수가 「그럴듯하지만
    # 틀린 금액」으로 나타나고, 그 화면은 진짜와 구분되지 않는다. 사용자는 이 숫자로
    # 공급자 교체를 판단하므로, 틀린 금액을 보여 주느니 안 보여 주는 쪽이 낫다.
    # WAS 는 **네 값이 전부 있을 때만** 계산하고, 하나라도 비면 비용을 아예 내보내지
    # 않는다(앱은 비용 칸을 그리지 않는다). 일부만 채우면 「받아쓰기 83원」만 떠서
    # 사용자가 그것을 한 건의 총액으로 읽는다.
    #
    # ⚠️ 단위가 요금표와 같아야 한다. 시간당·100만 토큰당으로 받는 이유는 공급자
    # 요금표가 그 단위로 적혀 있어 **그대로 옮겨 적을 수 있기** 때문이다. 초당으로
    # 환산해 적다가 0을 하나 빠뜨리면 금액이 10배 틀리는데 화면에서 알 수 없다.
    #
    # 현재 값의 출처와 검산은 jayeon-was 의 docs/llms.md 에 있다.
    # 🔴 그중 asr_usd_per_hour 만은 **알리바바가 공개 문서에 올려 두지 않은 값**이다.
    # 제3자 공시 단가와 자체 추정의 역산이 일치해 얻었다. **콘솔 청구서로 대조할 것** —
    # 이 값이 틀리면 화면의 금액이 통째로 틀어진다.
    asr_usd_per_hour = optional(number)

    # ⚠️ 출력 단가에 구형 qwen-plus 값($1.2)을 쓰지 마라. qwen3.7-plus 는 $1.6 이고,
    # 섞으면 약 12% 과소 계산된다 — 적게 나와서 의심하지 않게 되는 방향이라 더 나쁘다.
    llm_usd_per_million_input_tokens  = optional(number)
    llm_usd_per_million_output_tokens = optional(number)

    # USD→KRW. 단가는 요금표 그대로 USD 로 적고 환산은 여기서 한 번만 한다 — 단가마다
    # 원화로 미리 곱해 두면 환율이 바뀔 때 고칠 자리가 세 군데가 된다.
    #
    # ⚠️ 고정값이라 시간이 지나면 어긋난다. 실시간 조회를 붙이지 않은 이유는 100원 안팎의
    # 표시에서 환율이 몇 % 움직여야 몇 원 차이이고, 그 정밀도를 위해 외부 의존을 하나 더
    # 만들 값어치가 없기 때문이다. 크게 벌어지면 이 값을 갱신한다.
    # 🔴 0 을 넣지 마라. 모든 금액이 0원이 되어 **공짜로 보인다.** WAS 는 환율 0 을
    # 「설정 없음」으로 취급해 비용을 내보내지 않는다(단가 0 은 무료 구간으로 인정한다).
    usd_to_krw = optional(number)
  })
  default = {}

  # 🔴 네 값은 **전부 채우거나 전부 비우거나** 둘 중 하나다. 일부만 채운 상태는 WAS 에서
  # 조용히 「비용 없음」이 되므로, 그 실수를 apply 시점에 잡는다.
  validation {
    condition = alltrue([
      for v in [
        var.call_ai.asr_usd_per_hour,
        var.call_ai.llm_usd_per_million_input_tokens,
        var.call_ai.llm_usd_per_million_output_tokens,
        var.call_ai.usd_to_krw,
      ] : v != null
      ]) || alltrue([
      for v in [
        var.call_ai.asr_usd_per_hour,
        var.call_ai.llm_usd_per_million_input_tokens,
        var.call_ai.llm_usd_per_million_output_tokens,
        var.call_ai.usd_to_krw,
      ] : v == null
    ])
    error_message = "call_ai 의 단가 네 값(asr_usd_per_hour, llm_usd_per_million_input_tokens, llm_usd_per_million_output_tokens, usd_to_krw)은 전부 채우거나 전부 비워야 한다. 일부만 채우면 WAS 가 비용을 아예 내보내지 않아 화면에서 알아챌 수 없다."
  }

  validation {
    condition     = var.call_ai.usd_to_krw == null || try(var.call_ai.usd_to_krw > 0, false)
    error_message = "call_ai.usd_to_krw 는 0보다 커야 한다. 0이면 모든 금액이 0원이 되어 공짜로 보인다."
  }
}

variable "call_jobs" {
  description = <<-EOT
    통화분석 작업 스윕(tick) 설정(§call-jobs.tf).

    🔴 **paused 기본값은 true 이고, 그 이유가 순서다.** WAS 에 tick_path 가 배포되기 전에
    켜면 매분 404 가 쌓이고 Cloud Scheduler 로그가 실패로 도배된다.
    순서: paused = true 로 apply → WAS 배포 → false 로 바꿔 다시 apply.
    (enable_was_startup_probe 와 같은 관례다.)
  EOT
  type = object({
    # account_id 규칙: 소문자로 시작하는 6~30자 소문자/숫자/하이픈.
    scheduler_sa_id = optional(string, "jayeon-call-tick")
    job_name        = optional(string, "jayeon-call-tick")
    # 🔴 이 경로를 바꾸면 WAS 의 라우트도 같이 바꿔야 한다. 어긋나면 매분 404 이고
    # 서비스의 다른 부분은 전부 정상이라 알람이 울리지 않는다.
    tick_path = optional(string, "/internal/calls/tick")
    schedule  = optional(string, "* * * * *")
    time_zone = optional(string, "Etc/UTC")
    paused    = optional(bool, true)

    # tick OIDC 토큰의 `aud` 클레임. Cloud Scheduler 가 이 값으로 토큰을 발급하고
    # (§call-jobs.tf 의 oidc_token), WAS 가 CALL_TICK_AUDIENCE 로 같은 값을 검증한다
    # (§run.tf). **둘이 갈라지면 매분 403 이다.**
    #
    # 🔴 **왜 `module.was.uri` 를 직접 쓰지 않고 변수로 받는가 — 순환 참조 때문이다.**
    # 이 값은 module.was 의 입력(§run.tf 의 env 맵)으로 들어간다. 거기에 module.was.uri 를
    # 적으면 module.was → 자기 자신이 되어 terraform 이 "Cycle" 로 plan 을 거부한다.
    # 즉 이 하드코딩은 게으름이 아니라 그래프 제약이다. **되돌리지 마라** — 되돌리는 순간
    # apply 가 아니라 plan 단계에서 깨지고, 그 에러 메시지만 봐서는 이유를 알 수 없다.
    #
    # 🔴 **경로를 붙이지 않는 서비스 URL 이다.** `https://jayeon-was-....run.app` 까지이며
    # tick_path 는 붙이지 않는다. 경로가 붙은 audience 는 Cloud Run 이 토큰을 직접 검증하는
    # 구성(allow_unauthenticated = false)에서 403 이 된다.
    #
    # ⚠️ Cloud Run 서비스를 지우고 다시 만들면 URL 이 바뀐다. 그때 이 값을 같이 바꾸지
    # 않으면 스케줄러는 옛 URL 로 토큰을 발급하고 WAS 는 새 URL 을 기대해 매분 403 이다.
    # 그 사고를 막는 것이 §call-jobs.tf 의 precondition 이다 — 값이 실제 서비스 URL 과
    # 다르면 apply 가 그 자리에서 멈춘다.
    audience = optional(string)
  })
  default = {}

  validation {
    condition     = startswith(var.call_jobs.tick_path, "/")
    error_message = "tick_path 는 슬래시로 시작해야 한다."
  }

  # 값이 있으면 https 스킴이고 경로가 없어야 한다.
  # split("/", "https://host") == ["https:", "", "host"] 이므로 길이 3 이 "경로 없음" 이다.
  # 끝에 슬래시가 하나만 더 붙어도 길이가 4 가 되어 여기서 걸린다.
  validation {
    condition = (
      var.call_jobs.audience == null ||
      (startswith(coalesce(var.call_jobs.audience, ""), "https://") &&
      length(split("/", coalesce(var.call_jobs.audience, ""))) == 3)
    )
    error_message = "call_jobs.audience 는 https:// 로 시작하고 경로가 없는 서비스 URL 이어야 한다 (예: https://jayeon-was-xxxx-du.a.run.app). 끝 슬래시도 붙이지 마라."
  }
}
