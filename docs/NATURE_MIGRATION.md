# Nature 공개 이름·도메인 이행

이번 변경은 로컬 코드/설정 준비다. Terraform plan/apply, Hosting release, Cloud Run 배포와 원격 저장소 이름 변경은 실행하지 않았다.

## 변경과 보존

| 항목 | 목표/현재 설정 |
|---|---|
| 공개 웹 | `nature.redhead.kr` |
| 공개 API | `nature-api.redhead.kr` |
| 구성 루트 | `apps/nature/` (이전 로컬 경로 `apps/jayeon/`) |
| GCS backend | `redhead-kr-tfstate` / **`apps/jayeon` 그대로** |
| Cloud Run | `jayeon-app`, `jayeon-was` 그대로 |
| Firebase Hosting | `redhead-jayeon-app`, `redhead-jayeon-api` 그대로 |
| Runtime/배포 SA | `jayeon-app-run`, `jayeon-was-run`, `jayeon-deployer` 그대로 |
| Cloud Build 트리거·GitHub repo | 기존 `jayeon-app`, `jayeon-was` 그대로 |
| Secret Manager·JWT 값 | 기존 ID, 버전, random 리소스 주소 그대로 |
| Firestore | 프로젝트 `redhead-kr`, `(default)` DB 및 모든 컬렉션 그대로 |
| 코드 이름 | 앱 Nature, Go 모듈 `github.com/sslim7/nature-was` |

설정 루트 폴더는 Terraform resource address에 포함되지 않는다. 모듈/리소스 주소와 backend가 같으므로 이 이동에 `moved` 블록이나 `init -migrate-state`는 필요하지 않다. **prefix를 `apps/nature`로 바꾸지 않는다.** 새 state에서 기존 자원을 다시 만들려는 위험이 있다. `.terraform` 캐시가 없는 환경에서는 같은 backend로 `terraform init`한다.

Cloud Run 두 서비스와 Firestore `(default)`의 실제 존재는 읽기 전용 조회로 확인했다. 모든 Terraform state 항목이 현재 자원과 일치하는지는 아직 확인하지 않았다. 이전 README의 '앱 인프라 apply는 아직' 문구는 오래된 기록이었다.

## 사용자 수동 이행 순서

1. `apps/nature`의 기존 backend와 적용 대상 프로젝트를 확인한다. 사용자가 직접 plan을 검토한다. 예상 범위는 새 두 도메인의 Hosting 매핑/DNS 추가, CORS 신·구 도메인 허용, 프론트 빌드 URL substitution 및 표시용 라벨/이름이다. 기존 DB·시크릿·서비스·SA·Hosting 사이트의 삭제/교체가 보이면 진행하지 않고 원인을 확인한다.
2. 사용자가 별도로 승인한 인프라 적용 후 Nature 도메인의 DNS·Hosting 소유권·인증서 상태를 확인한다. 기존 `jayeon.redhead.kr`, `jayeon-api.redhead.kr` 매핑과 DNS는 그대로 유지한다.
3. 별도 배포 요청에 따라 Nature 웹/API 코드를 기존 Cloud Run 서비스에 배포한다. 앱의 공개 API/WebView URL은 빌드에 인라인되므로 웹 이미지 재빌드가 필요하다. `_SERVICE`는 기존 Cloud Run 이름을 유지한다.
4. Hosting rewrite는 기존 사이트/Cloud Run을 그대로 가리킨다. 필요 시 별도 승인 후 기존 사이트 ID로 Hosting release를 수행한다. 새 사이트 ID를 임의로 생성하지 않는다.
5. Nature HTTPS 로그인·프로필·수신자·이력 및 Android App Links를 검증한다. 구 도메인 제거는 구 클라이언트 사용 여부를 확인한 다음 별도 작업으로 수행한다.

GitHub의 실제 저장소 이름은 아직 `sslim7/jayeon-app` / `sslim7/jayeon-was`다. Go 모듈/앱 패키지명 변경은 원격 저장소 이전을 뜻하지 않는다. 원격 저장소 이전이 별도 승인되면 Cloud Build GitHub App 연결과 `cicd.*_repo`를 함께 갱신한다. Cloud Run/Hosting/SA 이름까지 바꾸는 경우에는 이번 도메인 변경과 분리하여 새 자원 생성·트래픽 전환·롤백 계획을 먼저 수립한다.


## 기존 CI 연결 리전 확인

2026-09-16 Cloud Audit Logs의 성공한 `CreateGitHubInstallation` 요청에서 `parent=projects/redhead-kr/locations/global`, 저장소 `sslim7/jayeon-app`, `sslim7/jayeon-was`, `sslim7/erd` 연결을 확인했다. 기존 연결은 **1세대 global**이다. 서울 리전 트리거 생성의 `Repository mapping does not exist`는 이 연결과 트리거 리전이 달라 발생했다.

`cicd.location=global`로 트리거 위치를 분리했고 Cloud Run/Artifact Registry 및 `_REGION`은 `asia-northeast3`로 유지한다. 새 OAuth 설치나 2세대 연결을 만들 필요가 없다. 공식 문서도 저장소와 트리거의 리전 일치를 요구한다: https://docs.cloud.google.com/build/docs/automating-builds/create-manage-triggers

`github { owner/name/push }`는 기존 1세대 연결 방식이며, 2세대의 `repository_event_config`와 혼용하지 않는다. 2세대 connections와 Developer Connect 연결은 이번 프로젝트에서 발견되지 않았다.

## 2026-09-16 실제 적용 기록

사용자의 명시적 승인으로 plan 검토 후 apply를 실행했다. Nature DNS 2개와 Hosting 커스텀 도메인 2개를 추가하고 기존 서비스 CORS·표시 설정을 갱신했다. 삭제·교체된 리소스는 없다.

첫 apply에서 Cloud Build 저장소 연결 리전 불일치가 발견됐다. 성공한 GitHub 연결 감사로그의 `locations/global`을 확인해 트리거 리전을 global로 분리했고, 후속 apply로 앱·WAS 트리거 2개를 생성했다. Cloud Run과 Artifact Registry는 서울 리전을 유지한다.

두 새 도메인은 HOST_ACTIVE·OWNERSHIP_ACTIVE이며 SSL 인증서는 CERT_PROPAGATING 상태로 배포 중이다. 적용 후 plan에는 리소스 변경이 없고 인증서 진행에 따른 DNS 출력 메타데이터 갱신만 확인됐다. 애플리케이션 소스의 release 머지·태그 푸시·이미지 배포는 실행하지 않았다.

Hosting 사이트의 rewrite release가 비어 있어 기존/새 도메인 모두 404였음을 확인했다. 저장소의 hosting-release.sh로 두 기존 사이트를 각각 기존 Cloud Run에 연결했다(appAssociation NONE). 이후 실제 TLS 검증을 포함한 GET에서 nature.redhead.kr 및 nature-api.redhead.kr/health 모두 HTTP 200을 확인했다. 이 작업은 라우팅 설정 적용이며 앱/WAS 컨테이너 이미지는 교체하지 않았다.

주의: 현재 두 Cloud Run 서비스의 이미지는 `us-docker.pkg.dev/cloudrun/container/hello` 부트스트랩이다. 위 HTTP 200은 HTTPS·Hosting→Cloud Run 라우팅 성공만 의미하며 실제 Nature 웹/API 기능 검증은 아니다. 실제 사용에는 별도로 앱·WAS 소스 배포가 필요하다.
