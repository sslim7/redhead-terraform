# 프로젝트에서 쓰는 API 를 한 곳에서 활성화한다.
#
# disable_on_destroy = false : destroy 시 API 자체를 끄면 Terraform 이 관리하지 않는
# 같은 프로젝트의 다른 리소스까지 함께 죽는다. 되돌리기 어려운 부작용이라 끄지 않는다.
# disable_dependent_services = false : 의존 API 연쇄 비활성화도 같은 이유로 막는다.
resource "google_project_service" "this" {
  for_each = toset(var.services)

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
