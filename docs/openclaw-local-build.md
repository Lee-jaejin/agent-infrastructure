# OpenClaw 로컬 브랜치로 이미지 빌드

npm에 배포되기 전(예: PR 상태인) openclaw 레포의 브랜치를 이 프로젝트에서 테스트하려면, 해당 브랜치에서 패키지를 pack한 뒤 로컬 tarball로 이미지를 빌드하면 된다.

## 로컬 수정이 반영되지 않을 때

로컬 브랜치로 빌드했는데도 동작이 npm 버전과 같다면, **compose가 기본 Dockerfile로 다시 빌드해 이미지를 덮어썼을 가능성**이 크다. `podman compose up -d --build openclaw`는 기본 Dockerfile을 사용해 npm의 `openclaw@2026.2.15`를 설치하므로, 그 전에 수동으로 만든 `openclaw:local`(로컬 tgz 기반)이 교체된다. 아래처럼 **override 파일**을 써서 로컬 tarball 빌드가 유지되도록 하자.

## 전제

- openclaw 레포가 로컬에 있음 (예: `~/Study/ai/openclaw`)
- 테스트할 브랜치로 체크아웃된 상태 (예: `fix/imessage-bot-self-response`)

## 절차

### 1. openclaw 레포에서 패키지 생성

```bash
cd /path/to/openclaw
git checkout fix/imessage-bot-self-response   # 사용할 브랜치
pnpm install   # 의존 미설치 시 pack 시 빌드 실패함
pnpm pack
```

`pnpm pack`은 `prepack` 스크립트(build + ui:build) 실행 후 `openclaw-<version>.tgz`를 프로젝트 루트에 생성한다.

### 2. tarball을 agent-infrastructure로 복사

```bash
cp /path/to/openclaw/openclaw-*.tgz /path/to/agent-infrastructure/infra/openclaw/
```

### 3. 로컬 이미지 빌드 및 실행 (compose override 사용)

**중요:** `podman compose up -d --build openclaw`만 쓰면 기본 Dockerfile이 사용되어 **npm 버전(2026.2.15)**으로 다시 빌드되고, 로컬 브랜치 수정이 덮어씌워진다. 로컬 tarball을 쓰는 동안은 **반드시** override 파일을 지정한다.

```bash
cd /path/to/agent-infrastructure
podman compose -f docker-compose.yml -f docker-compose.openclaw-local.yml up -d --build openclaw
```

override(`docker-compose.openclaw-local.yml`)가 openclaw 서비스의 빌드를 `Dockerfile.local`로 바꾼다. `infra/openclaw/openclaw-*.tgz`가 있어야 빌드가 성공한다.

수동 빌드만 할 경우:

```bash
podman build -f infra/openclaw/Dockerfile.local -t openclaw:local ./infra/openclaw
podman compose up -d openclaw
```

이 경우 **`compose up --build`를 쓰지 말 것.** 쓰면 기본 Dockerfile로 다시 빌드되어 npm 버전으로 교체된다.

### 4. npm 버전으로 되돌리기

로컬 테스트 후 다시 npm 배포 버전을 쓰려면 override 없이:

```bash
podman compose up -d --build openclaw
```

또는:

```bash
podman build -t openclaw:local ./infra/openclaw
podman compose up -d openclaw
```

`infra/openclaw/openclaw-*.tgz`는 `.gitignore`에 있으므로 커밋되지 않는다.

## 요약

| 목적               | 명령 |
|--------------------|------|
| 로컬 브랜치 테스트 | `podman compose -f docker-compose.yml -f docker-compose.openclaw-local.yml up -d --build openclaw` (tgz 먼저 복사) |
| npm 버전 (기본)    | `podman compose up -d --build openclaw` |
