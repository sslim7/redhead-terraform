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
}

call_jobs = {
  scheduler_sa_id = "jayeon-call-tick"
  job_name        = "jayeon-call-tick"
  tick_path       = "/internal/calls/tick"
  schedule        = "* * * * *"
  time_zone       = "Etc/UTC"
  # 🔴 WAS 에 /internal/calls/tick 이 배포된 뒤에 false 로 바꾼다.
  # 먼저 켜면 매분 404 가 쌓여 Cloud Scheduler 로그가 실패로 도배된다.
  paused = true
}
