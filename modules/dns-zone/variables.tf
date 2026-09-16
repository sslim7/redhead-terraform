variable "project_id" {
  description = "관리 영역을 생성할 GCP 프로젝트 ID"
  type        = string
}

# 이 값은 dns-records 의 zone_name 입력으로 그대로 넘어간다. 생성 후 변경할 수 없고,
# 바꾸면 영역이 재생성되면서 다른 state 가 그 영역에 넣어 둔 레코드까지 전부 사라진다.
variable "zone_name" {
  description = "Cloud DNS 관리 영역의 리소스 이름. 도메인이 아니라 GCP 안에서의 식별자이며 생성 후 변경할 수 없다"
  type        = string
  default     = "redhead"
}

variable "dns_name" {
  description = "관리할 도메인. 끝 점을 포함한 FQDN 이어야 한다 (예: redhead.kr.)"
  type        = string

  validation {
    condition     = endswith(var.dns_name, ".")
    error_message = "dns_name 은 끝 점을 포함해야 한다 (예: redhead.kr.). 점이 없으면 Cloud DNS API 가 거부한다."
  }
}

variable "description" {
  description = "관리 영역 설명. 콘솔에서 이 영역의 용도를 구분하는 용도다"
  type        = string
  default     = "Terraform 이 관리하는 redhead 우산 도메인 (레코드는 앱별 루트가 따로 관리한다)"
}
