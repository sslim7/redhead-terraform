# Cloud Run 서비스 2개.
#
# ── 🔴 Terraform 이 서비스를 먼저 만들어야 한다 ──────────────────────────────
#
# 두 모듈 모두 부트스트랩 이미지(us-docker.pkg.dev/cloudrun/container/hello)로 껍데기를
# 만든다. 실제 이미지는 Cloud Build 가 밀어 넣고, modules/cloud-run 의
# lifecycle.ignore_changes 가 다음 apply 의 재적용을 막는다.
#
# 순서를 뒤집으면 안 된다. Terraform 없이 `gcloud run deploy` 가 먼저 돌면 **서비스를 자기
# 기본 설정으로 만들어 버린다** — 포트, IAM(공개 여부), CPU 할당, 서비스 계정이 전부 CI 가
# 정한 값이 되고, 그다음 apply 가 그걸 이 파일의 값으로 되돌리려 한다. 매 배포마다 두 주체가
# 같은 서비스를 서로 되돌리는 상태가 되고, 어느 쪽이 이겼는지는 마지막에 돈 쪽이 정한다.
#
# ── 🔴 앞단에 Firebase Hosting 프록시가 있다 ─────────────────────────────────
#
# 요청은 `nature.redhead.kr → Hosting → rewrite → Cloud Run` 경로로 들어온다(§hosting.tf).
# 그래서 컨테이너가 보는 것은 브라우저의 직접 연결이 아니다:
#   - 모든 요청에 `Via` 헤더가 붙는다(Google Frontend 가 넣는다)
#   - **클라이언트 IP 는 소켓의 원격 주소가 아니라 `X-Forwarded-For` 에 있다.** 소켓 주소를
#     그대로 쓰면 전부 구글 프론트엔드 IP 로 보인다 — 레이트리밋이나 접속 로그를 그 값으로
#     구현하면 모든 사용자가 한 IP 로 뭉쳐 통째로 막히거나 통째로 통과한다.
#     (jayeon-was 는 이미 XFF 우선으로 구현돼 있다.)

# ── jayeon-app : Expo 웹 빌드를 nginx 로 서빙 ────────────────────────────────
module "app" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  location              = var.region
  name                  = var.cloud_run.app_name
  image                 = var.cloud_run.bootstrap_image
  service_account_email = module.app_service_account.email
  container_port        = var.cloud_run.container_port

  resources = {
    cpu    = var.cloud_run.cpu
    memory = var.cloud_run.memory
    # nginx 정적 서빙이라 응답을 보낸 뒤에 할 일이 없다. 기본값(true)을 그대로 둬
    # 요청 처리 시간만 과금한다.
    cpu_idle = true
  }

  scaling = {
    min_instance_count = 0
    max_instance_count = var.cloud_run.max_instance_count
    concurrency        = 80
  }

  # 🔴 **환경변수가 없다. 그리고 넣어도 아무 일이 일어나지 않는다.**
  #
  # `EXPO_PUBLIC_*` 는 **빌드 시점에 웹 번들로 인라인**된다. 이 컨테이너가 하는 일은 그렇게
  # 이미 만들어진 정적 파일을 nginx 가 내보내는 것뿐이라, Cloud Run 환경변수로 값을 주면
  # 리비전에는 남지만 브라우저가 받는 값은 **옛 번들의 값 그대로**다.
  #
  # 증상이 고약하다 — 설정을 바꿨고 리비전도 새로 떴고 에러도 없는데 동작만 안 바뀐다.
  # `gcloud run services describe` 로 보면 새 값이 멀쩡히 들어 있다.
  #
  # 값을 바꾸려면 **Cloud Build 트리거의 substitution** 을 고치고 이미지를 다시 빌드해야 한다
  # (§cicd.tf). 이 파일이 아니다.
  env = {}

  # Hosting rewrite 가 앞단이라 Cloud Run 자체는 공개여야 한다.
  # Hosting 은 Cloud Run 을 인증 없이 호출하므로, 여기서 닫으면 모든 요청이 403 이 된다.
  allow_unauthenticated = true

  # startup probe 를 두지 않는다. nginx 는 기동하면 곧바로 리스닝하고, 확인할 외부 의존이 없다.
  # (WAS 와 달리 Firestore 왕복 같은 "연결이 되는지" 를 볼 대상이 없다.)

  timeout = var.cloud_run.timeout
  labels  = { component = "app" }
}

