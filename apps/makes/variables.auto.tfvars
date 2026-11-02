# 구조적 설정만 둔다. 자격증명·키 성격의 값은 이 파일에 넣지 않는다(이 앱은 그런 값이 없다).

# shared/ 가 만든 것을 문자열로 가리킨다. remote state 를 읽지 않는 이유는 variables.tf 상단에.
project_id = "redhead-kr"
region     = "asia-northeast3"
zone_name  = "redhead"
dns_name   = "redhead.kr."

domain = "makes.redhead.kr"

# Firebase 전역 유일값이라 프로젝트 이름을 접두어로 붙였다. makes 의 .firebaserc 와 맞춘다.
site_id = "redhead-makes"
