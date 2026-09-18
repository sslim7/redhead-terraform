# Cloud Run 기본 서비스 계정(Compute Engine 기본 SA)은 프로젝트 편집자 권한을 갖는다.
# 서비스마다 전용 SA 를 만들어 필요한 권한만 준다.
#
# 우산 프로젝트라 계정 이름에 앱 접두어(jayeon-)를 붙인다. 프로젝트 하나에 여러 앱의 SA 가
# 섞여 살고, account_id 는 프로젝트 안에서 유일해야 하므로 접두어가 없으면 다음 앱과 충돌한다.

# ── 런타임 ──────────────────────────────────────────────────────────────────

# jayeon-app(Expo 웹 정적 빌드 → nginx) 런타임.
#
# 프로젝트 역할이 하나도 없다. 이 컨테이너 안에서 도는 것은 이미 만들어진 정적 파일을 내주는
# nginx 뿐이고 GCP API 를 전혀 호출하지 않는다. "웹앱이니까 뭔가 필요할 것" 이라는 직관으로
# 여기에 역할을 붙이지 말 것 — 권한이 필요한 쪽은 jayeon-was 이고, 이 SA 에 붙은 권한은
# 브라우저로 내려가는 정적 파일 서버가 프로젝트를 건드릴 수 있게 만들 뿐이다.
module "app_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "jayeon-app-run"
  display_name = "Nature 웹앱 Cloud Run runtime"
  description  = "Expo 웹 정적 빌드를 nginx 로 서빙한다. GCP API 를 호출하지 않아 역할이 없다"

  project_roles = []
}

# jayeon-was(Go 백엔드) 런타임.
#
# Firestore 와 통화 녹음 버킷을 쓴다. Cloud SQL 은 없다.
# 자격증명은 ADC 만 쓴다 — 키 파일을 만들지 않으므로 이 SA 로 도는 것이 곧 인증이다.
module "was_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "jayeon-was-run"
  display_name = "Nature WAS Cloud Run runtime"
  description  = "Go 백엔드 런타임. Firestore(Native)·통화 녹음 버킷·자기 시크릿만 읽고 쓴다"

  project_roles = [
    # Firestore 문서 읽기·쓰기. 없으면 모든 데이터 API 가 PERMISSION_DENIED 로 떨어진다.
    # 기동 자체는 되므로(클라이언트 생성은 네트워크를 타지 않는다) 헬스체크가 Firestore
    # 왕복을 포함하는 것이 이 실패를 잡아 주는 유일한 장치다.
    "roles/datastore.user",
  ]

  # ── 🔴 서명 URL 발급에 필요한 권한 ────────────────────────────────────────
  #
  # 앱은 녹음 파일을 **서버를 거치지 않고** GCS 로 직접 올린다(§call-audio.tf). 그러려면
  # WAS 가 V4 서명 URL(또는 resumable 세션 URL)을 만들어 줘야 하는데, 서명에는 개인키가
  # 필요하다. **Cloud Run 의 ADC 에는 개인키가 없다** — 메타데이터 서버가 주는 것은
  # 액세스 토큰뿐이다. 그래서 라이브러리가 IAM Credentials 의 `signBlob` API 로 서명을
  # 대신 받아 오고, GCP 는 그 호출을 "이 서비스 계정을 가장하는 행위" 로 취급한다.
  #
  # 가장의 대상이 **자기 자신**이어도 예외가 아니다. 그래서 이 SA 에 대해
  # roles/iam.serviceAccountTokenCreator 가 필요하다(표준 GCP 동작).
  #
  # 없으면 실패 모양이 헷갈린다 — 업로드가 아니라 **URL 을 만드는 단계**에서
  # "Permission 'iam.serviceAccounts.signBlob' denied" 가 나고, 버킷 IAM 은 멀쩡하므로
  # 스토리지 권한을 의심하며 시간을 버린다. 로컬 개발에서는 사용자 ADC 가 다른 경로를
  # 타서 재현되지 않고, 운영에서만 깨진다.
  #
  # 🔴 프로젝트 레벨로 주지 마라. 프로젝트 레벨 serviceAccountTokenCreator 는 **프로젝트의
  # 모든 SA** 를 가장할 수 있게 한다 — 우산 프로젝트에서는 배포자 SA(jayeon-deployer)와
  # 다른 앱의 런타임 SA 까지 포함된다. 모듈의 이 플래그는 이 계정 스코프로만 붙인다
  # (§modules/service-account/main.tf 의 self_token_creator).
  #
  # ⚠️ iamcredentials.googleapis.com 이 켜져 있어야 한다. shared/ 의 project-services 가
  # 소유한다 — 그래서 shared 를 먼저 apply 해야 한다.
  self_token_creator = true

  # 시크릿 접근은 프로젝트 레벨이 아니라 시크릿 단위로 붙는다(§secrets.tf 의 accessor_members).
  # 통화 녹음 버킷 권한도 프로젝트 레벨이 아니라 버킷 단위로 붙는다(§call-audio.tf).
}

