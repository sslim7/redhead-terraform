output "database_id" {
  description = "Firestore 데이터베이스 리소스 ID (projects/{project}/databases/{name})"
  value       = google_firestore_database.default.id
}

output "database_name" {
  description = "Firestore 데이터베이스 이름"
  value       = google_firestore_database.default.name
}

output "location_id" {
  description = "Firestore 데이터베이스 위치"
  value       = google_firestore_database.default.location_id
}

output "index_names" {
  description = "생성된 복합 인덱스의 서버 측 이름 목록"
  value       = sort([for idx in google_firestore_index.composite : idx.name])
}

output "rules_release_name" {
  description = "배포된 보안 규칙 릴리스 이름. rules_file 이 null 이면 null"
  value       = one(google_firebaserules_release.firestore[*].name)
}
