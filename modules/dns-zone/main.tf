# redhead.kr 의 권한 DNS 를 Cloud DNS 로 옮긴다. 이 모듈은 **관리 영역만** 만들고 레코드는
# 하나도 만들지 않는다. 레코드는 modules/dns-records 가 담당한다.
#
# **왜 쪼갰나.** redhead.kr 은 여러 앱이 서브도메인으로 사는 우산 도메인이다. 영역은
# shared/ 가 하나만 소유하고, 앱마다 자기 서브도메인 레코드를 apps/<앱>/ 에서 따로 만든다.
# 영역과 레코드가 한 모듈에 묶여 있으면 앱을 하나 추가할 때마다 shared 의 레코드 맵을
# 고쳐야 하고, 그러면 앱 하나의 실수가 **메일 레코드(MX·SPF·DKIM·DMARC)가 들어 있는
# 영역 전체**를 건드리게 된다. 서브도메인 하나 붙이는 변경이 도메인 메일을 끊을 수 있는
# 구조는 두지 않는다. 쪼개 두면 앱 루트의 state 에는 그 앱 레코드만 들어오고, 영역과
# 메일 레코드는 shared/ 밖에서 손댈 수 없다.
#
# 비용: Cloud DNS 에는 무료 티어가 없다. 관리 영역 1개당 $0.20/월이 고정으로 나가고,
# 쿼리는 100만건당 $0.40 이 추가된다. 앱마다 영역을 따로 파면 고정비가 그만큼 배로 드는데,
# 서브도메인을 위임하지 않는 한 그럴 이유가 없다 — 그래서 영역은 하나뿐이다.
#
# 이관 순서: 반드시 (1) dns-records 로 레코드를 전부 만들고 → (2) name_servers 출력을 가비아
# 네임서버 설정에 입력한다. 순서를 뒤집어 네임서버부터 바꾸면, 빈 영역이 권한을 갖게 되어
# 전파가 끝날 때까지 도메인 전체가 NXDOMAIN 으로 죽는다. 되돌려도 TTL 만큼 더 걸린다.
resource "google_dns_managed_zone" "this" {
  project     = var.project_id
  name        = var.zone_name
  dns_name    = var.dns_name
  description = var.description

  # 인터넷에서 조회되어야 하므로 public 이다. private 로 만들면 지정한 VPC 안에서만 응답한다.
  visibility = "public"
}
