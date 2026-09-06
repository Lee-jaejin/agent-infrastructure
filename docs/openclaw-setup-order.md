# OpenClaw 설정 순서

아래 순서대로만 하면 OpenClaw가 기동하고, (선택) iMessage까지 연동할 수 있습니다.

---

## 1. 사전 확인

- **Podman** 설치됨 (`podman --version`)
- **Ollama** 호스트에서 실행 중 (`ollama serve` 또는 `brew services start ollama`)
- 이 레포 클론 후 프로젝트 루트에서 진행

```bash
cd /path/to/agent-infrastructure
```

---

## 2. .env 만들기

`.env.example`을 복사한 뒤 필요한 값만 채웁니다.

```bash
cp .env.example .env
```

**반드시 바꿀 것:**

| 변수 | 설명 | 예시 |
|------|------|------|
| `OPENCLAW_GATEWAY_TOKEN` | 게이트웨이 인증 토큰 (아무 랜덤 문자열) | `my-secret-token-abc123` |

**Ollama가 호스트에 있을 때 (기본):**

- `OLLAMA_HOST=http://host.containers.internal:11434`
- `OLLAMA_BASE_URL=http://host.containers.internal:11434/v1`  
이미 `.env.example`에 있으면 그대로 두면 됩니다.

**iMessage 쓸 때만:** `IMSG_SSH_USER`에 macOS 사용자명 넣기 (3단계에서 SSH·설정까지 한 뒤).

`.env`는 커밋하지 마세요.

---

## 3. Ollama 확인

컨테이너에서 Ollama에 접속할 수 있어야 합니다. OpenClaw를 띄운 **뒤**에 해도 되지만, 미리 확인하려면:

```bash
# 호스트에서 Ollama 응답 확인
curl -s http://localhost:11434/api/tags | head -20
```

설정한 기본 모델(`config/openclaw.json`의 `agents.defaults.model.primary`)이 로드 가능한지 확인합니다. 예: `ollama/gpt-oss:20b` → `ollama pull gpt-oss:20b` (필요 시).

---

## 4. 워크스페이스 준비 (SOUL.md, AGENTS.md)

OpenClaw가 "SOUL.md를 읽어야 한다"만 반복하지 않도록, 워크스페이스에 최소 파일을 넣습니다.

```bash
mkdir -p workspace
cp config/workspace-templates/AGENTS-chat-only.md workspace/AGENTS.md
cp config/workspace-templates/SOUL.md workspace/SOUL.md
cp config/workspace-templates/USER.md workspace/USER.md
```

자세한 설명: [openclaw-workspace-setup.md](./openclaw-workspace-setup.md)

---

## 5. OpenClaw 빌드 및 기동

의존 서비스(egress-proxy)까지 함께 띄웁니다.

```bash
podman compose up -d openclaw
```

최초 빌드면 이미지 빌드에 시간이 걸릴 수 있습니다.  
OpenClaw만 다시 빌드하려면:

```bash
podman compose build openclaw
podman compose up -d openclaw
```

---

## 6. 동작 확인

```bash
# 컨테이너 실행 여부
podman ps | grep openclaw

# 게이트웨이 헬스 (로컬)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/health
# 200 이면 정상

# OpenClaw 자체 점검
podman exec openclaw openclaw doctor
```

`openclaw doctor`에서 경고가 나와도, Ollama 연결과 gateway 포트가 정상이면 기본 채팅은 가능합니다.

---

## 7. (선택) iMessage 연동

iMessage로 질문받으려면 다음이 필요합니다.

1. **호스트 macOS**에서 `imsg`(또는 iMessage CLI) 설치
2. **SSH 키** 생성 후 `~/.ssh/authorized_keys`에 강제 명령 등록
3. **docker-compose**에 SSH 키·imsg 스크립트 마운트 (이미 되어 있을 수 있음)
4. **config/openclaw.json**에 `channels.imessage` 및 `plugins.entries.imessage` 설정
5. **.env**에 `IMSG_SSH_USER=<macOS사용자명>` 설정
6. **재시작** 후 페어링: `podman exec openclaw openclaw pairing list imessage` / `openclaw pairing approve imessage <코드>`

자세한 단계와 보안 설정: [website/docs/openclaw-onboard.md](../website/docs/openclaw-onboard.md) (또는 `website/i18n/ko/...` 한글판).

---

## 8. 설정 변경 시

- **config/openclaw.json** 수정 후: `podman restart openclaw` (볼륨이 읽기 전용이므로 호스트에서만 편집)
- **.env** 수정 후: `podman compose up -d openclaw` (재생성)
- **workspace/** 안 AGENTS.md, SOUL.md, USER.md 수정 후: 재시작 없이 다음 대화부터 반영됨 (세션에 따라 다를 수 있음)

---

## 요약 체크리스트

- [ ] 1. Podman, Ollama 확인
- [ ] 2. `.env` 생성 후 `OPENCLAW_GATEWAY_TOKEN` 설정
- [ ] 3. Ollama 응답 및 모델 확인
- [ ] 4. `workspace/` 생성 후 AGENTS.md, SOUL.md, USER.md 복사
- [ ] 5. `podman compose up -d openclaw`
- [ ] 6. `curl http://127.0.0.1:18789/health` → 200, `openclaw doctor` 확인
- [ ] 7. (선택) iMessage 설정 및 페어링

여기까지 완료하면 OpenClaw는 로컬에서 동작하며, Tailscale로 같은 테일넷에 있는 기기에서 `http://<openclaw-tailscale-ip>:18789` 로 접근할 수 있습니다 (게이트웨이 `bind: tailnet` 인 경우).
