# GitHub 연결은 2026-09-16 CreateGitHubInstallation 감사로그에서 global로 확인했다.
# 트리거도 global이어야 한다. _REGION substitution은 Cloud Run/Registry용 asia-northeast3를 유지한다.
# 배포 파이프라인. 빌드는 Cloud Build 무료 한도(월 2,500 build-minutes) 안에서 돈다.
#
# ── 🔴 선행 조건: GitHub 저장소 연결은 Terraform 으로 만들 수 없다 ────────────
#
# 콘솔 > Cloud Build > 트리거 > 저장소 연결 에서 **Cloud Build GitHub App 을 1회 수동으로
# 설치**하고 저장소(sslim7/jayeon-app, sslim7/jayeon-was)를 연결해야 한다.
# 연결되지 않은 저장소를 참조하면 트리거 생성 apply 가 실패한다. 이 단계는 Terraform 으로
# 표현할 방법이 없다 — OAuth 설치 승인이 사람의 행위이기 때문이다.
#
# 그래서 저장소 README 의 apply 순서에 이 단계가 5번으로 들어가 있다.
#
# ── 🔴 태그 규칙이 표현하는 것과 표현하지 못하는 것 ──────────────────────────
#
# 배포 규칙은 "release 브랜치 커밋에 붙인 v 태그를 push 하면 배포" 다. 그런데
# **Git 에서 태그는 브랜치에 속하지 않는다** — 태그는 커밋을 가리킬 뿐이고, 그 커밋이 어느
# 브랜치에서 도달 가능한지는 태그의 속성이 아니다. Cloud Build 는 그 조건을 표현할 수단이
# 없어서 `^v.*$` 는 "v 로 시작하는 태그가 푸시됐다" 까지만 안다.
#
# 즉 실수로 staging 커밋에 `v0.2.0` 을 붙여 밀어도 **빌드는 똑같이 돈다.** 이건 도구가
# 막아 주는 것이 아니라 **사람이 지키는 규칙**이다.
#
# 앵커(^)를 빼지 마라. 빼면 `site-v1.0.0` 처럼 중간에 v 가 있는 태그까지 잡아 태그 하나가
# 빌드 두 개를 돌리게 된다.
#
# ── 🔴 substitution 을 추가할 때는 cloudbuild.yaml 도 함께 고쳐야 한다 ───────
#
# 트리거의 substitution 은 cloudbuild.yaml 의 빌드 스텝에서 실제로 참조해야 반영된다.
# YAML 의 기본값 선언과 Docker 빌드 인자 전달도 함께 유지한다.
#
# 변수를 하나 늘릴 때 고칠 곳은 세 군데다: 이 파일 · cloudbuild.yaml 의 substitutions ·
# 그 값을 쓰는 빌드 스텝.
module "cicd" {
  source = "../../modules/cicd"

  project_id        = var.project_id
  location          = var.cicd.location
  deployer_sa_email = module.deployer_service_account.email

  triggers = merge(
    {
      # Expo 웹 → nginx 이미지.
      "jayeon-app" = {
        github_owner = var.cicd.github_owner
        github_repo  = var.cicd.app_repo
        tag_regex    = var.cicd.tag_regex
        disabled     = var.cicd.disabled

        # 🔴 `EXPO_PUBLIC_*` 는 **빌드 시점에 웹 번들로 인라인**되므로 반드시 여기로 와야 한다.
        # Cloud Run 환경변수로 주면 리비전에는 남지만 브라우저가 받는 값은 옛 번들 그대로다
        # (§run.tf 의 module.app). 값을 바꾸면 이미지 재빌드가 필요하다.
        #
        # 값이 서로를 가리킨다 — 웹앱은 API 도메인을, 웹뷰 URL 은 자기 도메인을 쓴다.
        # 그래서 var.domains 한 곳만 고치면 번들까지 따라온다. 문자열로 따로 박으면
        # 도메인을 바꾸는 날 번들이 죽은 주소를 들고 나간다.
        substitutions = {
          _REGION                  = var.region
          _REPO                    = var.artifact_registry_repository_id
          _SERVICE                 = var.cloud_run.app_name
          _EXPO_PUBLIC_API_URL     = "https://${var.domains.api}"
          _EXPO_PUBLIC_ENV         = "production"
          _EXPO_PUBLIC_WEBVIEW_URL = "https://${var.domains.app}"
        }
      }
    },

    # Go 백엔드 이미지.
    #
    # GitHub 연결을 마친 뒤 enable_was_trigger = true 로 활성화한다.
    # 연결 전 생성은 실패하며, 이미 생성된 다른 리소스는 롤백되지 않는다.
    # Go 런타임 설정은 run.tf 가 소유하고, 여기서는 이미지/배포 대상만 전달한다.
    var.enable_was_trigger ? {
      "jayeon-was" = {
        github_owner = var.cicd.github_owner
        github_repo  = var.cicd.was_repo
        tag_regex    = var.cicd.tag_regex
        disabled     = var.cicd.disabled

        substitutions = {
          _REGION  = var.region
          _REPO    = var.artifact_registry_repository_id
          _SERVICE = var.cloud_run.was_name
        }
      }
    } : {},
  )

  # 트리거가 만들어진 직후 빌드가 시작되어도 배포 대상과 권한이 준비되어 있어야 한다.
  depends_on = [
    module.app,
    module.was,
    module.deployer_service_account,
    google_artifact_registry_repository_iam_member.deployer_writer,
    google_service_account_iam_member.deployer_acts_as_app,
    google_service_account_iam_member.deployer_acts_as_was,
  ]
}
