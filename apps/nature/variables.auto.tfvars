# Nature 리브랜딩: 공개 domains만 변경한다. Cloud Run/Hosting/GitHub ID는 기존 운영 대상을 보존한다.
# 구조적 설정만 둔다. 자격증명·키 성격의 값은 이 파일에 넣지 않는다
# (이 앱은 그런 값이 없다 — JWT 서명키는 Terraform 이 만들고 Secret Manager 에만 산다).

# shared/ 가 만든 것을 문자열로 가리킨다. remote state 를 읽지 않는 이유는 variables.tf 상단에.
project_id                      = "redhead-kr"
region                          = "asia-northeast3"
zone_name                       = "redhead"
dns_name                        = "redhead.kr."
artifact_registry_repository_id = "redhead"

firestore = {
  # 생성 후 변경 불가. Cloud Run 과 같은 리전에 둔다.
  location_id             = "asia-northeast3"
  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  deletion_policy         = "ABANDON"
}

domains = {
  app = "nature.redhead.kr"
  api = "nature-api.redhead.kr"
}

hosting = {
  # site_id 는 Firebase 전역 유일값이라 프로젝트 이름을 접두어로 붙였다.
  app_site_id = "redhead-jayeon-app"
  api_site_id = "redhead-jayeon-api"
}

cloud_run = {
  app_name = "jayeon-app"
  was_name = "jayeon-was"
  # 실제 이미지는 Cloud Build 가 밀어 넣는다. Terraform 은 이후 이미지 변경을 무시한다.
  bootstrap_image    = "us-docker.pkg.dev/cloudrun/container/hello"
  cpu                = "1"
  memory             = "512Mi"
  timeout            = "60s"
  max_instance_count = 3
  container_port     = 8080
}

# WAS 실제 이미지가 배포된 뒤에 true 로 바꾼다.
# 부트스트랩 hello 이미지에는 /healthz 가 없어서, 켠 채로 첫 apply 를 하면 리비전이 Ready 가
# 되지 못해 apply 자체가 실패한다.
enable_was_startup_probe = false

cicd = {
  location     = "global" # 기존 1세대 GitHub repository mapping 리전
  github_owner = "sslim7"
  app_repo     = "jayeon-app"
  was_repo     = "jayeon-was"
  # release 브랜치 커밋에 v 태그를 붙여 push 하면 배포된다.
  tag_regex = "^v.*$"
  disabled  = false
}

# sslim7/jayeon-was 를 콘솔에서 Cloud Build 에 연결한 뒤 true 로 바꾼다.
# 연결 전에 true 로 두면 트리거 생성이 실패하며, 다른 리소스는 일부 생성된 채 남을 수 있다.
enable_was_trigger = true
