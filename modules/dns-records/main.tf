# **이미 존재하는** 관리 영역에 레코드만 넣는다. 영역은 modules/dns-zone 이 shared/ 에서
# 하나만 만들고, 이 모듈은 그 영역을 이름으로만 가리킨다.
#
# 영역을 만들지 않는 덕분에 여러 루트 모듈이 같은 영역에 서로 겹치지 않는 레코드를 각자 넣을
# 수 있다. redhead.kr 은 우산 도메인이라 앱마다 자기 서브도메인 레코드를 apps/<앱>/ 에서
# 관리하는데, 만약 영역까지 이 모듈이 만들었다면 두 번째 앱의 apply 가 같은 영역을 또 만들려다
# alreadyExists 로 깨지거나, 더 나쁘게는 영역을 import 해 와서 **자기 state 가 영역 전체의
# 주인이라고 믿게** 된다.
#
# 레코드끼리는 (이름, 타입) 단위로만 충돌한다. 즉 앱 A 가 a.redhead.kr 을, 앱 B 가
# b.redhead.kr 을 각자 넣는 것은 안전하지만, 같은 라벨·타입을 두 루트가 동시에 선언하면
# 나중에 apply 한 쪽이 앞의 것을 조용히 덮어쓴다. 그래서 apex 레코드(메일·SPF 등)는
# shared/ 만 선언한다는 규칙을 지켜야 한다 — Terraform 은 이걸 막아 주지 않는다.
resource "google_dns_record_set" "a" {
  for_each = var.a_records

  project      = var.project_id
  managed_zone = var.zone_name
  name         = local.a_names[each.key]
  type         = "A"
  ttl          = var.default_ttl
  rrdatas      = each.value
}

# CNAME 은 같은 이름에 다른 타입의 레코드와 공존할 수 없다(RFC 1034 §3.6.2).
# apex 에는 영역 자체가 항상 SOA/NS 를 갖고 있어서 CNAME 을 둘 수 없고,
# 그래서 루트 도메인은 Firebase 가 알려주는 IP 를 A 레코드로 직접 박는다.
resource "google_dns_record_set" "cname" {
  for_each = var.cname_records

  project      = var.project_id
  managed_zone = var.zone_name
  name         = local.cname_names[each.key]
  type         = "CNAME"
  ttl          = var.default_ttl
  rrdatas      = [local.cname_targets[each.key]]
}

resource "google_dns_record_set" "txt" {
  for_each = var.txt_records

  project      = var.project_id
  managed_zone = var.zone_name
  name         = local.txt_names[each.key]
  type         = "TXT"
  ttl          = var.default_ttl
  rrdatas      = local.txt_rrdatas[each.key]
}

resource "google_dns_record_set" "mx" {
  for_each = var.mx_records

  project      = var.project_id
  managed_zone = var.zone_name
  name         = local.mx_names[each.key]
  type         = "MX"
  ttl          = var.default_ttl
  rrdatas      = local.mx_rrdatas[each.key]
}

locals {
  # 호출부는 apex 를 "" 로, 서브도메인은 "app" 처럼 라벨만 넘긴다.
  # FQDN 조립과 끝 점 처리를 여기 한 곳에서만 하기 위한 것이다.
  a_names     = { for host, _ in var.a_records : host => host == "" ? var.dns_name : "${host}.${var.dns_name}" }
  cname_names = { for host, _ in var.cname_records : host => host == "" ? var.dns_name : "${host}.${var.dns_name}" }
  txt_names   = { for host, _ in var.txt_records : host => host == "" ? var.dns_name : "${host}.${var.dns_name}" }
  mx_names    = { for host, _ in var.mx_records : host => host == "" ? var.dns_name : "${host}.${var.dns_name}" }

  # CNAME 대상에 끝 점이 없으면 영역 이름이 뒤에 붙은 상대 도메인으로 해석된다.
  # (redhead-web.web.app → redhead-web.web.app.redhead.kr.) 실패가 조용해서 반드시 보정한다.
  cname_targets = {
    for host, target in var.cname_records :
    host => endswith(target, ".") ? target : "${target}."
  }

  # Cloud DNS 는 TXT rrdata 를 큰따옴표로 감싼 문자열로 받는다. 감싸지 않으면 API 가 거부한다.
  # 이미 감싸 온 값을 또 감싸면 따옴표까지 레코드 내용이 되므로 그때는 그대로 둔다.
  #
  # 문자열 하나가 255자를 넘으면 여러 조각으로 쪼개 `"앞" "뒤"` 형태로 넣어야 하지만,
  # 이 프로젝트의 TXT 는 hosting-site 확인과 SPF/DMARC 정도라 그럴 일이 없어 구현하지 않았다.
  txt_rrdatas = {
    for host, values in var.txt_records :
    host => [
      for v in values :
      (startswith(v, "\"") && endswith(v, "\"")) ? v : "\"${v}\""
    ]
  }

  # MX 의 rrdata 는 "우선순위 공백 호스트" 한 문자열이다 (예: "10 mailserver.purelymail.com.").
  #
  # **끝 점이 핵심이다.** 점 없이 "mailserver.purelymail.com" 을 넣으면 Cloud DNS 가
  # 영역 이름을 이어 붙여 mailserver.purelymail.com.redhead.kr. 로 해석한다. API 는 이걸
  # 거부하지 않고 레코드도 정상으로 보이지만, 존재하지 않는 호스트를 가리키게 되어
  # **들어오는 메일이 조용히 배달 불가**가 된다. 발신 쪽 바운스를 보기 전까지 아무 징후가 없다.
  # 그래서 호출부가 점을 빼먹어도 여기서 붙여 준다.
  mx_rrdatas = {
    for host, entries in var.mx_records :
    host => [
      for e in entries :
      "${e.priority} ${endswith(e.target, ".") ? e.target : "${e.target}."}"
    ]
  }
}
