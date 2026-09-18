# Nature 리브랜딩: 공개 domains만 변경한다. Cloud Run/Hosting/GitHub ID는 기존 운영 대상을 보존한다.
# 구조적 설정만 둔다. 자격증명·키 성격의 값은 이 파일에 넣지 않는다
# (이 앱은 그런 값이 없다 — JWT 서명키는 Terraform 이 만들고 Secret Manager 에만 산다).

# shared/ 가 만든 것을 문자열로 가리킨다. remote state 를 읽지 않는 이유는 variables.tf 상단에.
project_id                      = "redhead-kr"
region                          = "asia-northeast3"
zone_name                       = "redhead"
dns_name                        = "redhead.kr."
artifact_registry_repository_id = "redhead"

firestore = {
  # 생성 후 변경 불가. Cloud Run 과 같은 리전에 둔다.
  location_id             = "asia-northeast3"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  deletion_policy         = "ABANDON"
}

domains = {
  app = "nature.redhead.kr"
  api = "nature-api.redhead.kr"
}

hosting = {
  # site_id 는 Firebase 전역 유일값이라 프로젝트 이름을 접두어로 붙였다.
  app_site_id = "redhead-jayeon-app"
  api_site_id = "redhead-jayeon-api"
}

cloud_run = {
  app_name = "jayeon-app"
  was_name = "jayeon-was"
  # 실제 이미지는 Cloud Build 가 밀어 넣는다. Terraform 은 이후 이미지 변경을 무시한다.
  bootstrap_image = "us-docker.pkg.dev/cloudrun/container/hello"
  cpu             = "1"
  # app(nginx 정적 서빙)은 512Mi 그대로 둔다.
  memory = "512Mi"
  # WAS 만 1Gi 로 올린다. 서버 통화분석이 전사문·분석 JSON 을 메모리에서 조립한다.
  # 공통 memory 를 올리면 nginx 컨테이너까지 같이 올라가 이득 없이 과금만 늘어난다.
  was_memory         = "1Gi"
  timeout            = "60s"
  max_instance_count = 3
  container_port     = 8080
}

# WAS 실제 이미지가 배포된 뒤에 true 로 바꾼다.
# 부트스트랩 hello 이미지에는 /healthz 가 없어서, 켠 채로 첫 apply 를 하면 리비전이 Ready 가
# 되지 못해 apply 자체가 실패한다.
enable_was_startup_probe = false

cicd = {
  location     = "global" # 기존 1세대 GitHub repository mapping 리전
  github_owner = "sslim7"
  app_repo     = "jayeon-app"
  was_repo     = "jayeon-was"
  # release 브랜치 커밋에 v 태그를 붙여 push 하면 배포된다.
  tag_regex = "^v.*$"
  disabled  = false
}

# sslim7/jayeon-was 를 콘솔에서 Cloud Build 에 연결한 뒤 true 로 바꾼다.
# 연결 전에 true 로 두면 트리거 생성이 실패하며, 다른 리소스는 일부 생성된 채 남을 수 있다.
enable_was_trigger = true

# ── 통화분석 서버 파이프라인 ────────────────────────────────────────────────

call_audio = {
  # 이름은 전역 유일값이다. 비워 두면 "{project_id}-call-audio" 로 파생된다.
  bucket_name = "redhead-kr-call-audio"
  # 🔴 사용자 확정: 1년(윤년 포함 366일). 이 날짜가 지나면 원본 오디오만 사라지고
  # 전사문·분석 결과는 Firestore 에 그대로 남는다. 줄이면 그만큼 과거 통화의 재분석이
  # 불가능해지며 되돌릴 수 없다.
  retention_days = 366
  # 웹뷰가 GCS 로 직접 PUT 한다. 목록에 없는 오리진은 에러 없이 브라우저에서만 막힌다.
  cors_origins = [
    "https://nature.redhead.kr",
    "http://localhost:3103",
  ]
}

