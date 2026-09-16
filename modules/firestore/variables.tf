variable "project_id" {
  description = "Firestore 데이터베이스를 생성할 GCP 프로젝트 ID"
  type        = string
}

variable "location_id" {
  description = "Firestore 데이터베이스 위치 (리전 또는 멀티리전). 생성 후 변경 불가"
  type        = string
}

variable "database" {
  description = "Firestore 데이터베이스 보호 설정"
  type = object({
    # 콘솔/API 를 통한 실수 삭제 방지. 운영 환경은 활성화 권장
    delete_protection_state = optional(string, "DELETE_PROTECTION_ENABLED")
    # Terraform destroy 시 동작. "DELETE" 는 실제 삭제, "ABANDON" 은 state 에서만 제거
    deletion_policy = optional(string, "ABANDON")
  })
  default = {}

  validation {
    condition = contains(
      ["DELETE_PROTECTION_ENABLED", "DELETE_PROTECTION_DISABLED"],
      var.database.delete_protection_state
    )
    error_message = "delete_protection_state 는 DELETE_PROTECTION_ENABLED 또는 DELETE_PROTECTION_DISABLED 여야 한다."
  }

  validation {
    condition     = contains(["DELETE", "ABANDON"], var.database.deletion_policy)
    error_message = "deletion_policy 는 DELETE 또는 ABANDON 이어야 한다."
  }
}

variable "indexes" {
  description = "생성할 복합 인덱스 목록. 필드 순서가 인덱스의 의미를 정하므로 코드의 쿼리 순서와 일치해야 한다"
  type = list(object({
    collection  = string
    query_scope = optional(string, "COLLECTION")
    fields = list(object({
      field_path   = string
      order        = optional(string)
      array_config = optional(string)
    }))
  }))

  # 🔴 기본값은 빈 리스트다. **인덱스 목록은 모듈이 아니라 앱이 소유한다** — 어떤 쿼리를 거는지는
  # 그 앱의 코드만 알고, 모듈에 기본값을 박아 두면 그 목록이 어느 앱 것인지 알 수 없게 된다.
  #
  # 대신 빈 기본값의 대가를 알고 있어야 한다. **인덱스가 없으면 그 쿼리를 쓰는 화면만
  # 500(FAILED_PRECONDITION)이 되고, 배포 후에야 발견된다.** 기동·헬스체크·나머지 API 는
  # 전부 정상이라 알람이 울리지 않는다. jayeon-was 가 복합 쿼리를 거는 순간
  # apps/jayeon/firestore.tf 의 `indexes` 에 같은 순서로 필드를 적어야 한다.
  default = []

  validation {
    condition     = alltrue([for idx in var.indexes : contains(["COLLECTION", "COLLECTION_GROUP"], idx.query_scope)])
    error_message = "query_scope 는 COLLECTION 또는 COLLECTION_GROUP 이어야 한다."
  }

  validation {
    condition     = alltrue([for idx in var.indexes : length(idx.fields) >= 2])
    error_message = "복합 인덱스는 필드가 2개 이상이어야 한다. 단일 필드 인덱스는 single_field_indexes 를 쓴다."
  }

  validation {
    condition = alltrue([
      for idx in var.indexes : alltrue([
        for f in idx.fields : (f.order == null) != (f.array_config == null)
      ])
    ])
    error_message = "인덱스 필드마다 order 와 array_config 중 정확히 하나만 지정해야 한다."
  }
}

variable "single_field_indexes" {
  description = "단일 필드 collection group 인덱스 목록. 자동 생성되는 단일 필드 인덱스는 COLLECTION 스코프뿐이라 명시 생성이 필요하다"
  type = list(object({
    collection = string
    field      = string
    # index_config 가 기존 구성을 통째로 대체하므로, 자동 생성되던 COLLECTION 스코프
    # 인덱스도 여기에 다시 적는다. 비우면 그 필드의 기본 인덱스가 사라진다
    orders = optional(list(string), ["ASCENDING", "DESCENDING"])
  }))

  # 위 indexes 와 같은 이유로 비워 둔다. 여기에 넣을 것은 **collectionGroup() 쿼리가 거는
  # 단일 필드**뿐이다 — 한 컬렉션 안에서 쓰는 단일 필드 인덱스는 Firestore 가 자동으로 만든다.
  #
  # ⚠ orders 를 함부로 줄이지 마라. index_config 는 그 필드의 인덱스 구성을 **통째로 대체**하므로,
  # ASCENDING 하나만 남기면 원래 자동으로 있던 DESCENDING 인덱스가 사라지고 그 필드로
  # 내림차순 정렬하던 화면이 조용히 깨진다.
  default = []

  validation {
    condition = alltrue([
      for f in var.single_field_indexes :
      alltrue([for o in f.orders : contains(["ASCENDING", "DESCENDING"], o)])
    ])
    error_message = "orders 의 값은 ASCENDING 또는 DESCENDING 이어야 한다."
  }
}

variable "rules_file" {
  description = "Firestore 보안 규칙 파일 경로. null 이면 규칙을 Terraform 이 관리하지 않는다"
  type        = string
  default     = null
}
