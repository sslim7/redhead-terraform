output "email" {
  description = "서비스 계정 이메일"
  value       = google_service_account.this.email
}

output "name" {
  description = "서비스 계정 리소스 name (projects/{project}/serviceAccounts/{email})"
  value       = google_service_account.this.name
}

output "id" {
  description = "서비스 계정 Terraform 리소스 ID"
  value       = google_service_account.this.id
}

output "member" {
  description = "IAM 정책에 그대로 넣을 수 있는 멤버 문자열 (serviceAccount:{email})"
  value       = "serviceAccount:${google_service_account.this.email}"
}
