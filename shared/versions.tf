terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Firebase 리소스(프로젝트 승격, Hosting, 보안 규칙)는 google-beta 에만 있다.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
    # 이 루트는 random 리소스를 직접 쓰지 않는다. 그래도 선언해 두는 것은 apps/<앱>/ 이
    # JWT 서명키를 random_password 로 만들고, 그 state 가 이 루트가 만든 버킷에 들어가기
    # 때문이다 — 두 루트의 프로바이더 버전 제약을 같게 두어 "한쪽에서만 되는" 상황을 막는다.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 2026-09-16: 로컬 state로 공통 인프라 생성 및 GCP NS 4개의 메일 DNS 비교 완료.
  # 기존 로컬 state는 terraform init -migrate-state로 이 버킷에 이전한다.
  # 이전 완료 전 terraform.tfstate를 삭제하거나 init -reconfigure를 사용하지 않는다.
  backend "gcs" {
    bucket = "redhead-kr-tfstate"
    prefix = "shared"
  }
}
