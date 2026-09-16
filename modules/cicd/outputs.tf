output "trigger_ids" {
  description = "트리거 이름 → 트리거 리소스 ID"
  value       = { for k, v in google_cloudbuild_trigger.this : k => v.id }
}

output "trigger_names" {
  description = "트리거 이름 → Cloud Build 트리거 이름"
  value       = { for k, v in google_cloudbuild_trigger.this : k => v.name }
}
