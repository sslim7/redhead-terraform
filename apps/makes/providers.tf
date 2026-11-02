provider "google" {
  project = var.project_id
  region  = var.region

  # app 라벨은 우산 프로젝트에서 "이게 누구 것인가" 를 가르는 단서다(apps/nature/providers.tf).
  default_labels = {
    managed-by = "terraform"
    app        = "makes"
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed-by = "terraform"
    app        = "makes"
  }
}

# Firebase 리소스(Hosting 사이트·커스텀 도메인) 전용 별칭.
#
# 🔴 **이 별칭이 없으면 Hosting apply 가 403 SERVICE_DISABLED 로 막힌다.** API 가 켜져
# 있어도 그렇다 — firebasehosting 은 quota project 를 요구하고, 사용자 ADC 로 부르면 그 값이
# 구글 소유 프로젝트로 잡힌다. user_project_override + billing_project 가 그 헤더를 고친다.
#
# 왜 기본 google-beta 가 아니라 별칭인지까지 포함한 전체 설명은 apps/nature/providers.tf 에 있다.
provider "google-beta" {
  alias = "firebase"

  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    managed-by = "terraform"
    app        = "makes"
  }
}
