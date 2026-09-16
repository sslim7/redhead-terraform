variable "project_id" {
  description = "Cloud Run 서비스를 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "location" {
  description = "Cloud Run 서비스 리전"
  type        = string
}

variable "name" {
  description = "Cloud Run 서비스 이름"
  type        = string
}

# 최초 apply 시점에는 애플리케이션 이미지가 아직 Artifact Registry 에 없다.
# 그래서 부트스트랩 이미지로 서비스 껍데기를 만들고, 이후 실제 이미지는 Cloud Build 가 굴린다.
# main.tf 의 lifecycle.ignore_changes 가 이 값의 재적용을 막는다.
variable "image" {
  description = "최초 생성 시 사용할 부트스트랩 컨테이너 이미지. 이후 이미지 갱신은 Cloud Build 가 담당하며 Terraform 은 변경을 무시한다"
  type        = string
}

variable "service_account_email" {
  description = "리비전이 사용할 런타임 서비스 계정 이메일"
  type        = string
}

variable "resources" {
  description = "컨테이너 CPU/메모리 및 CPU 할당 방식"
  type = object({
    cpu    = optional(string, "1")
    memory = optional(string, "512Mi")
    # false 면 요청 처리 중이 아니어도 인스턴스 수명 동안 CPU 가 할당된다.
    # 백그라운드 작업이나 요청 외 초기화가 끊기지 않아야 하는 서비스에 필요하다.
    cpu_idle = optional(bool, true)
    # 콜드 스타트 구간에만 CPU 를 추가로 준다. 기동 지연을 줄이는 용도다.
    startup_cpu_boost = optional(bool, true)
  })
  default = {}
}

variable "scaling" {
  description = "인스턴스 스케일링 범위와 인스턴스당 동시 요청 수"
  type = object({
    # 0 이면 유휴 시 인스턴스가 모두 내려간다. 유휴 과금을 없애는 대신 콜드 스타트를 감수한다.
    min_instance_count = optional(number, 0)
    max_instance_count = optional(number, 3)
    concurrency        = optional(number, 80)
  })
  default = {}

  validation {
    condition     = var.scaling.min_instance_count <= var.scaling.max_instance_count
    error_message = "min_instance_count 는 max_instance_count 이하여야 한다."
  }

  validation {
    condition     = var.scaling.concurrency >= 1
    error_message = "concurrency 는 1 이상이어야 한다."
  }
}

variable "container_port" {
  description = "컨테이너가 리스닝하는 포트. Cloud Run 이 이 값을 PORT 환경변수로 컨테이너에 주입한다"
  type        = number
  default     = 8080
}

variable "env" {
  description = "평문 환경변수 맵. PORT 는 Cloud Run 이 직접 주입하므로 넣을 수 없다"
  type        = map(string)
  default     = {}

  # Cloud Run 은 PORT 를 런타임에 스스로 주입하며, 사용자가 같은 이름을 지정하면 배포가 거부된다.
  # 배포 실패 메시지가 불친절해서 원인을 찾기 어려우므로 plan 단계에서 막는다.
  validation {
    condition     = !contains(keys(var.env), "PORT")
    error_message = "PORT 는 Cloud Run 이 예약한 환경변수다. container_port 를 대신 사용해야 한다."
  }
}

variable "secret_env" {
  description = "Secret Manager 시크릿을 참조하는 환경변수 맵. 키는 환경변수 이름이다"
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}

  # 시크릿 경로로 우회해도 PORT 예약 규칙은 동일하게 적용된다.
  validation {
    condition     = !contains(keys(var.secret_env), "PORT")
    error_message = "PORT 는 Cloud Run 이 예약한 환경변수다. secret_env 로도 지정할 수 없다."
  }
}

variable "startup_probe" {
  description = "기동 확인용 HTTP 프로브 설정. null 이면 프로브를 만들지 않는다"
  type = object({
    path                  = string
    initial_delay_seconds = optional(number, 0)
    period_seconds        = optional(number, 10)
    timeout_seconds       = optional(number, 5)
    # 헬스 엔드포인트가 Firestore 왕복까지 확인하는 구조라 첫 응답이 늦을 수 있다.
    # 임계값을 낮게 잡으면 정상 기동 중인 리비전이 실패로 처리된다.
    failure_threshold = optional(number, 10)
  })
  default  = null
  nullable = true
}

variable "allow_unauthenticated" {
  description = "true 면 allUsers 에 roles/run.invoker 를 부여해 공개 호출을 허용한다"
  type        = bool
  default     = true
}

variable "timeout" {
  description = "요청 처리 최대 시간 (예: \"60s\")"
  type        = string
  default     = "60s"
}

variable "labels" {
  description = "서비스에 붙일 라벨"
  type        = map(string)
  default     = {}
}
