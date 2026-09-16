output "name" {
  description = "Cloud Run 서비스 이름"
  value       = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "Cloud Run 서비스의 기본 HTTPS 엔드포인트"
  value       = google_cloud_run_v2_service.this.uri
}

output "location" {
  description = "Cloud Run 서비스 리전"
  value       = google_cloud_run_v2_service.this.location
}

output "id" {
  description = "Cloud Run 서비스 리소스 ID"
  value       = google_cloud_run_v2_service.this.id
}
