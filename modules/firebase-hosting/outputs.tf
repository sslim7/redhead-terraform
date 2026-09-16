output "site_id" {
  description = "Firebase Hosting 사이트 ID"
  value       = google_firebase_hosting_site.this.site_id
}

output "default_url" {
  description = "Firebase 가 자동 발급한 기본 Hosting URL"
  value       = google_firebase_hosting_site.this.default_url
}

# 운영자가 이 값을 보고 등록기관 DNS 에 레코드를 넣는다.
# wait_dns_verification = false 라 apply 직후에는 아직 검증되지 않은 상태로 출력된다.
output "dns_records" {
  description = "도메인별로 등록해야 할 DNS 레코드 (required_dns_updates 원본)"
  value       = { for k, v in google_firebase_hosting_custom_domain.this : k => v.required_dns_updates }
}

output "custom_domain_urls" {
  description = "커스텀 도메인 기반 HTTPS URL 목록"
  value       = [for k, v in google_firebase_hosting_custom_domain.this : "https://${v.custom_domain}"]
}
