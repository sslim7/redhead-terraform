variable "gcp" {
  description = <<-EOT
    GCP 프로젝트·리전 설정. 이 값은 프로바이더 설정(providers.tf)에도 그대로 들어가므로
    리소스 참조가 아닌 **리터럴**이어야 한다. 그래서 여기 default 를 둔다.
  EOT
  type = object({
    # 🔴 GCP 전역 유일값이다. 바꾸는 여파는 project.tf 주석 참고.
    project_id = optional(string, "redhead-kr")
    # 콘솔 프로젝트 선택기에 보이는 표시 이름. ID 와 달리 나중에 바꿀 수 있다.
    project_name = optional(string, "redhead")
    # Cloud Run · Artifact Registry · Cloud Build 를 한 리전에 모은다. 이미지 pull 이 리전
    # 내부에서 끝나고, 리전을 섞으면 이미지 전송에 네트워크 비용이 붙는다.
    region = optional(string, "asia-northeast3")
  })
  default = {}
}

# 기본값을 두지 않는다. 결제 계정 ID 는 비밀은 아니지만 이 레포와 수명이 다른 값이고
# (계정을 옮기면 바뀐다), 커밋된 tfvars 에 박아 두면 "왜 우리 계정에 과금되지" 를
# 추적할 지점이 코드 이력에 흩어진다. 실제 값은 local.auto.tfvars 에 둔다.
#
# 값이 비면 apply 시점에 물어보고, 잘못된 값을 넣으면 프로젝트는 만들어지지만 결제가 붙지
# 않아 API 활성화부터 실패한다. 형식은 "XXXXXX-XXXXXX-XXXXXX" 다.
variable "billing_account" {
  description = "프로젝트에 연결할 Cloud Billing 계정 ID (local.auto.tfvars 에서 온다)"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "billing_account 는 XXXXXX-XXXXXX-XXXXXX 형식이어야 한다 (gcloud billing accounts list 의 ACCOUNT_ID)."
  }
}

variable "domains" {
  description = <<-EOT
    우산 도메인. 서브도메인(jayeon.redhead.kr 등)은 여기 두지 않는다 — 앱 루트 소관이고,
    shared/ 가 알아야 하는 것은 존을 만들 apex 뿐이다.
  EOT
  type = object({
    apex = optional(string, "redhead.kr")
  })
  default = {}
}

variable "dns" {
  description = "Cloud DNS 관리 영역 설정"
  type = object({
    # 도메인이 아니라 GCP 안에서의 식별자다. **생성 후 변경할 수 없고**, 바꾸면 영역이
    # 재생성되면서 앱 루트가 그 영역에 넣어 둔 레코드까지 전부 사라진다(다른 state 라
    # Terraform 이 알려주지 못한다).
    zone_name = optional(string, "redhead")
    # 이관 중에는 낮게 둔다. 값을 되돌려야 할 때 잘못된 응답이 캐시에 남는 시간이 곧 장애
    # 시간이다. 안정된 뒤 올리면 쿼리 비용이 줄지만(100만건당 $0.40), 이 도메인의 쿼리량에서는
    # 차이가 의미 없어 계속 600 으로 둔다.
    ttl = optional(number, 600)
  })
  default = {}
}

variable "artifact_registry" {
  description = <<-EOT
    앱들이 **공유하는** 컨테이너 이미지 저장소. 앱마다 저장소를 파지 않는 이유는
    무료 한도(0.5GB)가 프로젝트 전체 합산이라 쪼개도 아무 이득이 없고, 정리 정책만
    여러 벌로 늘어나기 때문이다.
  EOT
  type = object({
    repository_id     = optional(string, "redhead")
    keep_tagged_count = optional(number, 5)
    # Duration 값이다. API 가 초 단위 문자열("604800s")로 정규화하므로 "7d" 로 넣으면
    # 프로바이더 버전에 따라 매 plan 마다 diff 가 남을 수 있다 — variables.auto.tfvars 는
    # 그래서 초로 적어 둔다.
    untagged_max_age = optional(string, "7d")
  })
  default = {}
}

variable "mail" {
  description = <<-EOT
    redhead.kr 메일(purelymail.com) 관련 DNS 레코드 값.

    **이 값들이 어디서 왔는가.** 원본은 가비아 DNS 관리 화면에 들어 있는 이관 전 레코드이고,
    그것이 실제로 공개 DNS 에 떠 있는지 dig 로 한 번 더 확인한 실측값이다.

        dig TXT   redhead.kr
        dig MX    redhead.kr
        dig CNAME purelymail1._domainkey.redhead.kr
        dig CNAME _dmarc.redhead.kr

    즉 purelymail 문서의 "이렇게 넣어라" 가 아니라 **지금 떠 있는 값**이다. 문서와 실측이
    다르면 실측을 따른다 — 이번 작업의 목표는 현재 동작을 그대로 옮기는 것이고, 문서에 맞춰
    값을 "고치면" 이관 실패와 설정 변경이 같은 apply 에 섞여 무엇이 메일을 끊었는지 가릴 수 없다.

    값을 바꿀 일이 생기면 purelymail 콘솔이 먼저다. DNS 를 먼저 바꾸면 그 사이 메일이 끊긴다.
  EOT
  type = object({
    # purelymail 의 도메인 소유권 증명. 이 값이 사라지면 purelymail 이 도메인 소유를
    # 재확인하지 못해 해당 도메인의 메일 처리를 멈춘다.
    ownership_proof = string
    # 이 도메인을 발신 주소로 쓸 수 있는 서버 목록. 없으면 보낸 메일이 스팸으로 분류되거나
    # 아예 거부된다(수신은 계속 된다 — 그래서 알아채기 어렵다).
    spf = string
    # 한 라벨의 MX 는 전부 이 리스트에 모은다. 나눠 선언하면 마지막 것만 남는다.
    mx = list(object({
      priority = number
      target   = string
    }))
    # DKIM 공개키. purelymail 이 키를 교체할 수 있으므로 값이 아니라 CNAME 으로 위임한다.
    # 키는 3개다 — 하나만 넣으면 그 키로 서명되지 않은 메일이 DKIM fail 이 된다.
    dkim_cnames = map(string)
    # DMARC 정책. SPF/DKIM 검증 실패 시 수신자가 어떻게 할지를 알린다.
    dmarc_cname = string
  })

  # apex TXT 는 두 값이 한 rrset 에 들어가야 한다(dns.tf 참고). 둘 중 하나가 빈 문자열이면
  # 빈 TXT rrdata 가 만들어져 SPF 파서가 레코드 전체를 무효로 볼 수 있다.
  validation {
    condition     = length(var.mail.ownership_proof) > 0 && length(var.mail.spf) > 0
    error_message = "ownership_proof 와 spf 는 비워 둘 수 없다. 둘은 apex TXT 한 rrset 에 함께 들어간다."
  }

  validation {
    condition     = length(var.mail.mx) > 0
    error_message = "MX 가 없으면 이 도메인으로 오는 메일이 전부 수신 실패한다."
  }
}
