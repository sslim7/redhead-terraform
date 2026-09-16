# 🔴 project 에 들어가는 값은 var.gcp.project_id 이고, 이 변수는 variables.auto.tfvars 의
# 리터럴 문자열("redhead")이다. 그래서 프로젝트가 아직 없는 첫 apply 에서도 프로바이더 설정
# 자체는 문제없이 평가된다 — 리소스 참조(google_project.this.project_id)를 쓰면 프로바이더
# 설정이 apply 중에 결정되는 값에 의존해 init/plan 단계에서 깨진다.
#
# 대신 이 프로바이더를 타는 리소스는 **프로젝트가 생긴 뒤에** 만들어져야 한다. 프로바이더 설정은
# 그 순서를 보장하지 않으므로(리터럴이라 프로젝트 존재 여부를 모른다) 모든 모듈·리소스 호출에
# depends_on 으로 순서를 직접 걸어 둔다. 빠뜨리면 "프로젝트가 없다"는 404 가 아니라
# 권한 오류(403)로 나와 원인을 찾기 어렵다.
provider "google" {
  project = var.gcp.project_id
  region  = var.gcp.region

  # GCP 라벨은 키/값 모두 소문자, 숫자, 하이픈, 밑줄만 허용한다.
  default_labels = {
    managed-by  = "terraform"
    service     = "redhead"
    environment = "production"
  }
}

provider "google-beta" {
  project = var.gcp.project_id
  region  = var.gcp.region

  default_labels = {
    managed-by  = "terraform"
    service     = "redhead"
    environment = "production"
  }
}

# 🔴 Firebase 리소스 전용 별칭. 이게 없으면 apply 가 403 으로 막힌다.
#
# firebase·firebasehosting·firebaserules API 는 **요청마다 quota project 를 요구한다.** 사용자
# ADC(`gcloud auth application-default login`)로 부르면 요청의 소비 프로젝트가 gcloud 가 쓰는
# 구글 소유 클라이언트 프로젝트로 잡히고, redhead 에 API 가 켜져 있어도
# `403 SERVICE_DISABLED` 가 난다. 에러 메시지는 "API 를 켜라" 고 말하는데 이미 켜져 있어서,
# 이 주석이 없으면 켜고 다시 켜 보는 데 시간을 쓴다.
#
# ADC 파일의 quota_project_id 는 답이 아니다. gcloud SDK 와 달리 Terraform 의 google
# 프로바이더는 그 값을 자동으로 쓰지 않고, user_project_override = true 일 때만
# X-Goog-User-Project 헤더를 붙인다. billing_project 가 그 헤더에 들어갈 값이다.
#
# **기본 google-beta 에 걸지 않고 별칭으로 가른 이유.** 이 옵션은 해당 프로바이더를 타는
# **모든** 리소스의 요청 경로를 바꾼다. 지금 shared/ 에서 google-beta 를 쓰는 것은
# google_firebase_project 하나뿐이라 기본에 걸어도 결과가 같지만, 그때는 "지금 결과가 같다"는
# 사실이 유일한 안전장치가 된다. quota project 를 요구하지 않는 beta 리소스를 하나 들이는 날
# 그 안전장치가 소리 없이 사라지고, 그 리소스는 billing_project 를 대고 호출되기 시작한다.
# 별칭은 무엇이 이 옵션을 필요로 하는지를 호출부에 적어 두게 만든다(firebase.tf).
provider "google-beta" {
  alias = "firebase"

  project               = var.gcp.project_id
  region                = var.gcp.region
  user_project_override = true
  billing_project       = var.gcp.project_id

  default_labels = {
    managed-by  = "terraform"
    service     = "redhead"
    environment = "production"
  }
}