# ── 배포자 ──────────────────────────────────────────────────────────────────

# Cloud Build 트리거가 이 계정으로 빌드한다.
#
# 기본 Cloud Build SA 를 쓰지 않는 이유 — 그쪽은 프로젝트 편집자에 가까운 광범위한 권한을
# 갖는다. 커스텀 SA 로 돌리면 빌드가 할 수 있는 일이 아래 역할로 한정된다.
module "deployer_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "jayeon-deployer"
  display_name = "Nature Cloud Build 배포자"
  description  = "Cloud Build 트리거가 이 계정으로 돈다. 이미지 빌드·푸시·Cloud Run 배포"

  project_roles = [
    # Cloud Run 서비스 갱신(새 리비전 배포). run.developer 로는 기존 서비스의 일부 설정을
    # 못 바꿔 `gcloud run deploy` 가 중간에 실패하는 경우가 있어 admin 을 준다.
    "roles/run.admin",
    # 🔴 커스텀 SA 로 도는 빌드는 이게 없으면 **로그를 못 써서 빌드 자체가 실패한다.**
    # 기본 Cloud Build SA 에는 붙어 있어 커스텀 SA 로 옮길 때 빠뜨리기 쉽고, 에러가
    # "빌드 로그를 쓸 수 없다" 로만 나와 원인이 배포 코드처럼 보인다.
    "roles/logging.logWriter",
  ]

  # ⚠ roles/artifactregistry.writer 를 여기 넣지 않는다. 저장소가 shared 소유라
  # 프로젝트 레벨이 아니라 저장소 단위로 붙인다 — 아래 블록 참고.
}

# ── shared 소유 리소스에 앱의 권한을 덧붙이는 자리 ───────────────────────────

# 🔴 Artifact Registry 저장소는 **shared/ 가 소유**하지만, 그 저장소에 이미지를 밀어 넣을
# 권한은 앱이 자기 것을 덧붙인다.
#
# 안전한 이유는 리소스 종류에 있다. `_iam_member` 는 바인딩 하나만 더하고 지울 뿐이라,
# 다른 state 가 같은 저장소에 붙여 둔 바인딩을 건드리지 않는다. 여기에 `_iam_policy` 나
# `_iam_binding` 을 쓰면 그 순간 이 state 가 저장소 IAM 전체의 주인이라고 믿게 되고,
# 다음 apply 가 shared 와 다른 앱이 붙인 권한을 **조용히 지운다.**
#
# 프로젝트 레벨 roles/artifactregistry.writer 를 쓰지 않는 이유도 같다 — 그러면 이 배포자가
# 프로젝트의 모든 저장소(앞으로 다른 앱이 만들 것까지)에 쓸 수 있게 된다.
resource "google_artifact_registry_repository_iam_member" "deployer_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repository_id

  role   = "roles/artifactregistry.writer"
  member = module.deployer_service_account.member
}

# ── "as service account" 배포 권한 ──────────────────────────────────────────
#
# 🔴 배포자가 런타임 SA 를 지정해 Cloud Run 서비스를 배포하려면 **그 SA 에 대한 actAs**
# (roles/iam.serviceAccountUser)가 필요하다. 없으면 `gcloud run deploy` 가
# "Permission 'iam.serviceAccounts.actAs' denied" 로 실패한다 — 빌드는 이미지까지 다 만든
# 뒤 마지막 단계에서 죽으므로 원인이 배포 명령처럼 보인다.
#
# 🔴 **프로젝트 레벨로 주지 마라.** 프로젝트 레벨 serviceAccountUser 는 프로젝트의 **모든**
# SA 를 가장할 수 있게 한다 — 우산 프로젝트에서는 다른 앱의 런타임 SA 까지 포함된다.
# 그래서 대상 SA 단위로 하나씩 붙인다.
#
# 🔴 그리고 사람 쪽도 같은 권한이 필요하다. **트리거를 만드는 주체**(이 루트에 apply 를 돌리는
# 사람 또는 CI)가 배포 SA(jayeon-deployer)에 대해 iam.serviceAccountUser 를 갖고 있어야
# 트리거 생성이 성공한다. Cloud Build 트리거에 service_account 를 지정하는 것 자체가
# 그 계정을 가장하는 행위로 취급되기 때문이다. 프로젝트 소유자는 이미 갖고 있으므로 보통
# 문제가 되지 않지만, 권한을 좁힌 계정으로 apply 하면 여기서 막힌다.
resource "google_service_account_iam_member" "deployer_acts_as_app" {
  service_account_id = module.app_service_account.name
  role               = "roles/iam.serviceAccountUser"
  member             = module.deployer_service_account.member
}

resource "google_service_account_iam_member" "deployer_acts_as_was" {
  service_account_id = module.was_service_account.name
  role               = "roles/iam.serviceAccountUser"
  member             = module.deployer_service_account.member
}
