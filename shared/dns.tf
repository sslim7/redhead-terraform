# ══════════════════════════════════════════════════════════════════════════════
# 🔴 이 파일이 이 레포에서 가장 위험한 부분이다. 고치기 전에 이 주석을 끝까지 읽어라.
#
# redhead.kr 은 **purelymail.com 으로 메일을 쓰고 있다.** 네임서버를 GCP 로 옮기는 순간
# 가비아 DNS 에 들어 있는 레코드는 아무도 물어보지 않는 값이 되고, 아래 7개가 Cloud DNS 에
# 없으면 메일이 끊긴다.
#
#   MX 가 없으면              → 들어오는 메일이 전부 수신 실패한다
#   SPF/DKIM/DMARC 가 없으면  → 보내는 메일이 스팸 처리되거나 거부된다
#
# **이 실패는 apply 결과에도, 웹 접속에도, 서버 로그에도 드러나지 않는다.** apply 는
# 성공하고 사이트는 정상으로 보인다. 알게 되는 경로는 "며칠 전 보낸 메일을 상대가 못 받았다"
# 는 연락뿐이고, 그때는 이미 끊긴 채로 며칠이 지나 있다.
#
# 그래서 규칙이 셋이다.
#   1. 레코드를 **먼저** 다 만들고, GCP 네임서버에 직접 질의해 확인한 **뒤에** 네임서버를 옮긴다
#      (`dig @<GCP NS> MX redhead.kr`. 공용 리졸버에 물으면 아직 가비아 값을 돌려주므로
#       확인이 되지 않는다). 순서를 뒤집으면 빈 영역이 권한을 갖고 도메인 전체가 죽는다.
#   2. 가비아 DNS 관리의 기존 레코드는 지우지 말고 남긴다 — 네임서버를 되돌리면 즉시 복구되는
#      유일한 롤백 수단이다.
#   3. apex 레코드는 shared/ 만 선언한다(아래 참고).
# ══════════════════════════════════════════════════════════════════════════════

# 영역만 만든다. 레코드는 아래 module.dns_records_apex 와 앱 루트가 각자 넣는다.
# 도메인 등록·갱신은 계속 가비아에 남는다 — .kr 은 Cloud Domains 가 지원하지 않는다.
#
# 비용: Cloud DNS 에는 무료 티어가 없다. 관리 영역 1개당 $0.20/월 + 쿼리 100만건당 $0.40.
module "dns_zone" {
  source = "../modules/dns-zone"

  project_id = google_project.this.project_id
  zone_name  = var.dns.zone_name
  dns_name   = "${var.domains.apex}."

  depends_on = [module.project_services]
}

# 🔴 **apex 전용 호출이다.** 이 모듈 호출에 서브도메인(jayeon 등) 레코드를 넣지 마라.
# 서브도메인은 앱 루트(apps/<앱>/)가 자기 state 에서 넣는다. 여기로 끌어오면 앱을 하나
# 추가할 때마다 메일 레코드가 들어 있는 이 state 를 건드려야 한다.
#
# 🔴 거꾸로도 마찬가지다. **apex 레코드는 여기서만 선언한다.** 레코드는 (라벨, 타입) 단위로
# 충돌하는데, 앱 루트가 같은 조합을 또 선언하면 나중에 apply 한 쪽이 앞의 것을 조용히 덮고
# **Terraform 은 그것을 감지하지 못한다**(state 가 달라 서로를 보지 못한다). 앱이 apex TXT 를
# 하나 추가하는 것만으로 SPF 와 purelymail 소유권 증명이 함께 사라진다.
#
# A 레코드는 **없다.** 현재 redhead.kr 은 apex 에 A 가 없고 www 도 없다(dig 로 확인).
# 없는 것을 새로 만들지 않는다 — 이번 작업은 현재 상태를 그대로 옮기는 것이고, 이관과 신규
# 설정을 같은 apply 에 섞으면 무엇이 무엇을 깨뜨렸는지 가를 수 없다. 나중에 소개 사이트를
# apex 에 붙이게 되면 Firebase Hosting 의 고정 IP 를 a_records 의 "" 키로 넣을 자리가 여기다
# (apex 는 CNAME 을 쓸 수 없다 — RFC 1034 §3.6.2).
module "dns_records_apex" {
  source = "../modules/dns-records"

  project_id = google_project.this.project_id

  # 영역 출력을 그대로 넘긴다. 앱 루트는 이 값을 remote state 로 읽지 않고 문자열로 적는다
  # (이유는 modules/dns-records/variables.tf).
  zone_name   = module.dns_zone.zone_name
  dns_name    = module.dns_zone.dns_name
  default_ttl = var.dns.ttl

  # 🔴 apex 라벨("")의 TXT 두 값은 **한 리스트에 함께** 들어가야 한다.
  # google_dns_record_set 은 (이름, 타입) 조합당 하나만 존재하므로, 이 둘을 따로 선언하면
  # 나중에 apply 되는 쪽이 앞의 것을 지운다. 소유권 증명이 사라지면 purelymail 이 도메인
  # 소유를 재확인하지 못해 메일 처리를 멈추고, SPF 가 사라지면 보낸 메일이 스팸 처리된다.
  txt_records = {
    "" = [
      var.mail.ownership_proof,
      var.mail.spf,
    ]
  }

  # 수신 경로. 우선순위가 여러 개로 늘어나도 이 리스트 하나에 모은다.
  mx_records = {
    "" = var.mail.mx
  }

  # DKIM 3개와 DMARC. 값이 아니라 CNAME 위임이므로 purelymail 이 키를 교체해도 여기는
  # 그대로 둔다 — 값으로 박아 두면 교체되는 날 조용히 DKIM fail 이 시작된다.
  cname_records = merge(
    var.mail.dkim_cnames,
    { "_dmarc" = var.mail.dmarc_cname },
  )

  depends_on = [module.dns_zone]
}
