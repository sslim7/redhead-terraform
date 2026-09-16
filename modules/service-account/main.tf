resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}

# 역할은 항상 멤버 단위(_iam_member)로 붙인다.
# _binding / _policy 는 authoritative 라서 Terraform 밖에서 붙은 권한
# (Google 관리 서비스 에이전트 등)을 apply 때 조용히 제거한다.
resource "google_project_iam_member" "this" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.this.email}"
}

# 자기 자신을 가장할 수 있는 권한. 서명 URL·커스텀 토큰이 이 계정의 키 없이 동작하려면 필요하다.
resource "google_service_account_iam_member" "self_token_creator" {
  count = var.self_token_creator ? 1 : 0

  service_account_id = google_service_account.this.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.this.email}"
}
