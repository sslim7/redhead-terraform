provider "google" {
  project = var.project_id
  region  = var.region

  # GCP 라벨은 키/값 모두 소문자, 숫자, 하이픈, 밑줄만 허용한다.
  #
  # app 라벨을 두는 이유 — 이 프로젝트는 우산 프로젝트라 여러 앱의 리소스가 한 프로젝트에
  # 섞여 산다. 콘솔과 청구 내역에서 "이게 누구 것인가" 를 가르는 유일한 단서다.
  default_labels = {
    managed-by = "terraform"
    app        = "nature"
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed-by = "terraform"
    app        = "nature"
  }
}

# Firebase 리소스(Hosting 사이트·커스텀 도메인, Firestore 보안 규칙) 전용 별칭.
#
# 🔴 **이 별칭이 없으면 Hosting 과 보안 규칙 apply 가 403 으로 막힌다.**
#
# firebasehosting·firebaserules API 는 요청마다 quota project 를 요구한다. 사용자 ADC 로
# 부르면 요청의 소비자가 구글 소유 프로젝트(gcloud SDK 의 기본 클라이언트 프로젝트)로 잡혀
# **redhead 에 API 가 켜져 있어도** 403 SERVICE_DISABLED 가 난다. 에러 메시지는 "API 를
# 활성화하라" 고 말하는데 이미 켜져 있어서, 이걸 모르면 shared/ 의 project-services 를
# 의심하며 시간을 버린다.
#
# ADC 파일의 quota_project_id 는 답이 되지 않는다. gcloud SDK 와 달리 Terraform 의 google
# 프로바이더는 그 값을 자동으로 쓰지 않고, user_project_override 가 켜져 있을 때만
# X-Goog-User-Project 헤더를 붙인다. billing_project 는 그 헤더에 실릴 값이다.
#
# 기본 google-beta 에 걸지 않고 별칭으로 가른 이유 — 이 옵션은 그 프로바이더를 타는 **모든**
# 리소스의 요청 경로를 바꾼다. 지금은 google-beta 를 쓰는 것이 Firebase 리소스뿐이라 기본에
# 걸어도 결과가 같지만, 그때는 "지금 결과가 같다" 는 사실이 유일한 안전장치가 된다.
# quota project 를 요구하지 않는 beta 리소스를 하나 들이는 날 그 안전장치가 소리 없이
# 사라지고, 그 리소스는 billing_project 를 대고 호출되기 시작한다. 별칭은 무엇이 이 옵션을
# 필요로 하는지를 호출부에 적어 두게 만든다.
#
# 배선 — 리소스가 모듈 안에 있으므로 호출부에서 모듈의 google-beta 를 이 별칭에 연결한다
# (hosting.tf, firestore.tf 의 `providers` 블록). 모듈 안쪽은 `provider = google-beta`
# 그대로 두어 모듈이 별칭 이름을 알 필요가 없게 한다.
provider "google-beta" {
  alias = "firebase"

  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    managed-by = "terraform"
    app        = "nature"
  }
}
