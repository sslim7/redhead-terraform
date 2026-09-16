terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # Firebase 관련 리소스(firebaserules)는 google 프로바이더에 없고 google-beta 에만 있다.
    # 보안 규칙을 Terraform 으로 배포하려면 호출부가 google-beta 를 넘겨야 하고, 그 프로바이더는
    # quota project 가 설정된 것이어야 한다(호출부 providers.tf 의 google-beta.firebase 참고).
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}
