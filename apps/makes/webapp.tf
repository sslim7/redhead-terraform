# Firebase 웹 앱 — makes 덱 페이지가 Firebase JS SDK(Auth · Firestore)를 초기화할 설정의 출처.
#
# 로그인 공급자(구글)와 Authorized domains 는 여기서 만들지 않는다. Identity Platform config 는
# OAuth 클라이언트를 테라폼이 만들 수 없어 Firebase 콘솔에서 사람이 켠다(README 「Hosting rewrite」).
#
# deletion_policy 는 기본값 ABANDON 을 둔다(명시). DELETE 면 destroy 가 웹 앱을 실제로 지우고,
# 다시 만들면 appId·apiKey 가 바뀌어 makes 저장소에 심어 둔 설정이 조용히 깨진다.
# ABANDON 은 state 에서만 빼므로 앱과 그 설정이 살아남는다.
resource "google_firebase_web_app" "makes" {
  # firebase API 는 quota project 가 필요하다. providers.tf 의 google-beta.firebase 참고.
  provider = google-beta.firebase

  project         = var.project_id
  display_name    = "makes"
  deletion_policy = "ABANDON"
}

data "google_firebase_web_app_config" "makes" {
  provider = google-beta.firebase

  project    = var.project_id
  web_app_id = google_firebase_web_app.makes.app_id
}
