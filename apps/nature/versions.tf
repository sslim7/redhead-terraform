terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Firebase(Hosting 사이트·커스텀 도메인, Firestore 보안 규칙) 리소스는 google-beta 에만 있다.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
    # JWT 서명키 자동 생성(modules/secrets)에 쓴다.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # shared가 만든 버킷을 사용하되 앱 전용 prefix로 state를 분리한다.
  backend "gcs" {
    bucket = "redhead-kr-tfstate"
    prefix = "apps/jayeon" # 기존 운영 state 식별자: 로컬 폴더명과 함께 바꾸면 안 된다.
  }
}
