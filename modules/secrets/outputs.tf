output "secret_ids" {
  description = "시크릿 이름 → secret_id (Cloud Run 의 secret 참조에 쓰는 짧은 이름)"
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}

output "secret_names" {
  description = "시크릿 이름 → 전체 리소스 name (projects/{number}/secrets/{secret_id})"
  value       = { for k, s in google_secret_manager_secret.this : k => s.name }
}

# Terraform 이 생성한 시크릿의 **평문 값**.
#
# 같은 비밀을 Secret Manager 밖에서도 써야 할 때만 쓴다 — 예컨대 헤더에 평문으로 값을 실어야
# 하는 호출자(Cloud Scheduler 등)가 생겼을 때다. Cloud Run 처럼 시크릿을 직접 마운트할 수
# 있는 곳은 secret_ids 를 쓰고 이 값을 보지 않는다.
#
# 값은 어차피 state 에 평문으로 들어 있어 이 출력이 노출 범위를 넓히지는 않는다.
# 그래도 sensitive 로 두어 plan/apply 로그에 찍히지 않게 한다.
#
# 🔴 루트 모듈의 output 으로 그대로 흘려보내지 마라. `terraform output` 한 번으로 서명키가
# 셸 히스토리와 CI 로그에 남는다.
output "generated_values" {
  description = "Terraform 이 생성한 시크릿 이름 → 평문 값 (manual·initial_value 지정 시크릿은 없음)"
  value       = { for k, r in random_password.this : k => r.result }
  sensitive   = true
}
