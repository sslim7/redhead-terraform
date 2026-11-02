# makes — 영상·발표·문서 HTML 을 올리는 정적 사이트. 콘텐츠는 ~/Projects/makes 저장소가 올린다.
#
# 🔴 shared 의 remote state 를 읽지 않는다. 이유는 apps/nature/variables.tf 상단에 있다.

variable "project_id" {
  description = "GCP 프로젝트 ID. shared/ 가 만든 우산 프로젝트다"
  type        = string
  default     = "redhead-kr"
}

variable "region" {
  description = "프로바이더 기본 리전. Hosting 은 리전이 없지만 다른 앱 루트와 같은 값을 쓴다"
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

variable "domain" {
  description = <<-EOT
    이 사이트의 커스텀 도메인. redhead.kr 하위 서브도메인이다.

    apex(redhead.kr)는 여기 올 수 없다. apex 레코드는 shared/ 소유다 — dns.tf 상단을 보라.
  EOT
  type        = string
  default     = "makes.redhead.kr"
}

# 🔴 site_id 는 프로젝트가 아니라 **Firebase 전역**에서 유일해야 한다. 그래서 프로젝트
# 이름을 접두어로 둔다. 선점된 값이면 apply 가 실패한다.
#
# ⚠️ makes 저장소의 `.firebaserc` 타깃(`makes` → `redhead-makes`)이 이 값을 가리킨다.
# 바꾸면 그쪽도 함께 고쳐야 deploy 가 새 사이트로 간다.
variable "site_id" {
  description = "Firebase Hosting 사이트 ID. Firebase 전역에서 유일해야 한다"
  type        = string
  default     = "redhead-makes"
}
