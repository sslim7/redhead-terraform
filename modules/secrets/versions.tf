terraform {
  required_version = ">= 1.14.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    # 값을 넘기지 않은 시크릿을 자동 생성하는 데 쓴다.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
