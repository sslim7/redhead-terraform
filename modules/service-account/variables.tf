variable "project_id" {
  description = "서비스 계정을 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "account_id" {
  description = "서비스 계정 ID. 이메일의 @ 앞부분이 된다 (6~30자, 소문자/숫자/하이픈)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "account_id 는 소문자로 시작하는 6~30자의 소문자/숫자/하이픈이어야 한다."
  }
}

variable "display_name" {
  description = "콘솔에 표시되는 서비스 계정 이름"
  type        = string
}

variable "description" {
  description = "서비스 계정 용도 설명"
  type        = string
  default     = ""
}

variable "project_roles" {
  description = "이 서비스 계정에 프로젝트 레벨로 부여할 역할 목록 (예: roles/datastore.user)"
  type        = list(string)
  default     = []
}

variable "self_token_creator" {
  description = <<-EOT
    자기 자신에 대해 roles/iam.serviceAccountTokenCreator 를 부여할지 여부.
    GCS V4 서명 URL 과 Firebase 커스텀 토큰 발급에 필요하다.
    프로젝트 레벨로 주면 프로젝트의 모든 서비스 계정을 가장할 수 있게 되므로
    반드시 이 계정 스코프로만 부여한다.
  EOT
  type        = bool
  default     = false
}
