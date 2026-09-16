# Firestore Native 데이터베이스 하나와 그 인덱스·보안 규칙을 관리한다.
#
# **API 활성화는 이 모듈이 하지 않는다.** firestore.googleapis.com 과 firebaserules.googleapis.com
# 은 shared/ 의 modules/project-services 가 켠다. 두 state 가 같은 google_project_service
# 리소스를 각자 관리하면 소유권이 갈리고, 한쪽 destroy 가 다른 쪽이 쓰는 API 를 끄거나
# (disable_on_destroy 를 어떻게 두든) 같은 리소스를 두 번 만들려다 apply 가 깨진다.
# 그래서 여기는 "API 는 이미 켜져 있다" 를 전제로만 동작한다 — 전제를 보장하는 것은
# apply 순서(shared 먼저)뿐이고 Terraform 은 이걸 강제하지 못한다.

# (default) 데이터베이스만 만든다.
# Firestore 무료 쿼터(저장 1GiB, 일일 읽기 50,000 / 쓰기 20,000 / 삭제 20,000)는
# 프로젝트당 (default) 데이터베이스 하나에만 적용된다.
# 이름 있는(named) 추가 데이터베이스는 무료 쿼터가 없고 전액 과금되므로 만들지 않는다.
#
# 🔴 redhead 는 **우산 프로젝트**다. `redhead.kr` 아래로 앱이 계속 늘어나는데 (default)
# 데이터베이스는 프로젝트에 하나뿐이고, 지금 그것을 jayeon 이 가져갔다. 다음 앱이 Firestore 를
# 쓰려면 named 데이터베이스(전액 과금)를 만들거나 별도 프로젝트로 가야 한다. 두 번째 앱이
# 이 모듈을 그대로 복사해 호출하면 같은 (default) 를 두 state 가 주장하게 되고, 먼저 만든
# 쪽이 이긴 채로 나중 apply 가 alreadyExists 로 깨진다 — **Terraform 이 막아 주지 않는다.**
resource "google_firestore_database" "default" {
  project = var.project_id
  name    = "(default)"

  # 🔴 생성 후 변경 불가. 바꾸려면 데이터베이스를 지우고 다시 만들어야 하고, 그것은
  # 데이터를 버리는 일이다. Cloud Run 과 같은 리전에 둔다.
  location_id = var.location_id
  type        = "FIRESTORE_NATIVE"

  # PITR 을 켜면 변경 이력 보관에 별도 스토리지 과금이 발생한다. 무료티어 유지를 위해 비활성화.
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_DISABLED"

  delete_protection_state = var.database.delete_protection_state
  deletion_policy         = var.database.deletion_policy
}

# 복합 인덱스.
# 인덱스가 없으면 서비스가 즉시 죽지 않고 해당 쿼리를 쓰는 화면만 500(FAILED_PRECONDITION)을
# 뱉으므로 **배포 후에야 발견된다.** 기동·헬스체크·다른 API 는 전부 정상이라 알람도 울리지
# 않는다. 그래서 쿼리를 추가하는 커밋과 같은 호흡으로 여기에 인덱스를 더해야 한다.
#
# API 는 필드가 2개 미만인 복합 인덱스를 거부한다. 단일 필드 collection group 인덱스는
# 이 리소스로 만들 수 없어 google_firestore_field 로 따로 만든다(아래).
resource "google_firestore_index" "composite" {
  # for_each 키에 **스코프와 각 필드의 방향까지** 넣는다.
  #
  # Firestore 에서 인덱스의 정체성은 (컬렉션, 쿼리 스코프, 필드 순서, **각 필드의 방향**)이다.
  # 필드 이름만으로 키를 만들면 방향만 다른 두 인덱스가 하나로 뭉개진다 —
  # `(adminId asc, createdAt asc)` 과 `(adminId asc, createdAt desc)` 는 서로 다른 인덱스이고
  # 둘 다 필요한데(정렬 방향이 요청 파라미터인 화면이 있다), 이름만으로 키를 만들면 같은 키가
  # 되어 `Duplicate object key` 로 plan 이 통째로 실패한다.
  #
  # plan 이 깨지는 쪽은 그래도 눈에 보인다. 위험한 것은 그때 키를 고치지 않고 인덱스 하나를
  # 빼서 넘어가는 것이다 — 그러면 **그 방향의 쿼리만** 런타임에 FAILED_PRECONDITION 500 이
  # 되고, 기동·헬스체크·반대 방향 요청은 전부 정상이라 배포 후에야 발견된다.
  #
  # 같은 필드 조합을 COLLECTION 과 COLLECTION_GROUP 두 스코프로 둘 수도 있고 그것도 서로
  # 다른 인덱스라, query_scope 도 키에 들어간다.
  #
  # order 와 array_config 는 변수 validation 이 "정확히 하나" 를 보장하므로 coalesce 로 합친다.
  for_each = {
    for idx in var.indexes :
    "${idx.collection}:${idx.query_scope}:${join(",", [
      for f in idx.fields : "${f.field_path}:${coalesce(f.order, f.array_config)}"
    ])}" => idx
  }

  project     = var.project_id
  database    = google_firestore_database.default.name
  collection  = each.value.collection
  query_scope = each.value.query_scope

  # 필드 순서가 곧 인덱스의 의미다. 순서를 바꾸면 다른 인덱스가 되고 기존 쿼리가 깨진다.
  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_path   = fields.value.field_path
      order        = fields.value.order
      array_config = fields.value.array_config
    }
  }

  depends_on = [google_firestore_database.default]
}

