variable "project_id" {
  description = "Firebase Hosting 사이트를 생성할 GCP 프로젝트 ID"
  type        = string
}

# site_id 는 프로젝트 안이 아니라 Firebase 전역에서 유일해야 한다.
# 이미 누군가 선점한 값이면 apply 가 실패하므로 프로젝트 이름을 접두어로 두는 편이 안전하다.
variable "site_id" {
  description = "Firebase Hosting 사이트 ID. Firebase 전역에서 유일해야 한다"
  type        = string
}

variable "custom_domains" {
  description = "이 사이트에 연결할 커스텀 도메인 목록"
  type        = list(string)
  default     = []
}

# run_service · message 는 없앴다. 버전과 릴리스를 Terraform 이 만들지 않으므로 받을 이유가
# 없다 — 어떤 Cloud Run 으로 넘길지는 `hosting/{site}.json` 이 말한다(main.tf 의 경계 주석 참고).
