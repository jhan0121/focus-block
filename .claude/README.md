<p align="center">
  <img src="./assets/claude-code-icon.svg" width="96" height="96" alt="Claude Code icon">
</p>

# Nekoi Claude Code Rules Pack

Claude Code 프로젝트에 적용할 수 있는 범용 규칙, 명령, 에이전트, 훅 패키지입니다.
특정 언어, 프레임워크, 폴더 구조, API, DB, 개인 경로를 전제하지 않고 실제 파일을 읽어 현재 프로젝트 구조를 확인하도록 구성되어 있습니다.

## 포함 항목

- `agents/`: 작업 유형별 검증 에이전트 정의
- `commands/`: 프로젝트 작업, 맥락 형성, 편집 가드, 서비스 파이프라인, 사고 규칙 명령
- `rules/`: 사고 규칙, 편집 이중검증, 프로젝트 맥락 형성 규칙
- `hooks/`: Claude Code 훅 스크립트
- `config/nekoi-claude.ini`: 배포 대상 프로젝트별 경로와 설정값 자리표시자
- `assets/claude-code-icon.svg`: README에서 직접 참조하는 로컬 아이콘
- `settings.json`: 기본 Claude Code 설정
- `settings.local.json`: 개인 권한을 넣지 않은 빈 로컬 설정 예시

## 적용 방식

이 저장소를 프로젝트의 `.claude` 디렉터리로 사용하거나, 기존 `.claude` 디렉터리에 필요한 파일을 병합해서 사용할 수 있습니다.

훅 위치가 기본값과 다르면 환경변수로 지정합니다.

```bash
export NEKOI_CLAUDE_HOOKS_DIR="/path/to/this-package/hooks"
export NEKOI_CLAUDE_CONFIG="/path/to/this-package/config/nekoi-claude.ini"
```

`config/nekoi-claude.ini`의 자리표시자는 배포받은 프로젝트에 맞게 수정합니다.

```ini
[project]
frontend_dir=<FRONTEND_DIR>
backend_dir=<BACKEND_DIR>
service_dir=<SERVICE_DIR>
primary_env_file=<PRIMARY_ENV_FILE>
service_env_file=<SERVICE_ENV_FILE>

[service]
public_api_base_url=<PUBLIC_API_BASE_URL>
secondary_api_base_url=<SECONDARY_API_BASE_URL>
service_key_name=<SERVICE_KEY_ENV_NAME>

[database]
server_database_name=<SERVER_DATABASE_NAME>
service_database_name=<SERVICE_DATABASE_NAME>
```



## 제작자

- Nekoi
- 이메일: <nekoi@everlib.pro>
- 웹사이트: <https://www.everlib.pro/>

## 라이선스

저작권 정보 없음.

이 패키지는 자유롭게 사용, 수정, 복사, 재배포, 상업적 활용이 가능합니다.
배포할 때는 <nekoi@everlib.pro> 로 사용 또는 배포 사실만 알려주세요.

알림 이메일에는 프로젝트명, 배포 위치, 사용 목적 중 가능한 정보만 적으면 됩니다.
별도의 저작권 고지, 라이선스 전문 동봉, 소스 공개 의무는 없습니다.
