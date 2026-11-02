# Hosting 이 자동 발급한 *.web.app 주소. 커스텀 도메인 검증 전에도 deploy 결과를 여기서 본다.
output "hosting_default_url" {
  description = "Firebase Hosting 기본 URL. 커스텀 도메인 검증과 무관하게 동작한다"
  value       = module.hosting.default_url
}

# Firebase 가 커스텀 도메인에 요구하는 DNS 레코드의 원본. CNAME 은 dns.tf 가 이미 넣으므로
# 손으로 넣을 것은 없고, 검증이 진행 중인지 / 무엇이 빠졌는지 보는 용도다.
# wait_dns_verification = false 라 apply 성공이 "도메인이 뜬다" 를 뜻하지 않는다.
output "hosting_dns_records" {
  description = "도메인 → Firebase 가 요구하는 DNS 변경 목록(원본). 커스텀 도메인 검증 상태를 확인할 때 본다"
  value       = module.hosting.dns_records
}

output "dns_record_names" {
  description = "이 앱이 소유한 DNS 레코드의 FQDN 목록. shared/ 의 apex 레코드와 다른 앱의 레코드는 포함하지 않는다"
  value       = module.dns_records.record_names
}

output "url" {
  description = "커스텀 도메인 주소. 인증서 발급과 makes 쪽 deploy 가 끝나야 콘텐츠가 뜬다"
  value       = "https://${var.domain}"
}

# Firebase JS SDK 의 initializeApp() 에 그대로 넣는 값.
# 🔴 비밀이 아니다 — 브라우저 번들에 실려 누구나 본다. 접근 통제는 Firestore 규칙
# (firestore.rules.tftpl)과 Auth 가 한다. 그래서 sensitive 로 두지 않는다.
output "firebase_web_config" {
  description = "Firebase 웹 앱 공개 설정(apiKey · authDomain · projectId · appId · storageBucket · messagingSenderId)"
  value = {
    apiKey            = data.google_firebase_web_app_config.makes.api_key
    authDomain        = data.google_firebase_web_app_config.makes.auth_domain
    projectId         = var.project_id
    appId             = google_firebase_web_app.makes.app_id
    storageBucket     = data.google_firebase_web_app_config.makes.storage_bucket
    messagingSenderId = data.google_firebase_web_app_config.makes.messaging_sender_id
  }
}

output "firestore_database_id" {
  description = "덱 편집본 Firestore 데이터베이스 이름. SDK 의 getFirestore(app, \"<이 값>\") 에 넣는다"
  value       = module.firestore.database_name
}
