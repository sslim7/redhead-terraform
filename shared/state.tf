# Terraform state 보관용 버킷. shared/ 와 apps/<앱>/ 이 prefix 만 달리해 같은 버킷을 쓴다.
#
# 닭과 달걀 문제가 있다 — 이 버킷을 만들려면 apply 를 해야 하는데 그 apply 의 state 를 담을
# 곳이 아직 없다. 그래서 첫 apply 는 로컬 state 로 돌고, 그 뒤에 옮긴다(순서는 versions.tf).
#
# 🔴 버킷 이름도 **전역 유일값**이다. "redhead-kr-tfstate" 가 이미 쓰이고 있으면 apply 가
# 409 로 실패한다. 이름은 project_id 에서 파생시키므로 프로젝트 ID 를 바꾸면 함께 바뀐다 —
# 그때 versions.tf 의 backend bucket 도 같이 고쳐야 한다(그쪽은 변수를 쓸 수 없다).
resource "google_storage_bucket" "tfstate" {
  project  = google_project.this.project_id
  name     = "${var.gcp.project_id}-tfstate"
  location = var.gcp.region

  # ACL 을 끄고 IAM 하나로만 접근을 통제한다. 둘이 공존하면 IAM 을 아무리 좁혀도
  # 오브젝트 ACL 로 뚫린 구멍이 남는다.
  uniform_bucket_level_access = true

  # 🔴 형식적인 설정이 아니다. **이 버킷의 state 에는 생성된 JWT 서명키가 평문으로 들어간다** —
  # apps/jayeon/ 이 random_password 로 만들어 Secret Manager 에 넣는 값이고, Terraform 은
  # 만든 값을 state 에 그대로 기록한다(Secret Manager 에 넣었다는 사실과 무관하다).
  # 이 버킷이 공개되면 WAS 의 토큰을 누구나 위조할 수 있다. 실수로 allUsers 를 붙이는
  # 경로 자체를 막는다 — enforced 는 프로젝트·조직 정책보다 우선하며 되돌리려면 이 코드를 고쳐야 한다.
  public_access_prevention = "enforced"

  # 잘못된 apply 나 state 손상에서 되돌릴 유일한 수단이다. state 는 수백 KB라 세대가 쌓여도
  # 저장 비용이 문제되지 않는다.
  versioning {
    enabled = true
  }

  # 세대를 무한히 쌓지는 않는다. 20개면 최근 apply 20회 안에서 되돌릴 수 있고,
  # 그보다 오래된 state 로 돌아가는 것은 이미 인프라와 맞지 않아 쓸 수 없다.
  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [module.project_services]
}
