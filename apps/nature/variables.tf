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
    bootstrap_image    = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")
    cpu                = optional(string, "1")
    memory             = optional(string, "512Mi")
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
