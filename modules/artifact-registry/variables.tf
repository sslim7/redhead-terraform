variable "project_id" {
  description = "저장소를 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "location" {
  description = "Artifact Registry 리전. Cloud Run 과 같은 리전에 둬야 이미지 pull 이 리전 내부에서 끝난다"
  type        = string
}

variable "repository_id" {
  description = "저장소 ID. 이미지 경로의 마지막 세그먼트가 된다"
  type        = string
  default     = "redhead"
}

variable "description" {
  description = "저장소 설명"
  type        = string
  default     = "redhead 서비스 컨테이너 이미지 저장소"
}

variable "cleanup" {
  description = <<-EOT
    이미지 정리 정책. Artifact Registry 무료 한도는 0.5GB 라서
    빌드마다 쌓이는 이미지를 방치하면 금방 과금 구간에 들어간다.
  EOT
  type = object({
    # 최근 N개 버전은 정리 대상에서 제외한다.
    keep_tagged_count = optional(number, 5)
    # 태그 없는 이미지(재빌드로 태그를 뺏긴 레이어)를 지우기까지의 기간.
    # API 는 Duration 을 초 단위 문자열("604800s")로 정규화하므로,
    # "7d" 같은 표기를 쓰면 프로바이더 버전에 따라 매 plan 마다 diff 가 남을 수 있다.
    untagged_max_age = optional(string, "7d")
    # true 로 두면 실제 삭제 없이 Cloud Logging 에 대상만 기록한다. 정책 검증용.
    dry_run = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.cleanup.keep_tagged_count >= 1
    error_message = "keep_tagged_count 는 1 이상이어야 한다."
  }
}

variable "writer_members" {
  description = "roles/artifactregistry.writer 를 부여할 멤버 목록 (이미지를 push 하는 Cloud Build SA 등)"
  type        = list(string)
  default     = []
}

variable "reader_members" {
  description = "roles/artifactregistry.reader 를 부여할 멤버 목록 (이미지를 pull 하는 Cloud Run SA 등)"
  type        = list(string)
  default     = []
}
