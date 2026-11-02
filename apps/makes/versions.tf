terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Firebase(Hosting 사이트·커스텀 도메인) 리소스는 google-beta 에만 있다.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }

  # shared가 만든 버킷을 사용하되 앱 전용 prefix로 state를 분리한다.
  # 🔴 apply 이후에는 prefix 를 바꾸지 마라. 빈 state 에서 기존 자원을 다시 만들려 한다.
  backend "gcs" {
    bucket = "redhead-kr-tfstate"
    prefix = "apps/makes"
  }
}
