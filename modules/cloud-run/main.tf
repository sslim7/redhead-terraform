resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  location = var.location
  name     = var.name
  labels   = var.labels

  # 개인 프로젝트라 서비스를 지우고 다시 만드는 상황을 허용해야 한다.
  # true 로 두면 destroy 는 물론 재생성이 필요한 변경까지 프로바이더가 거부한다.
  deletion_protection = false

  template {
    service_account = var.service_account_email
    timeout         = var.timeout

    max_instance_request_concurrency = var.scaling.concurrency

    scaling {
      min_instance_count = var.scaling.min_instance_count
      max_instance_count = var.scaling.max_instance_count
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.resources.cpu
          memory = var.resources.memory
        }
        cpu_idle          = var.resources.cpu_idle
        startup_cpu_boost = var.resources.startup_cpu_boost
      }

      # 평문 환경변수와 시크릿 환경변수는 같은 env 블록 타입을 공유한다.
      # 변수를 나눠 받는 이유는 시크릿 값이 평문 맵에 섞여 state 에 남는 것을 막기 위해서다.
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }

      dynamic "startup_probe" {
        for_each = var.startup_probe == null ? [] : [var.startup_probe]
        content {
          initial_delay_seconds = startup_probe.value.initial_delay_seconds
          period_seconds        = startup_probe.value.period_seconds
          timeout_seconds       = startup_probe.value.timeout_seconds
          failure_threshold     = startup_probe.value.failure_threshold

          http_get {
            # 프로브는 컨테이너가 실제로 리스닝하는 포트로 보내야 하므로 container_port 를 그대로 쓴다.
            path = startup_probe.value.path
            port = var.container_port
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # 배포 이미지는 Cloud Build 가 커밋마다 갱신한다. 여기서 무시하지 않으면
      # 다음 terraform apply 가 운영 중인 이미지를 부트스트랩 이미지로 되돌린다.
      template[0].containers[0].image,
      # gcloud run deploy 는 client/client_version 을 자기 값으로 덮어쓴다.
      # 무시하지 않으면 배포할 때마다 의미 없는 diff 가 생긴다.
      client,
      client_version,
    ]
  }
}

# allUsers 에 대한 공개 호출 허용.
# authoritative 한 _iam_policy / _iam_binding 대신 _iam_member 를 써서
# 콘솔이나 다른 도구가 추가한 바인딩을 지우지 않게 한다.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.this.project
  location = google_cloud_run_v2_service.this.location
  name     = google_cloud_run_v2_service.this.name

  role   = "roles/run.invoker"
  member = "allUsers"
}
