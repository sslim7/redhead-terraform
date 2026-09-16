# 전제: GitHub 저장소 연결은 Terraform 으로 만들 수 없다.
# Cloud Build GitHub App 설치와 저장소 연결은 콘솔에서 1회 수동으로 해야 하며,
# 연결되지 않은 저장소를 참조하면 트리거 생성 apply 가 실패한다.
# 따라서 이 모듈은 "저장소가 이미 연결되어 있다"를 전제로 동작한다.
resource "google_cloudbuild_trigger" "this" {
  for_each = var.triggers

  project  = var.project_id
  location = var.location
  name     = each.key

  filename       = each.value.filename
  substitutions  = each.value.substitutions
  included_files = each.value.included_files
  disabled       = each.value.disabled

  # 커스텀 SA 로 빌드하면 기본 Cloud Build SA 의 광범위한 권한을 쓰지 않게 된다.
  # 대신 이 SA 에 빌드·푸시·배포 권한이 모두 붙어 있어야 한다.
  #
  # 트리거마다 다른 SA 를 쓸 수 있게 열어 둔다. 하나로 묶으면 "정적 파일만 올리면 되는 빌드"가
  # Cloud Run 배포 권한까지 들고 돌게 되고, 그 레포에 커밋 권한이 있는 사람은 누구나
  # 운영 서비스를 갈아끼울 수 있게 된다. 지정하지 않으면 공용 deployer 를 쓴다.
  service_account = "projects/${var.project_id}/serviceAccounts/${coalesce(each.value.service_account_email, var.deployer_sa_email)}"

  github {
    owner = each.value.github_owner
    name  = each.value.github_repo

    # branch 와 tag 는 상호 배타적이다. 둘 다 넣으면 API 가 거부한다.
    push {
      branch = each.value.branch_regex
      tag    = each.value.tag_regex
    }
  }
}
