locals {
  # 값을 아무도 알 필요가 없는 시크릿(JWT 서명키 등)은 Terraform 이 만들어 넣는다.
  generated = { for k, v in var.secrets : k => v if !v.manual && v.initial_value == null }

  # 호출부가 값을 넘긴 시크릿.
  provided = { for k, v in var.secrets : k => v if !v.manual && v.initial_value != null }

  # 외부에서 발급받는 키 중, 아직 부트스트랩 placeholder 가 필요한 것.
  # 실제 값이 올라간 뒤에는 placeholder = false 로 바꿔 Terraform 관리에서 뺀다 —
  # 계속 소유하면 재생성 시 REPLACE_ME 가 latest 를 덮어 기능이 조용히 죽는다.
  manual = { for k, v in var.secrets : k => v if v.manual && v.placeholder }

  # 위 둘은 lifecycle 이 동일하므로 하나의 secret_version 리소스로 합친다.
  auto_values = merge(
    { for k, v in local.provided : k => v.initial_value },
    { for k, v in local.generated : k => random_password.this[k].result },
  )

  # 신규 서비스 계정의 이메일은 apply 전까지 unknown 이다. 키에는 목록의 고정 순번을
  # 쓰고, 계산되는 이메일은 값에만 둔다. 호출자는 accessor_members 순서를 유지해야 한다.
  accessor_bindings = {
    for pair in setproduct(keys(var.secrets), range(length(var.accessor_members))) :
    "${pair[0]}::${pair[1]}" => {
      secret = pair[0]
      member = var.accessor_members[pair[1]]
    }
  }
}

# 특수문자를 빼는 이유 - 이 값들은 환경변수나 URL 로 흘러가는데,
# 셸/URL 인코딩 사고를 감수할 만큼의 엔트로피 이득이 없다(32자 영숫자 = 약 190비트).
resource "random_password" "this" {
  for_each = local.generated

  length  = each.value.random_length
  special = false
}

resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key

  # 무료 티어와 지연시간 관점에서 리전을 직접 고를 이유가 없다. Google 관리 복제를 쓴다.
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "auto" {
  for_each = local.auto_values

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = each.value
}

# 실제 값은 운영자가 올린다. Terraform 이 placeholder 로 되돌리면 서비스가 죽으므로
# secret_data 변경은 무시한다.
resource "google_secret_manager_secret_version" "manual" {
  for_each = local.manual

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
