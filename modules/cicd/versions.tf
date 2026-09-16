terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # 이 모듈은 GA 리소스만 쓰지만, 호출부가 모든 모듈에 동일한 provider 집합을
    # 넘길 수 있도록 google-beta 도 함께 선언해 둔다.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}
