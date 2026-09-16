# 이 프로젝트에서 쓰는 Google API 를 한 곳에서 켠다. 목록의 기본값은 모듈이 들고 있다
# (modules/project-services/variables.tf) — 어떤 API 가 왜 필요한지도 거기 적혀 있다.
#
# depends_on 이 필수다. project_id 는 리터럴 문자열이라 Terraform 이 프로젝트와의 순서를
# 스스로 알 수 없고, 프로젝트가 없는 상태에서 활성화를 호출하면 403 이 난다
# (404 가 아니라 403 이어서 원인이 "프로젝트가 없다" 로 보이지 않는다).
module "project_services" {
  source = "../modules/project-services"

  project_id = google_project.this.project_id

  depends_on = [google_project.this]
}
