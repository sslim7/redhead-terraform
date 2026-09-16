variable "project_id" {
  description = "레코드를 생성할 GCP 프로젝트 ID (관리 영역이 속한 프로젝트)"
  type        = string
}

# 영역을 리소스 참조가 아니라 **문자열로만** 받는다. 영역은 다른 state(shared/)가 소유하며,
# 이 모듈은 그 state 를 읽지 않는다.
#
# terraform_remote_state 로 영역을 읽어 오는 방법도 있지만 쓰지 않았다. 그러면 앱 루트가
# shared 의 state 파일 전체를 읽을 권한을 갖게 되고(그 안에는 다른 앱의 값도 들어 있다),
# shared 의 출력 구조가 바뀌는 순간 모든 앱의 plan 이 동시에 깨진다. 영역 이름은
# 한 번 정하면 바뀌지 않는 값이므로(생성 후 변경 불가) 문자열 결합이 더 느슨하고 안전하다.
variable "zone_name" {
  description = "레코드를 넣을 Cloud DNS 관리 영역의 리소스 이름. 이 모듈은 영역을 만들지 않고 이미 있는 것을 가리킨다"
  type        = string
}

variable "dns_name" {
  description = "관리 영역의 도메인. 라벨에 이어 붙여 FQDN 을 만드는 데 쓴다. 끝 점을 포함해야 한다 (예: redhead.kr.)"
  type        = string

  validation {
    condition     = endswith(var.dns_name, ".")
    error_message = "dns_name 은 끝 점을 포함해야 한다 (예: redhead.kr.). 점이 없으면 조립한 레코드 이름이 영역 밖을 가리킨다."
  }
}

variable "default_ttl" {
  description = "모든 레코드에 적용할 TTL(초). 값을 바꾸면 기존 캐시가 만료된 뒤부터 반영된다"
  type        = number
  default     = 600
}

# 아래 맵들의 키는 FQDN 이 아니라 라벨만 받는다. apex 는 "", 서브도메인은 "app" 처럼 쓴다.
# 호출부가 도메인과 끝 점을 매번 반복하지 않게 하려는 것이고, 조립은 모듈이 한다.
variable "a_records" {
  description = "A 레코드. 호스트 라벨(apex 는 \"\") → IP 목록. 한 호스트의 IP 여러 개는 rrdatas 한 리스트로 들어간다"
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k, _ in var.a_records : !endswith("${k}.", var.dns_name)])
    error_message = "a_records 의 키는 라벨만 쓴다. 도메인 전체를 넣으면 dns_name 이 한 번 더 붙는다."
  }
}

variable "cname_records" {
  description = "CNAME 레코드. 호스트 라벨 → 대상 도메인. 대상에 끝 점이 없으면 모듈이 붙인다"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, _ in var.cname_records : !endswith("${k}.", var.dns_name)])
    error_message = "cname_records 의 키는 라벨만 쓴다. 도메인 전체를 넣으면 dns_name 이 한 번 더 붙는다."
  }

  # 영역 apex 에는 SOA/NS 가 이미 있어 CNAME 을 함께 둘 수 없다(RFC 1034 §3.6.2).
  # 넣으면 apply 시점에 API 오류가 나므로 plan 단계에서 막는다.
  validation {
    condition     = !contains(keys(var.cname_records), "")
    error_message = "apex(\"\")에는 CNAME 을 둘 수 없다. 루트 도메인은 a_records 로 지정한다."
  }
}

# 한 라벨의 TXT 값은 반드시 이 리스트 하나에 모아 넘긴다. google_dns_record_set 은
# (이름, 타입) 조합당 하나만 존재하므로, 같은 라벨에 TXT rrset 을 두 번 선언하면
# 나중에 apply 되는 쪽이 앞의 것을 지운다. apex 에는 hosting 소유권 증명 TXT 와 SPF 가
# **함께** 살아야 하는데, 이를 나눠 선언하면 한쪽이 사라져 도메인 검증이 풀리거나
# 메일이 SPF fail 로 반송된다. 둘을 같은 리스트에 넣어야 한 rrset 의 두 rrdata 가 된다.
variable "txt_records" {
  description = "TXT 레코드. 호스트 라벨 → 값 목록(한 라벨의 값은 전부 한 리스트에). 값은 따옴표 없이 넘기면 모듈이 감싸 준다"
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k, _ in var.txt_records : !endswith("${k}.", var.dns_name)])
    error_message = "txt_records 의 키는 라벨만 쓴다. 도메인 전체를 넣으면 dns_name 이 한 번 더 붙는다."
  }
}

# MX 도 TXT 와 같다. 한 라벨의 메일 서버 여러 개는 rrset 하나의 rrdatas 리스트로 들어가므로
# 전부 이 리스트에 모아 넘긴다. 우선순위별로 나눠 선언할 수단은 없다 — 나눠도 (이름, MX)
# 조합이 같아서 마지막 것만 남고 앞의 서버들이 사라진다.
#
# target 은 끝 점을 붙여 쓰는 것이 원칙이고, 빠뜨리면 모듈이 붙여 준다(main.tf 의 mx_rrdatas 참고).
variable "mx_records" {
  description = "MX 레코드. 호스트 라벨 → {priority, target} 목록. rrdata 는 모듈이 \"우선순위 호스트.\" 형태로 조립한다"
  type = map(list(object({
    priority = number
    target   = string
  })))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.mx_records : !endswith("${k}.", var.dns_name)])
    error_message = "mx_records 의 키는 라벨만 쓴다. 도메인 전체를 넣으면 dns_name 이 한 번 더 붙는다."
  }

  # MX preference 는 16비트 정수다. 범위를 벗어나거나 소수면 API 가 거부한다.
  validation {
    condition = alltrue([
      for entries in values(var.mx_records) : alltrue([
        for e in entries : floor(e.priority) == e.priority && e.priority >= 0 && e.priority <= 65535
      ])
    ])
    error_message = "MX priority 는 0~65535 범위의 정수여야 한다."
  }

  # 빈 리스트는 rrdatas 가 비어 있는 rrset 을 만들려 해서 apply 가 깨진다.
  validation {
    condition     = alltrue([for entries in values(var.mx_records) : length(entries) > 0])
    error_message = "mx_records 의 각 라벨에는 최소 1개의 메일 서버가 있어야 한다."
  }
}