call_ai = {
  # 1차 공급자. Vertex AI/Bedrock 으로 옮길 때 고칠 곳이 여기와 WAS 의 어댑터다.
  asr_provider = "alibaba"
  asr_model    = "qwen-audio-3.0-asr-flash-filetrans"
  llm_provider = "alibaba"
  llm_model    = "qwen3.7-plus"
  # 🔴 워크스페이스 전용 호스트다(스킴·경로 없이 호스트만). 실호출로 확인한 값이며,
  # 워크스페이스가 호스트명에 박혀 있어 `X-DashScope-WorkSpace` 헤더가 필요 없다.
  # 레거시 `dashscope-intl.aliyuncs.com` 도 살아 있지만 Alibaba 가 이 호스트를 권한다.
  # 경로는 용도마다 달라 서버가 붙인다: LLM 은 `/compatible-mode/v1`, ASR 은 `/api/v1`.
  base_url = "ws-f05u45izndv5glmp.ap-southeast-1.maas.aliyuncs.com"
  # 호스트에 이미 들어 있지만, 업로드 정책 발급 등 일부 호출이 따로 요구할 수 있어 남긴다.
  workspace_id = "ws-f05u45izndv5glmp"

  # ── 원가 단가 (2026-09-18 조사, 근거는 jayeon-was 의 docs/llms.md) ──────────
  # 🔴 위 asr_model / llm_model 을 바꾸면 여기도 반드시 함께 바꾼다(§variables.tf).
  #
  # 🔴 asr_usd_per_hour 만은 **알리바바가 공개 문서에 올려 두지 않은 값**이다. 제3자 공시
  # 단가(초당 $0.000035)와 자체 추정의 역산이 정확히 일치해 얻었다. **콘솔 청구서로
  # 대조할 것** — 비용의 85%가 받아쓰기라, 이 값이 틀리면 화면 금액이 통째로 틀어진다.
  asr_usd_per_hour = 0.126

  # qwen3.7-plus 국제 리전 공시 단가.
  # ⚠️ 출력에 $1.2 를 쓰지 마라 — 그건 구형 qwen-plus non-thinking 값이고 약 12% 적게 나온다.
  llm_usd_per_million_input_tokens  = 0.40
  llm_usd_per_million_output_tokens = 1.60

  # 실환율(조사 시점 1,385)보다 높게 잡은 값이다. 표시 금액이 실제보다 **적게** 나오는
  # 방향을 피하려는 선택이다 — 비용을 과소로 보다가 나중에 청구서에서 놀라는 쪽이 나쁘다.
  usd_to_krw = 1500
}

call_jobs = {
  scheduler_sa_id = "jayeon-call-tick"
  job_name        = "jayeon-call-tick"
  tick_path       = "/internal/calls/tick"
  schedule        = "* * * * *"
  time_zone       = "Etc/UTC"
  # 2026-09-18 WAS v0.1.3 배포로 /internal/calls/tick 이 열린 것을 확인하고 켰다
  # (인증 없는 호출이 404 가 아니라 401 로 떨어지는 것이 라우트가 있다는 증거다).
  # 🔴 되돌려 끄면 통화가 업로드만 되고 영영 분석되지 않는다 — 앱에는 「분석 중」 으로
  # 계속 남고 에러가 나지 않아 알람도 울리지 않는다.
  paused = false

  # jayeon-was 의 Cloud Run 서비스 URL(경로 없음). 스케줄러가 발급하는 OIDC 토큰의 `aud`
  # 이자 WAS 가 검증하는 값이다.
  #
  # 🔴 여기 문자열로 적혀 있는 이유는 순환 참조다 — module.was.uri 를 §run.tf 의 env 에
  # 넣으면 module.was 가 자기 출력을 입력으로 받게 되어 plan 이 Cycle 로 거부된다
  # (§variables.tf 의 call_jobs.audience).
  #
  # ⚠️ Cloud Run 서비스를 지우고 다시 만들면 이 URL 이 바뀐다. 그때 이 줄을 같이 고쳐야
  # 하며, 잊으면 §call-jobs.tf 의 precondition 이 apply 를 그 자리에서 멈춰 알려 준다.
  audience = "https://jayeon-was-km2zqs27fa-du.a.run.app"
}
