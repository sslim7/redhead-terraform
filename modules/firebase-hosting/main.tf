# Firebase Hosting 사이트와 커스텀 도메인을 관리한다.
# Cloud Run rewrite 버전과 릴리스는 scripts/hosting-release.sh가 소유한다.
resource "google_firebase_hosting_site" "this" {
  provider = google-beta

  project = var.project_id
  site_id = var.site_id
}

# ── 콘텐츠 소유권의 경계 ─────────────────────────────────────────────────────
# **Hosting 의 버전과 릴리스는 Terraform 이 관리하지 않는다.** 사이트 리소스와 커스텀 도메인
# 까지가 여기 몫이고, 그 안에 무엇을 서빙할지는 전부 밖에서 정한다.
#
#   rewrite 사이트(web·api)  →  `scripts/hosting-release.sh` + `hosting/{site}.json`
#   정적 사이트(intro)       →  배포 파이프라인의 `firebase deploy`
#
# **왜 뺐나.** Hosting 버전 설정에는 `appAssociation` 이 있는데 **프로바이더가 그 필드를
# 노출하지 않는다**(7.44 에도 8.0 에도 `config` 는 headers·redirects·rewrites 뿐이다).
# 기본값 AUTO 는 `/.well-known/assetlinks.json` 을 Firebase 가 만든 빈 배열로 가로채므로,
# 안드로이드 App Links 를 쓰려면 반드시 `NONE` 이어야 한다. 즉 이 설정은 Terraform 으로
# 표현할 방법이 없다.
#
# 그러면 남는 길은 둘뿐이었다 — API 로 얹어 두고 Terraform 과 공존시키거나, 아예 넘기거나.
# 공존은 조용히 되돌아간다. rewrite 를 한 줄만 고쳐 apply 하면 Terraform 이 자기 버전을
# 새로 릴리스하면서 `appAssociation` 을 지우고, **그 순간 App Links 가 죽는데 아무도 모른다**
# (직접 설치한 앱에서는 계속 열려서 테스트로도 안 드러난다). 그래서 넘겼다.
#
# **버전·릴리스 리소스를 다시 들이지 마라.** 들이는 순간 위 사고가 그대로 장전된다.

resource "google_firebase_hosting_custom_domain" "this" {
  provider = google-beta
  for_each = toset(var.custom_domains)

  project       = var.project_id
  site_id       = google_firebase_hosting_site.this.site_id
  custom_domain = each.value

  # DNS 레코드는 호출하는 앱 루트 또는 DNS 운영자가 별도로 관리한다.
  # true 로 두면 apply 가 검증이 끝날 때까지 멈춰 버리므로 기다리지 않는다.
  # 대신 outputs.dns_records 로 필요한 레코드를 노출해 운영자가 보고 등록하게 한다.
  wait_dns_verification = false

  # destroy 시 Firebase 쪽 도메인 연결까지 실제로 제거한다.
  # 남겨두면 같은 도메인을 다른 사이트에 다시 붙일 때 충돌한다.
  #
  # 한 도메인은 한 사이트에만 붙는다. 도메인을 다른 사이트로 옮기는 변경은 Terraform 이
  # "이쪽에서 destroy, 저쪽에서 create" 로 계획하는데 둘 사이에 의존이 없어 순서가 보장되지 않는다.
  # create 가 먼저 잡히면 "이미 사용 중" 으로 apply 가 깨지므로, 옮길 때는 떼는 쪽을
  # -target 으로 먼저 apply 하고 그다음 전체 apply 를 돌린다.
  deletion_policy = "DELETE"
}
