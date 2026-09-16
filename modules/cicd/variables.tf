variable "project_id" {
  description = "Cloud Build 트리거를 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "location" {
  description = "Cloud Build 트리거 리전"
  type        = string
}

# 트리거가 사용할 SA 는 이 모듈이 만들지 않는다.
# 하나의 SA 를 여러 트리거가 공유하고, 권한 구성은 호출부가 modules/service-account 로 관리한다.
variable "deployer_sa_email" {
  description = "빌드를 실행할 서비스 계정 이메일"
  type        = string
}

variable "triggers" {
  description = "생성할 Cloud Build 트리거 맵. 맵의 키가 트리거 이름이 된다"
  type = map(object({
    github_owner = string
    github_repo  = string

    # branch_regex 와 tag_regex 는 둘 중 정확히 하나만 지정한다.
    # 둘 다 정규식으로 해석되므로 "^v" 처럼 앵커를 붙이지 않으면 의도보다 넓게 잡힌다.
    #
    # Git 에서 태그는 브랜치에 속하지 않는다. "release 브랜치에 붙인 v 태그" 같은 조건은
    # Cloud Build 가 표현할 수 없고, tag_regex 로 "v 로 시작하는 태그 push" 까지만 걸 수 있다.
    # 어느 브랜치의 커밋에 태그를 붙였는지는 태그를 미는 사람이 지킬 규칙이다.
    branch_regex = optional(string)
    tag_regex    = optional(string)

    # 이 트리거만 다른 서비스 계정으로 돌리고 싶을 때 지정한다. null 이면 deployer_sa_email.
    # 트리거를 만드는 주체(사람 또는 CI)가 그 SA 에 대해 iam.serviceAccountUser 를 가져야 한다.
    service_account_email = optional(string)

    filename       = optional(string, "cloudbuild.yaml")
    substitutions  = optional(map(string), {})
    included_files = optional(list(string))
    disabled       = optional(bool, false)
  }))

  # 트리거 이름 규칙을 어기면 API 가 거부한다. 원인 메시지가 모호해서 미리 걸러낸다.
  validation {
    condition = alltrue([
      for k in keys(var.triggers) : can(regex("^[a-zA-Z][a-zA-Z0-9-_]{0,63}$", k))
    ])
    error_message = "트리거 이름(맵 키)은 영문자로 시작하고 영숫자·하이픈·언더스코어만 쓸 수 있다."
  }

  validation {
    condition = alltrue([
      for t in values(var.triggers) : (t.branch_regex == null) != (t.tag_regex == null)
    ])
    error_message = "트리거마다 branch_regex 와 tag_regex 중 정확히 하나만 지정해야 한다."
  }
}
