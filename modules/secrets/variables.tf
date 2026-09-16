variable "project_id" {
  description = "시크릿을 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "secrets" {
  description = <<-EOT
    시크릿 이름 → 초기 버전 생성 방식. 키가 그대로 secret_id 가 된다.
    manual = true 인 항목은 Terraform 이 placeholder 만 넣고 이후 값 변경을 추적하지 않는다.
  EOT
  type = map(object({
    # 값을 직접 지정한다. null 이면 random_password 로 생성한다.
    initial_value = optional(string)
    # 자동 생성 시 길이.
    random_length = optional(number, 32)
    # 실제 값을 state 에 남기면 안 되는, 외부 콘솔에서 발급받는 키에 쓴다.
    manual = optional(bool, false)

    # manual 시크릿의 부트스트랩용 placeholder("REPLACE_ME") 버전을 만들지 여부.
    #
    # Cloud Run 은 배포 시점에 버전이 최소 1개 있어야 해서 최초에는 true 가 필요하다.
    # **실제 값을 올린 뒤에는 반드시 false 로 바꾼다.**
    # true 로 두면 Terraform 이 이 버전을 계속 소유하는데, 어떤 이유로든 재생성되는 순간
    # REPLACE_ME 가 latest 가 되어 그 시크릿을 쓰는 기능이 조용히 죽는다.
    #
    # false 로 바꿀 때는 state 에서도 빼야 한다:
    #   terraform state rm 'module.secrets.google_secret_manager_secret_version.manual["KEY"]'
    placeholder = optional(bool, true)
  }))

  validation {
    condition = alltrue([
      for k, v in var.secrets : !(v.manual && v.initial_value != null)
    ])
    error_message = "manual = true 인 시크릿에는 initial_value 를 지정할 수 없다. 실제 값은 Terraform 밖에서 올린다."
  }

  validation {
    condition = alltrue([
      for k, v in var.secrets : v.random_length >= 16
    ])
    error_message = "random_length 는 16 이상이어야 한다."
  }
}

variable "accessor_members" {
  description = <<-EOT
    모든 시크릿에 roles/secretmanager.secretAccessor 를 부여할 멤버 목록
    (예: serviceAccount:app@project.iam.gserviceaccount.com).
    프로젝트 레벨이 아니라 시크릿 단위로 붙는다.

    ⚠ 이 목록은 모듈 안의 **모든** 시크릿에 한꺼번에 걸린다. 읽을 주체가 서로 다른 시크릿을
    한 모듈에 섞으면, 어느 한쪽이 읽을 이유가 전혀 없는 값까지 그 권한으로 열린다.
    주체가 다르면 모듈 호출을 나눠라.
  EOT
  type        = list(string)
  default     = []
}
