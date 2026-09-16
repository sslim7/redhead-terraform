# 앱들이 공유하는 컨테이너 이미지 저장소. Cloud Run 과 같은 리전에 둬서 이미지 pull 이
# 리전 내부에서 끝나게 한다(리전을 섞으면 pull 마다 네트워크 비용이 붙는다).
module "artifact_registry" {
  source = "../modules/artifact-registry"

  project_id    = google_project.this.project_id
  location      = var.gcp.region
  repository_id = var.artifact_registry.repository_id
  description   = "redhead 서비스 컨테이너 이미지 (앱들이 공유한다)"

  # 무료 한도가 0.5GB 뿐이라 방치하면 몇 달 만에 넘긴다.
  cleanup = {
    keep_tagged_count = var.artifact_registry.keep_tagged_count
    untagged_max_age  = var.artifact_registry.untagged_max_age
  }

  # 🔴 의도적으로 비워 둔다. 저장소는 shared/ 가 하나만 소유하지만, 여기에 push 하는 배포 SA 는
  # 앱마다 따로 있고 **앱 루트가 자기 권한을 자기 state 에서 붙인다**
  # (apps/<앱>/ 의 google_artifact_registry_repository_iam_member).
  #
  # 여기에 목록으로 모으면 앱을 하나 추가할 때마다 shared/ 를 고쳐야 하고, 그 apply 가
  # 프로젝트·DNS 존·메일 레코드가 들어 있는 state 를 건드린다 — 권한 한 줄 추가가 도메인
  # 전체를 위험에 넣는 구조는 두지 않는다.
  #
  # 이게 안전한 이유는 모듈이 _binding 이 아니라 **_iam_member(non-authoritative)** 를 쓰기
  # 때문이다. _binding 이라면 멤버 목록이 authoritative 해져서 여기 빈 리스트를 넘기는 순간
  # 앱들이 붙여 둔 권한을 전부 지워 버린다(지워진 쪽은 다음 배포가 push 403 으로 깨질 때까지
  # 아무 징후가 없다). _iam_member 는 자기가 선언한 멤버만 관리하므로 루트가 여러 개여도 겹치지 않는다.
  writer_members = []
  # reader 도 같다. 이미지를 pull 하는 Cloud Run SA 는 앱 루트가 만든다.
  reader_members = []

  depends_on = [module.project_services]
}
