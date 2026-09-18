variable "project_id" {
  description = "API 를 활성화할 GCP 프로젝트 ID"
  type        = string
}

variable "services" {
  description = "활성화할 Google API 목록. 기본값은 이 구성에서 실제로 사용하는 API 전체다"
  type        = list(string)
  default = [
    # 프로젝트·API 자체를 다루는 API. 이게 없으면 나머지 활성화 호출부터 막힌다.
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    # terraform state 를 담는 GCS 버킷. backend 가 죽으면 아무 것도 apply 할 수 없어
    # 실질적으로 가장 먼저 켜져 있어야 하는 API 다.
    "storage.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    # redhead.kr 의 권한 DNS 를 Cloud DNS 가 갖는다. 도메인 등록·갱신만 가비아에 남는다
    # (.kr 은 Cloud Domains 가 지원하지 않는다).
    "dns.googleapis.com",
    # Cloud Run 앞단 커스텀 도메인을 Firebase Hosting 으로 붙인다.
    # asia-northeast3 에 Cloud Run 도메인 매핑이 없어서 이 경로를 쓴다.
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    # jayeon-was 의 유일한 데이터 저장소다(Native 모드). 별도 DB 인스턴스를 띄우지 않는 이유는
    # Cloud SQL 이 트래픽 0에서도 인스턴스 고정비를 받기 때문이고, 그래서 이 API 가 꺼지면
    # WAS 는 대체 저장소 없이 그냥 동작하지 못한다.
    "firestore.googleapis.com",
    # WAS 의 JWT 서명키 2개(access·refresh)를 담는다. 키를 Cloud Run 환경변수에 직접 박으면
    # 콘솔·`gcloud run services describe`·배포 이력에 평문으로 남고 교체 이력도 사라진다.
    "secretmanager.googleapis.com",
    # Firestore 보안 규칙 배포용. 앱이 Firestore 를 클라이언트에서 직접 읽는 구조라면 규칙이
    # 유일한 접근 통제선이고, 이 API 가 없으면 규칙 리소스 apply 가 403 으로 막힌다.
    # firestore.googleapis.com 과 별개 API 라서 따로 켜야 한다.
    "firebaserules.googleapis.com",
    # 통화분석 작업 스윕(tick). Cloud Scheduler 가 1분마다 WAS 의 내부 엔드포인트를 두드린다
    # (apps/nature/call-jobs.tf). Cloud Run 은 요청이 없으면 인스턴스를 내리므로 백그라운드
    # 워커를 띄우는 대신 이 방식을 쓴다 — min_instance_count 를 1 로 올리지 않기 위해서다.
    "cloudscheduler.googleapis.com",
    # 🔴 GCS 서명 URL 발급에 필요하다. Cloud Run 의 ADC 에는 개인키가 없어서, 서명을
    # 이 API 의 signBlob 으로 대신 받는다(apps/nature/iam.tf 의 self_token_creator).
    # 대부분의 프로젝트에 기본으로 켜져 있어 빠뜨리기 쉽고, 빠지면 업로드가 아니라
    # **URL 을 만드는 단계**에서 403 이 난다 — 버킷 IAM 은 멀쩡해서 원인이 그쪽으로 보인다.
    "iamcredentials.googleapis.com",
  ]

  validation {
    condition     = length(var.services) > 0
    error_message = "services 는 최소 1개 이상이어야 한다."
  }
}
