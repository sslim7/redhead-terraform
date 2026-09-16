# 구조적 설정만 둔다. 계정·자격증명 성격의 값(billing_account)은 local.auto.tfvars 에 있고
# 그 파일은 커밋하지 않는다 (.gitignore 참고). 여기 값은 전부 공개돼도 무해한 식별자다.

gcp = {
  project_id   = "redhead-kr"
  project_name = "redhead"
  region       = "asia-northeast3"
}

domains = {
  apex = "redhead.kr"
}

dns = {
  zone_name = "redhead"
  # 이관 중에는 낮게 둔다. 잘못된 응답이 캐시에 남는 시간이 곧 장애 시간이다.
  ttl = 600
}

artifact_registry = {
  repository_id     = "redhead"
  keep_tagged_count = 5
  # API 가 Duration 을 초 문자열로 정규화하므로 "7d" 대신 초로 넘겨 permadiff 를 피한다.
  # 값 자체는 7일이다.
  untagged_max_age = "604800s"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔴 메일(purelymail.com) 레코드. 7개가 전부 있어야 메일이 산다.
#
# **이 값들의 출처.** 이관 전 원본은 가비아 DNS 관리 화면의 레코드 목록이고, 그것이 실제로
# 공개 DNS 에 떠 있는지 dig 로 교차 확인했다. 즉 purelymail 문서를 보고 옮겨 적은 것이 아니라
# **지금 떠 있는 실측값**이다.
#
#   dig TXT   redhead.kr
#   dig MX    redhead.kr
#   dig CNAME purelymail1._domainkey.redhead.kr   (2, 3 도 같은 방식으로)
#   dig CNAME _dmarc.redhead.kr
#
# 값을 고칠 일이 생기면 purelymail 콘솔에서 바꾼 뒤 여기를 맞춘다. 순서를 뒤집으면 그 사이
# 메일이 끊긴다. 네임서버 이전 후에는 위 dig 에 `@<GCP NS>` 를 붙여야 이 값이 보인다.
# ══════════════════════════════════════════════════════════════════════════════

mail = {
  # purelymail 의 도메인 소유권 증명. 사라지면 purelymail 이 소유를 재확인하지 못한다.
  ownership_proof = "purelymail_ownership_proof=fda431efcf3513466fda7d213b52f4f59a5fbc75125f9be4ba7c5c1f61a93e5ab182633d8bddc62456ddd9e5a164ba6f1f33afe2372b57126701f393d9f654ee"

  # ~all(softfail)은 purelymail 이 안내하는 값 그대로다. -all 로 조이면 전달(forwarding)된
  # 메일이 반송될 수 있어 실측값을 바꾸지 않는다.
  spf = "v=spf1 include:_spf.purelymail.com ~all"

  # 수신 서버. 끝 점이 있어야 절대 도메인으로 해석된다 — 빼면 Cloud DNS 가 영역 이름을
  # 이어 붙여(mailserver.purelymail.com.redhead.kr.) 수신이 조용히 죽는다.
  mx = [
    { priority = 10, target = "mailserver.purelymail.com." },
  ]

  # DKIM 공개키 3개. purelymail 이 키를 교체할 수 있어 값이 아니라 CNAME 으로 위임한다.
  # 하나라도 빠지면 그 키로 서명된 메일이 DKIM fail 이 된다.
  dkim_cnames = {
    "purelymail1._domainkey" = "key1.dkimroot.purelymail.com."
    "purelymail2._domainkey" = "key2.dkimroot.purelymail.com."
    "purelymail3._domainkey" = "key3.dkimroot.purelymail.com."
  }

  # DMARC 정책도 purelymail 이 관리하도록 위임한다.
  dmarc_cname = "dmarcroot.purelymail.com."
}
