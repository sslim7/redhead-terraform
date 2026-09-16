output "enabled_services" {
  description = "이 모듈이 활성화한 API 목록"
  value       = [for s in google_project_service.this : s.service]
}

output "ready" {
  description = <<-EOT
    API 활성화 완료를 나타내는 더미 값. 모든 google_project_service 에 의존하므로
    다른 모듈이 depends_on 대신 이 값을 참조해 순서를 강제할 수 있다.
    (모듈 전체 depends_on 은 하위 리소스를 전부 unknown 으로 만들어 plan 가독성을 해친다)
  EOT
  value       = join(",", [for s in google_project_service.this : s.service])
}
