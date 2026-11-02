# 🔴🔴 apex 라벨("")을 이 파일에서 **절대** 선언하지 마라 🔴🔴
#
# apex 에는 purelymail 메일 레코드(MX·SPF·DKIM·DMARC)가 살고 shared/ 가 소유한다.
# (이름, 타입)이 같은 레코드를 두 state 가 선언하면 나중 apply 가 앞의 것을 통째로 덮어써
# 메일이 끊기고, 그 실패는 apply 도 plan 도 알려 주지 않는다.
# 이 루트가 선언해도 되는 것은 자기 서브도메인뿐이다. 전문은 apps/nature/dns.tf 상단.

module "dns_records" {
  source = "../../modules/dns-records"

  project_id = var.project_id

  # shared/ 가 만든 영역을 이름으로만 가리킨다. 이 모듈은 영역을 만들지 않는다.
  zone_name = var.zone_name
  dns_name  = var.dns_name

  # 대상은 Hosting 모듈의 site_id 출력에서 조립한다 — site_id 를 바꾸면 레코드도 따라온다.
  # 끝 점이 없으면 영역 이름이 붙어 엉뚱한 곳을 가리킨다(모듈이 보정하지만 명시한다).
  cname_records = {
    "makes" = "${module.hosting.site_id}.web.app."
  }

  # a_records / txt_records / mx_records 는 지정하지 않는다 — 서브도메인 하나가 CNAME 으로
  # 끝나고, CNAME 이 붙은 이름에는 다른 레코드를 둘 수 없다(RFC 1034 §3.6.2).
}
