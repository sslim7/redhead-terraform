terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Firebase Hosting 리소스는 GA 프로바이더에 없다. 이 모듈의 모든 리소스가 google-beta 를 쓴다.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}
