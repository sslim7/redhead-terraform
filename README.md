# redhead-terraform

`redhead.kr` 아래 GCP 인프라를 관리한다. 프로젝트 ID는 **`redhead-kr`**(번호 `514877625307`),
리전은 `asia-northeast3`, Artifact Registry 저장소는 `redhead`다.
이 저장소는 `main`만 사용한다. 앱·WAS 코드는 각각의 저장소에서 작업한다.

## 구성과 소유권

| 경로 | 관리 대상 | state (`gs://redhead-kr-tfstate`) |
|---|---|---|
| `shared/` | 프로젝트, API, state 버킷, Firebase 등록, DNS 존, 메일(PurelyMail) DNS, Artifact Registry | `shared` |
| `apps/nature/` | Cloud Run, 서비스 계정·권한, JWT 시크릿, Firestore·인덱스·규칙, Hosting 사이트·커스텀 도메인, 앱 DNS, Cloud Build 트리거 | `apps/jayeon` |
| `modules/` | 재사용 Terraform 모듈 | — |
| `hosting/`, `scripts/hosting-release.sh` | Hosting rewrite 설정과 릴리스 (Terraform 밖) | — |

- shared와 앱은 state를 분리한다. 앱은 shared state를 읽지 않고 프로젝트 ID·존 이름 등을
  `variables.auto.tfvars`로 받는다. apex와 메일 레코드는 shared만 소유한다.
- `apps/nature`의 backend prefix는 **`apps/jayeon` 그대로 둔다.** 폴더만 리브랜딩으로 옮겼으며
  prefix를 바꾸면 빈 state에서 기존 자원을 다시 만들려 한다.
- 결제 계정은 `shared/local.auto.tfvars`(커밋 제외)에 둔다. 예제는 `local.auto.tfvars.example`.

## 현재 상태 (2026-09-17 확인)

| 항목 | 상태 |
|---|---|
| shared 인프라 | apply 완료. state는 GCS(`shared`)로 이전 완료 |
| DNS | 가비아 → Cloud DNS(`ns-cloud-b1`~`b4.googledomains.com`) 위임 완료. 메일 MX·TXT·DKIM·DMARC 일치 확인 |
| 앱 인프라 | apply 완료. 적용 후 plan 변경 없음 |
| Cloud Build | 1세대 GitHub 연결(`global`): `sslim7/jayeon-app`, `sslim7/jayeon-was`, `sslim7/erd`. 트리거 `jayeon-app`, `jayeon-was` 활성 |
| 배포 | 태그 트리거로 실제 이미지 배포됨 — app `v0.1.2`, was `v0.1.0` |
| 도메인 | `https://nature.redhead.kr` 200, `https://nature-api.redhead.kr/health` 200(`ok`). 구 `jayeon.redhead.kr`, `jayeon-api.redhead.kr`도 호환용으로 유지 |
| 기본 VPC | Compute API 미사용 상태라 기본 VPC 없음 (`auto_create_network = true`는 영향 없음) |

남은 작업:

- WAS `/healthz` startup probe 활성화: `apps/nature/variables.auto.tfvars`에서
  `enable_was_startup_probe = true`로 바꾸고 plan 검토 후 apply한다. 현재는 기본 TCP probe다.
- `sslim7/erd`는 저장소 연결만 되어 있고 트리거·배포 구성은 없다.
- 구 `jayeon*` 도메인 제거는 구 클라이언트 사용 여부 확인 후 별도 작업으로 한다.

## app·was 연동 계약

| 항목 | 값 |
|---|---|
| 웹 도메인 / Hosting / Cloud Run | `nature.redhead.kr` / `redhead-jayeon-app` / `jayeon-app` |
| API 도메인 / Hosting / Cloud Run | `nature-api.redhead.kr` / `redhead-jayeon-api` / `jayeon-was` |
| 이미지 저장소 | `asia-northeast3-docker.pkg.dev/redhead-kr/redhead` |
| 배포 트리거 | release 브랜치 커밋에 `v*` 태그 push (트리거 위치 `global`, 빌드 `_REGION`은 서울) |
| 웹 빌드 변수 | `EXPO_PUBLIC_API_URL`, `EXPO_PUBLIC_ENV`, `EXPO_PUBLIC_WEBVIEW_URL` |
| WAS 런타임 | `GOOGLE_CLOUD_PROJECT`, `CORS_ALLOWED_ORIGINS`, `JWT_SECRET`, `ADMIN_JWT_SECRET` |
| 헬스 체크 | 외부 `/health`, 컨테이너 startup probe `/healthz` |
| 데이터 | Firestore `(default)`, 서버 SA만 접근, 클라이언트 규칙은 전면 거부 |

- CI는 이미지만 교체하고 서비스 설정은 Terraform이 소유한다(`lifecycle.ignore_changes`로 이미지 무시).
- 두 JWT 키는 서로 다른 Secret Manager 시크릿이며 값이 Terraform state에도 들어가므로
  state 버킷 접근 권한을 제한한다.
- `EXPO_PUBLIC_*`는 빌드 시 번들에 들어가므로 변경 시 이미지를 다시 빌드한다.
- Cloud Build 트리거 위치(`cicd.location = "global"`)와 Cloud Run 리전을 같은 값으로 묶지 않는다.
  1세대 연결이 `global`이라 서울 리전 트리거는 `Repository mapping does not exist`로 실패한다.

## Hosting rewrite

Hosting은 Cloud Run 앞에서 커스텀 도메인을 처리한다. rewrite는 Terraform이 지원하지 않아
`hosting/*.json`과 스크립트로 별도 관리한다. `appAssociation: NONE`을 유지해 앱의
`/.well-known/assetlinks.json`이 그대로 전달되게 한다. 아래 명령은 라이브 설정을 바꾼다.

```bash
scripts/hosting-release.sh redhead-jayeon-app
scripts/hosting-release.sh redhead-jayeon-api
```

사이트 생성 직후 rewrite release가 없으면 모든 도메인이 404를 반환한다.
참고: [Cloud Run 연동 지원 리전](https://firebase.google.com/docs/hosting/cloud-run),
[커스텀 도메인 소유권 상태](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/projects.sites.customDomains#ownershipstate).

## 작업 절차

plan·apply는 사용자가 로컬에서 직접 검토하고 실행한다. 삭제·교체가 plan에 보이면 진행하지 않는다.

```bash
cd shared        # 또는 apps/nature
terraform init
terraform plan
terraform apply
```

클라우드 변경 없는 검증:

```bash
terraform fmt -check -recursive
terraform -chdir=shared init -backend=false && terraform -chdir=shared validate
terraform -chdir=apps/nature init -backend=false && terraform -chdir=apps/nature validate
bash -n scripts/hosting-release.sh
```

메일 DNS 확인(각 GCP 네임서버에 직접 질의):

```bash
dig @ns-cloud-b1.googledomains.com redhead.kr MX
dig @ns-cloud-b1.googledomains.com redhead.kr TXT
dig @ns-cloud-b1.googledomains.com purelymail1._domainkey.redhead.kr CNAME
dig @ns-cloud-b1.googledomains.com _dmarc.redhead.kr CNAME
```

## 참고 문서

- [Nature 리브랜딩 이행 기록과 보존 식별자](docs/NATURE_MIGRATION.md) — Cloud Run·Hosting·SA·시크릿 이름은
  `jayeon` 식별자를 유지한다. 이름까지 바꾸려면 새 자원 생성·트래픽 전환·롤백 계획을 먼저 세운다.