# 단일 필드 collection group 인덱스.
# Firestore 가 자동 생성하는 단일 필드 인덱스는 COLLECTION 스코프뿐이라,
# collectionGroup() 쿼리는 필드가 하나여도 명시 생성이 필요하다.
#
# index_config 를 지정하면 그 필드의 인덱스 구성이 통째로 대체된다.
# 그래서 실제로 필요한 COLLECTION_GROUP 스코프뿐 아니라, 원래 자동으로 있던
# COLLECTION 스코프 ASCENDING/DESCENDING 도 같이 적어야 기본 인덱스가 사라지지 않는다.
resource "google_firestore_field" "single" {
  # 위 composite 와 달리 키에 방향이 없어도 된다. 이쪽은 필드 하나가 리소스 하나이고
  # 방향(orders)은 그 리소스 **안의** index_config 로 들어가므로, 같은 필드를 방향만 바꿔
  # 두 번 선언할 일이 없다 — 오히려 두 번 선언하면 나중 것이 앞의 구성을 통째로 대체한다.
  for_each = {
    for f in var.single_field_indexes :
    "${f.collection}:${f.field}" => f
  }

  project    = var.project_id
  database   = google_firestore_database.default.name
  collection = each.value.collection
  field      = each.value.field

  index_config {
    dynamic "indexes" {
      for_each = each.value.orders
      content {
        order       = indexes.value
        query_scope = "COLLECTION"
      }
    }

    indexes {
      order       = "ASCENDING"
      query_scope = "COLLECTION_GROUP"
    }
  }

  depends_on = [google_firestore_database.default]
}

# 보안 규칙.
# ruleset 은 불변 객체다. 내용이 바뀌면 새 ruleset 을 만들고 release 가 그것을 가리키게 한다.
# create_before_destroy 를 걸어야 release 가 옮겨 간 뒤에 옛 ruleset 이 지워진다.
# 반대 순서면 release 가 사라진 ruleset 을 가리키는 순간이 생긴다.
resource "google_firebaserules_ruleset" "firestore" {
  count    = var.rules_file != null ? 1 : 0
  provider = google-beta

  project = var.project_id

  source {
    files {
      name    = "firestore.rules"
      content = file(var.rules_file)
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_firestore_database.default]
}

# "cloud.firestore" 는 (default) 데이터베이스의 활성 규칙을 가리키는 고정 릴리스 이름이다.
# firebase CLI 의 `deploy --only firestore:rules` 도 같은 이름을 덮어쓴다.
# 두 경로로 배포하면 서로를 되돌리므로 배포 주체를 Terraform 하나로 고정한다.
resource "google_firebaserules_release" "firestore" {
  count    = var.rules_file != null ? 1 : 0
  provider = google-beta

  project      = var.project_id
  name         = "cloud.firestore"
  ruleset_name = "projects/${var.project_id}/rulesets/${google_firebaserules_ruleset.firestore[0].name}"
}