# ── jayeon-was : Go 1.26 / net/http / distroless 정적 바이너리 ───────────────
module "was" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  location              = var.region
  name                  = var.cloud_run.was_name
  image                 = var.cloud_run.bootstrap_image
  service_account_email = module.was_service_account.email

  # 코드가 PORT 를 읽고 미설정일 때만 8080 으로 떨어진다. Cloud Run 이 이 값을 PORT 로
  # 주입하므로 실제로는 항상 이 포트를 쓴다.
  container_port = var.cloud_run.container_port

  resources = {
    cpu    = var.cloud_run.cpu
    memory = var.cloud_run.memory
    # 기본값(true)을 그대로 둔다 — **응답을 보낸 뒤에 도는 작업이 현재 없다.**
    # 백그라운드 고루틴(지연 처리, 푸시 발송 같은 것)이 생기면 그때 false 로 내려야 한다.
    # 그대로 두면 응답 직후 CPU 가 스로틀돼 그 작업이 중간에 끊기고, 증상은 "가끔 안 된다"
    # 로만 나타난다.
    cpu_idle = true
  }

  scaling = {
    min_instance_count = 0
    max_instance_count = var.cloud_run.max_instance_count
    concurrency        = 80
  }

  env = {
    # 🔴 미설정이면 WAS 가 **기동하지 않는다.** Firestore 클라이언트가 프로젝트를 알 수 없어서다.
    # ADC 에서 유추되기를 기대하지 말 것 — 코드가 이 값을 직접 요구한다.
    GOOGLE_CLOUD_PROJECT = var.project_id

    # 🔴 CORS 허용 오리진 목록.
    #
    # **목록에 없는 오리진은 에러가 나지 않는다.** WAS 는 응답에 CORS 헤더를 조용히 안 붙일
    # 뿐이고, 서버 로그·응답 코드·지연시간이 전부 정상으로 보인다. 막히는 것은 브라우저이고,
    # 그래서 curl 로는 재현되지 않는다. 증상은 프론트엔드 콘솔의 CORS 에러 하나뿐이다.
    #
    # 스킴을 포함한 정확한 오리진이어야 한다. 끝에 슬래시를 붙이면 매칭되지 않는다.
    #
    # ⚠ 어드민 SPA 가 생기면(별도 서브도메인) **여기에 더해야 한다.** 브라우저는 같은 API 를
    # 쓰더라도 다른 서브도메인을 다른 오리진으로 본다. 그때 이 값을 빼먹으면 어드민 화면은
    # 멀쩡히 뜨고 API 호출만 전부 막힌다.
    CORS_ALLOWED_ORIGINS = join(",", distinct(["https://${var.domains.app}", "https://${var.legacy_domains.app}"]))

    # 🔴 FIRESTORE_EMULATOR_HOST 를 **절대 넣지 마라.**
    #
    # 이 변수는 값이 존재하는 것만으로 동작이 바뀐다 — Firestore SDK 가 실제 Firestore 대신
    # 그 주소의 에뮬레이터를 찾아간다. 운영 리비전에 실수로 들어가면 WAS 가 존재하지 않는
    # 에뮬레이터에 붙으려 하고, 모든 데이터 API 가 연결 실패로 죽는다. 빈 문자열로 두는 것도
    # 안전하지 않다(SDK 구현에 따라 "설정됨" 으로 볼 수 있다). 아예 넣지 않는 것이 유일하게
    # 안전한 상태다.
  }

  secret_env = {
    # 🔴 서로 **다른** 시크릿이어야 한다. 같은 시크릿을 두 변수에 연결하면 그 순간 WAS 가
    # 기동을 거부하고 배포가 리비전 실패로 떨어진다. 이유는 secrets.tf 주석에.
    JWT_SECRET = { secret = module.secrets.secret_ids["JWT_SECRET"] }
    # ⚠️ 이 줄을 지우면 WAS 는 기동하지만 어드민 라우트를 등록하지 않는다. 어드민 API 가
    # 전부 404 이고 기동·헬스체크는 정상이라 알람이 울리지 않는다.
    ADMIN_JWT_SECRET = { secret = module.secrets.secret_ids["ADMIN_JWT_SECRET"] }
  }

  # ── 🔴 헬스체크 경로가 둘이고, 바꿔 쓰면 안 된다 ──────────────────────────
  #
  #   startup probe(아래)  → `/healthz`
  #   외부 감시·스모크 체크 → `/health`
  #
  # 프로브는 Google Frontend 를 거치지 않고 **컨테이너의 포트로 직접** 오므로 `/healthz` 가
  # 그대로 도착한다. 반면 밖에서 오는 요청의 `/healthz` 는 **Google Frontend 가 정확히 그
  # 경로를 가로채 자체 404(HTML)를 돌려준다** — run.app 주소로 불러도, Hosting 을 경유해도
  # 컨테이너까지 오지 않는다. 그래서 감시 대상 경로로 `/healthz` 를 쓰면 "프로브는 되는데
  # 밖에서는 404" 라는 모양이 되고, 서비스가 멀쩡한데 감시가 빨간불이 된다(또는 그 반대로
  # 해석해 정상이라 믿는다).
  #
  # 임계값을 넉넉히 잡는 이유 — 핸들러가 Firestore 왕복을 포함하고(3초 타임아웃), 첫 프로브는
  # 콜드스타트 + 첫 연결 수립과 겹친다. IAM 전파가 아직 끝나지 않아 몇 번 실패하는 구간도
  # 있다. 임계를 낮게 잡으면 정상 기동 중인 리비전이 실패로 처리돼 배포가 롤백된다.
  # 기동 예산 = period_seconds × failure_threshold = 100초.
  #
  # 🔴 **기본값이 false 인 것이 중요하다.** 부트스트랩 hello 이미지에는 /healthz 가 없어서,
  # 프로브를 켠 채로 첫 apply 를 하면 리비전이 Ready 가 되지 못해 **apply 자체가 실패한다.**
  # WAS 의 진짜 이미지가 배포된 뒤 enable_was_startup_probe = true 로 바꿔 다시 apply 한다.
  startup_probe = var.enable_was_startup_probe ? {
    path              = "/healthz"
    period_seconds    = 10
    timeout_seconds   = 5
    failure_threshold = 10
  } : null

  # 인증은 앱 레벨 JWT 가 한다. Hosting rewrite 가 앞단이라 Cloud Run 자체는 공개여야 한다.
  allow_unauthenticated = true

  timeout = var.cloud_run.timeout
  labels  = { component = "was" }

  # module.secrets 를 통째로 기다린다. secret_ids 출력만 참조하면 시크릿 리소스에만 의존해
  # secretAccessor 바인딩보다 먼저 리비전이 만들어질 수 있고, 그러면 시크릿을 못 읽어
  # 기동에 실패한다(JWT_SECRET 이 없으면 WAS 는 기동을 거부한다).
  # Firestore 및 런타임 IAM도 기동 전에 준비한다. probe를 켠 리비전은 DB 접근을 확인한다.
  depends_on = [module.secrets, module.firestore, module.was_service_account]
}
