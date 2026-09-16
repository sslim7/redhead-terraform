output "zone_name" {
  description = "Cloud DNS 관리 영역의 리소스 이름. 앱별 루트가 modules/dns-records 의 zone_name 에 그대로 넣는다"
  value       = google_dns_managed_zone.this.name
}

output "dns_name" {
  description = "관리 중인 도메인 (끝 점 포함)"
  value       = google_dns_managed_zone.this.dns_name
}

# 이 모듈의 결과물 중 사람이 직접 써야 하는 유일한 값이다.
# 레코드가 모두 만들어진 뒤 이 네 개를 가비아 네임서버 설정에 그대로 입력하면 이관이 끝난다.
output "name_servers" {
  description = "도메인 등록기관(가비아)에 입력할 네임서버 목록"
  value       = google_dns_managed_zone.this.name_servers
}
