output "repository_id" {
  description = "저장소 ID (이미지 경로의 마지막 세그먼트)"
  value       = google_artifact_registry_repository.this.repository_id
}

# 프로바이더의 name 속성은 짧은 이름("redhead")만 돌려주므로
# gcloud/API 에 그대로 넘길 수 있는 전체 경로인 id 를 쓴다.
output "repository_name" {
  description = "저장소 전체 리소스 경로 (projects/{project}/locations/{location}/repositories/{id})"
  value       = google_artifact_registry_repository.this.id
}

output "docker_repo_url" {
  description = "이미지 태그 앞에 붙이는 Docker 저장소 경로"
  value       = "${var.location}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}
