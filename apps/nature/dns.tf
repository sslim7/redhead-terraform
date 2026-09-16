# ╔══════════════════════════════════════════════════════════════════════════╗
# ║ 🔴🔴 apex 라벨("")을 이 파일에서 **절대** 선언하지 마라 🔴🔴               ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# `redhead.kr` 의 apex 에는 purelymail 메일 레코드(MX·SPF·DKIM·DMARC)가 살고 있고,
# 그것들은 **shared/ 가 소유한다.**
#
# google_dns_record_set 은 (이름, 타입) 조합당 하나만 존재한다. 같은 조합을 두 state 가
# 각자 선언하면 **나중에 apply 한 쪽이 앞의 것을 통째로 덮어쓴다** — 병합되지 않는다.
# 여기서 apex TXT 를 하나 선언하는 순간 apex 의 SPF·DKIM·DMARC 가 그 값으로 대체되고,
# apex MX 를 선언하면 메일 서버 목록이 사라진다. 결과는 **메일이 끊기는 것**이다:
# MX 가 없으면 수신 실패, SPF/DKIM/DMARC 가 없으면 보내는 메일이 스팸 처리되거나 거부된다.
#
# 🔴 그리고 이 실패는 **조용하다.** apply 는 성공하고, plan 에도 "apex TXT 를 만든다" 로만
# 나온다(다른 state 가 같은 레코드를 갖고 있다는 사실을 Terraform 은 알지 못한다). 웹은
# 멀쩡하고, 발신 쪽 바운스나 "메일이 안 온다" 는 연락을 받기 전까지 아무 징후가 없다.
#
# 이 루트가 선언해도 되는 것은 **이 앱의 서브도메인뿐이다.** 서브도메인끼리는 (이름, 타입)이
# 달라 충돌하지 않으므로, 앱을 늘려도 서로의 레코드를 건드리지 않는다.
#
# ── 🔴 CNAME 이 붙은 이름에는 다른 레코드를 둘 수 없다 (RFC 1034 §3.6.2) ─────
#
# 그래서 아래 두 라벨에 TXT 를 얹지 않는다. 얹으려 해도 Cloud DNS 가 거부한다.
# 도메인 소유권 증명 TXT 도 필요 없다 — 서브도메인은 CNAME 자체가 소유권 증명이다
# (Firebase 가 요구하는 것은 "이 이름이 우리 사이트를 가리키는가" 이고 CNAME 이 그 답이다).
# 확인이 필요하면 outputs.hosting_dns_records 로 Firebase 가 요구하는 원본을 본다.
#
# apex 에 CNAME 을 둘 수 없는 것도 같은 규칙이다(영역 apex 에는 항상 SOA/NS 가 있다).
# modules/dns-records 의 validation 이 apex CNAME 은 plan 단계에서 막아 준다 —
# 다만 apex **TXT·MX** 는 막아 주지 않는다. 그건 위 경고를 사람이 지켜야 한다.

module "dns_records" {
  source = "../../modules/dns-records"

  project_id = var.project_id

  # shared/ 가 만든 영역을 이름으로만 가리킨다. 이 모듈은 영역을 만들지 않는다.
  # remote state 를 읽지 않는 이유는 variables.tf 상단에.
  zone_name = var.zone_name
  dns_name  = var.dns_name

  # 두 서브도메인을 각자의 Hosting 사이트로 넘긴다.
  # 대상은 Hosting 모듈의 site_id 출력에서 조립한다 — site_id 를 바꾸면 이 레코드도 함께
  # 따라오게 하려는 것이다. 문자열로 따로 적으면 한쪽만 고쳐 도메인이 죽은 사이트를 가리킨다.
  #
  # 끝 점을 붙인다. 없으면 Cloud DNS 가 영역 이름을 이어 붙여
  # redhead-jayeon-app.web.app.redhead.kr. 로 해석한다 — 모듈이 보정해 주지만 명시한다.
  cname_records = {
    "nature"     = "${module.hosting_app.site_id}.web.app."
    "nature-api" = "${module.hosting_api.site_id}.web.app."
    "jayeon"     = "${module.hosting_app.site_id}.web.app."
    "jayeon-api" = "${module.hosting_api.site_id}.web.app."
  }

  # a_records / txt_records / mx_records 를 지정하지 않는다. 지정할 것이 없다 —
  # 이 앱의 도메인은 둘 다 서브도메인이고 CNAME 으로 끝난다. 위 경고를 참고.
}
