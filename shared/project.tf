# redhead 우산 도메인 아래의 모든 것이 들어가는 GCP 프로젝트. 이 리소스가 이 레포 전체의 뿌리다.
#
# 🔴 project_id 는 **GCP 전역 유일값**이다. 남이 이미 "redhead" 를 쓰고 있으면 이 apply 가
# 실패한다(그 프로젝트가 삭제 대기 중이어도 30일간 ID 가 잠긴다). 그 경우 variables.auto.tfvars
# 의 gcp.project_id 를 바꾸면 되는데, **Artifact Registry 이미지 경로가 프로젝트 ID 를
# 포함한다**는 점을 함께 봐야 한다:
#   asia-northeast3-docker.pkg.dev/<프로젝트 ID>/redhead/<이미지>
# jayeon-app·jayeon-was 의 cloudbuild.yaml 은 이 경로를 $PROJECT_ID 로 참조하므로 실제로는
# 자동으로 따라오지만, 어딘가에 경로를 문자열로 박아 둔 곳이 생기면 그날 함께 깨진다.
#
# 조직이 없다 — org_id 도 folder_id 도 지정하지 않는다.
# `gcloud organizations list` 가 0건이므로(Workspace/Cloud Identity 를 쓰지 않는 개인 계정)
# 이 프로젝트는 **부모 없는 프로젝트**로 만들어진다. 둘 중 하나라도 넣으면 존재하지 않는 부모를
# 가리켜 apply 가 실패한다. 나중에 조직을 만들면 프로젝트를 그 아래로 이동할 수 있지만,
# 조직 정책·상속 IAM 이 한꺼번에 따라붙으므로 그때는 별개의 작업으로 다룬다.
resource "google_project" "this" {
  project_id = var.gcp.project_id
  name       = var.gcp.project_name

  # 결제가 붙어야 API 활성화부터 통과한다. 무료 한도 안에서 쓰더라도 계정 연결 자체는 필요하다.
  billing_account = var.billing_account

  # 🔴 운영 프로젝트다. `terraform destroy` 한 번이 프로젝트를 통째로 지우는 일을 막는다.
  # 값은 PREVENT / ABANDON / DELETE 셋 중 하나이고 프로바이더에서 Computed 라서,
  # **명시하지 않으면 의도가 코드에 남지 않는다** — 다음 사람이 "여기 기본값이 뭐였지" 를
  # 프로바이더 소스에서 찾아야 하고, 그 기본값은 프로바이더 메이저 버전에 따라 바뀐다.
  # 진짜로 프로젝트를 접을 때는 이 값을 먼저 커밋으로 바꾸게 만드는 것이 목적이다.
  deletion_policy = "PREVENT"

  # Cloud Run은 VPC 연결 없이 운영한다. VM이나 VPC 커넥터를 만들지 않는다.
  # false는 기본 VPC 생성을 막는 것이 아니라 Compute API 활성화 후 삭제하는 옵션이다.
  # 프로젝트 부트스트랩이 그 API 오류에 막히지 않도록 기본 VPC 정리는 별도로 유예한다.
  # 기존 프로젝트에서 이 값을 바꿔도 네트워크를 생성하거나 삭제하지 않는다.
  # 추후 false로 되돌리는 것만으로 기존 VPC가 삭제되지는 않는다.
  auto_create_network = true
}
