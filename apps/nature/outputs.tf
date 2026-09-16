# 🔴 생성된 시크릿 값(JWT_SECRET · ADMIN_JWT_SECRET)은 출력하지 않는다.
#
# 값은 이미 state 에 평문으로 있으므로 output 이 노출 범위를 "원리적으로" 넓히지는 않는다.
# 그래도 내보내지 않는 이유는 경로가 늘어나기 때문이다 — output 으로 두면 `terraform output`
# 한 번에 서명키가 셸 히스토리·터미널 스크롤백·CI 로그로 복사된다. state 는 버킷 IAM 하나로
# 닫혀 있지만 그 사본들은 아무 통제도 받지 않는다.
#
# 키를 꺼내야 할 일이 생기면 Secret Manager 에서 직접 본다:
#   gcloud secrets versions access latest --secret=JWT_SECRET --project=redhead
# (그 호출은 감사 로그에 남는다. output 은 남지 않는다.)

# ── 서비스 주소 ─────────────────────────────────────────────────────────────

# DNS 전파·Hosting 릴리스 전의 스모크 테스트에 쓴다.
#
# ⚠ WAS 를 이 주소로 확인할 때 경로는 **`/health`** 다. `/healthz` 는 Google Frontend 가
# 가로채 자체 404(HTML)를 돌려주므로 run.app 주소로도 컨테이너까지 오지 않는다 — 서비스가
# 멀쩡한데 404 를 보고 배포가 실패했다고 판단하게 된다(§run.tf).
output "cloud_run_uris" {
  description = "Cloud Run 서비스의 기본 HTTPS 엔드포인트. WAS 스모크 체크 경로는 /health 다(/healthz 가 아니다)"
  value = {
    (var.cloud_run.app_name) = module.app.uri
    (var.cloud_run.was_name) = module.was.uri
  }
}

# Hosting 이 자동 발급한 *.web.app 주소.
#
# dns.tf 의 CNAME 대상이 이 사이트들이다. 커스텀 도메인이 아직 검증되지 않았을 때도
# 이 주소로는 접근할 수 있어, rewrite 가 제대로 올라갔는지 먼저 확인하는 데 쓴다.
output "hosting_default_urls" {
  description = "Firebase Hosting 기본 URL. rewrite 릴리스 확인용 (커스텀 도메인 검증과 무관하게 동작한다)"
  value = {
    (var.hosting.app_site_id) = module.hosting_app.default_url
    (var.hosting.api_site_id) = module.hosting_api.default_url
  }
}

# ── 도메인 검증 상태 확인 ───────────────────────────────────────────────────
#
# Firebase 가 각 커스텀 도메인에 대해 요구하는 DNS 레코드의 **원본**이다.
# 우리는 이미 Cloud DNS 에 CNAME 을 넣어 두었으므로(dns.tf) 손으로 넣을 것은 없고,
# 이 출력은 **검증이 진행 중인지 / 무엇이 빠졌는지**를 보는 용도다.
#
# 모듈이 wait_dns_verification = false 라 apply 는 검증을 기다리지 않는다. 즉 apply 성공은
# "도메인이 뜬다" 를 뜻하지 않는다 — 검증이 끝나야 관리형 인증서가 발급되고, 그전까지
# 도메인은 인증서 오류 또는 404 다. `terraform refresh` 후 이 값을 보면 최신 상태다.
output "hosting_dns_records" {
  description = "도메인 → Firebase 가 요구하는 DNS 변경 목록(원본). 커스텀 도메인 검증 상태를 확인할 때 본다"
  value = merge(
    module.hosting_app.dns_records,
    module.hosting_api.dns_records,
  )
}

# 이 영역에는 shared/ 가 넣은 apex 레코드(메일 등)와 다른 앱의 레코드, 그리고 영역 생성 시
# 자동으로 붙는 SOA/NS 가 함께 산다. 이 출력은 **이 state 가 소유한 것만** 보여준다.
output "dns_record_names" {
  description = "이 앱이 소유한 DNS 레코드의 FQDN 목록. shared/ 의 apex 레코드와 다른 앱의 레코드는 포함하지 않는다"
  value       = module.dns_records.record_names
}

# ── 운영에 필요한 식별자 ────────────────────────────────────────────────────

# 콘솔에서 Cloud Build 트리거를 확인할 때, 그리고 이 계정에 권한을 더 붙여야 할 때 쓴다.
output "deployer_sa_email" {
  description = "Cloud Build 가 이 계정으로 빌드한다. 트리거를 만드는 주체도 이 계정에 대해 iam.serviceAccountUser 가 있어야 한다"
  value       = module.deployer_service_account.email
}

# 항상 "(default)" 다. 값 자체가 아니라 **이 프로젝트의 (default) DB 를 jayeon 이 가져갔다**는
# 사실을 드러내려고 둔다 — 다음 앱은 named DB(전액 과금)를 쓰거나 별도 프로젝트로 가야 한다.
output "firestore_database_name" {
  description = "Firestore 데이터베이스 이름. 프로젝트당 (default) 는 하나뿐이고 이 앱이 그것을 쓴다"
  value       = module.firestore.database_name
}
