# 이 출력들은 **사람이 보기 위한 것이다.**
#
# apps/<앱>/ 은 이 값을 terraform_remote_state 로 읽지 않는다. 프로젝트 ID·영역 이름·리전처럼
# 한 번 정하면 바뀌지 않는 값을 자기 tfvars 에 문자열로 적는다. 그렇게 해 두면 앱 루트가
# shared/ 의 state 를 읽을 권한을 가질 필요가 없고(그 state 에는 다른 앱의 값도 들어 있다),
# 이 파일의 출력 구조를 바꿀 때 모든 앱의 plan 이 동시에 깨지는 일도 없다.
#
# 따라서 여기서 무엇을 지우거나 이름을 바꿔도 앱은 깨지지 않는다. 대신 운영 작업(네임서버
# 이전, 이미지 경로 확인) 때 볼 것이 없어진다.

output "project_id" {
  description = "운영 GCP 프로젝트 ID"
  value       = google_project.this.project_id
}

# 프로젝트 ID 와 다른 값이다. IAM 멤버 문자열 중 일부(Cloud Build·Compute 기본 SA 등)가
# 이 숫자를 쓰므로, 앱 루트에서 그런 멤버를 적을 때 여기서 확인한다.
output "project_number" {
  description = "프로젝트 번호. 일부 기본 서비스 계정 이메일이 이 숫자를 포함한다"
  value       = google_project.this.number
}

output "dns_zone_name" {
  description = "Cloud DNS 관리 영역의 리소스 이름. 앱 루트의 tfvars 에 이 값을 문자열로 적는다"
  value       = module.dns_zone.zone_name
}

output "dns_name" {
  description = "관리 중인 도메인 (끝 점 포함)"
  value       = module.dns_zone.dns_name
}

# ── 🔴 사람이 실제로 쓰는 유일한 출력 ────────────────────────────────────────
# 이 네 개를 가비아 > 도메인 > 네임서버 설정에 입력하면 이관이 끝난다. 그 전에 반드시
# 메일 레코드 7개가 GCP 네임서버에서 응답하는지 직접 확인하라(dns.tf 상단, README §apply 순서).
output "name_servers" {
  description = "가비아 > 도메인 > 네임서버 설정에 입력할 값. 메일 레코드 확인 후에 바꾼다"
  value       = module.dns_zone.name_servers
}

# 앱의 cloudbuild.yaml 이 이미지를 이 경로 아래로 push 한다(거기서는 $PROJECT_ID 로 조립한다).
# 손으로 이미지를 올리거나 태그를 확인할 때 쓴다.
output "docker_repo_url" {
  description = "이미지 태그 앞에 붙는 Docker 저장소 경로"
  value       = module.artifact_registry.docker_repo_url
}

output "artifact_registry_repository_id" {
  description = "Artifact Registry 저장소 ID (이미지 경로의 마지막 세그먼트)"
  value       = module.artifact_registry.repository_id
}
