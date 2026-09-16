# GCP 프로젝트를 Firebase 프로젝트로 승격시킨다.
#
# **왜 필요한가.** Firebase Hosting 사이트는 Firebase 프로젝트 안에만 만들 수 있다. GCP
# 프로젝트와 Firebase 프로젝트는 같은 것의 두 얼굴이지만, 이 리소스가 만드는 승격을 거치지
# 않으면 google_firebase_hosting_site 가 "project not found" 류의 오류로 막힌다 — 콘솔에서
# "Firebase 추가" 를 누르는 일을 코드로 옮긴 것이 이 리소스다.
#
# 🔴 apps/jayeon/ 의 Hosting 사이트 2개가 이것에 의존하지만, **state 가 달라 Terraform 이
# 그 순서를 강제하지 못한다.** apply 순서(shared/ 를 먼저)가 유일한 보장이다(README §apply 순서).
# 순서를 어기면 앱 apply 가 Hosting 사이트 생성에서 실패하고, 그 시점에는 이미 Cloud Run 과
# 배포 SA 가 만들어진 뒤라 부분 적용 상태에서 멈춘다.
#
# provider 는 google-beta.firebase 별칭이다. firebase API 가 요청마다 quota project 를
# 요구하므로 기본 프로바이더로는 403 SERVICE_DISABLED 가 난다(이유는 providers.tf).
#
# destroy 시 이 리소스는 프로젝트의 Firebase 승격을 되돌리지 않는다(API 에 그런 동작이 없다).
# state 에서만 사라지므로, 다시 만들면 import 없이도 성공한다.
resource "google_firebase_project" "this" {
  provider = google-beta.firebase

  project = google_project.this.project_id

  depends_on = [module.project_services]
}
