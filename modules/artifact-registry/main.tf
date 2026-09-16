resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"

  cleanup_policy_dry_run = var.cleanup.dry_run

  # 태그를 잃은 이미지는 롤백 대상이 될 수 없으므로 기간만 지나면 지운다.
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = var.cleanup.untagged_max_age
    }
  }

  # KEEP 정책은 DELETE 정책보다 우선한다. 최근 N개는 어떤 경우에도 남겨
  # 직전 버전으로 롤백할 수 있게 한다.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.cleanup.keep_tagged_count
    }
  }
}

# writer/reader 는 _binding 이 아니라 _iam_member 다. 저장소는 shared/ 가 하나만 소유하지만
# 거기에 push·pull 하는 주체는 앱마다 따로 있고, 각 앱 루트(apps/<앱>/)가 자기 배포 SA 를
# 이 저장소에 덧붙인다. _binding 으로 묶으면 그 목록이 authoritative 해져서 한 앱의 apply 가
# 다른 앱이 붙여 둔 권한을 지워 버린다 — 지워진 쪽은 다음 배포가 push 403 으로 깨질 때까지
# 아무 징후가 없다. _iam_member 는 자기가 선언한 멤버만 관리하므로 루트가 여러 개여도 겹치지 않는다.
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each = toset(var.writer_members)

  project    = var.project_id
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value
}

resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each = toset(var.reader_members)

  project    = var.project_id
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
