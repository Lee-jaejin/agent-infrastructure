# 커밋 계획 (주제별)

Conventional Commits + COMMITS.md 기준. 아래 순서대로 실행하면 됨.

---

## 1. infra(openclaw): workspace volume, gateway rate limit, OpenClaw 2026.2.15

**주제:** OpenClaw 컨테이너·설정 — 워크스페이스 마운트, 게이트웨이 제한, 버전

```bash
git add \
  config/openclaw.json \
  docker-compose.yml \
  infra/openclaw/Dockerfile \
  .env.example \
  .gitignore
git commit -m "infra(openclaw): workspace volume, gateway rate limit, skipBootstrap, 2026.2.15

- config: skipBootstrap, auth.rateLimit (maxAttempts, windowMs, lockoutMs, exemptLoopback)
- compose: openclaw-data volume, workspace mount (SOUL/AGENTS), drop openclaw-sessions
- Dockerfile: OPENCLAW_VERSION 2026.2.15, PNPM_HOME, systemd package
- .env.example: OPENCLAW_VERSION 2026.2.15
- .gitignore: workspace/, /workspace-templates/ (root only; config/workspace-templates/ committed)"
```

---

## 2. config: add workspace templates (AGENTS-chat-only, SOUL, USER)

**주제:** 워크스페이스 최소 템플릿 — openclaw-setup-order 4단계에서 복사용

```bash
git add config/workspace-templates/
git commit -m "config: add workspace templates for SOUL.md, AGENTS.md, USER.md

- AGENTS-chat-only.md: chat-only instructions (no file-read loop)
- SOUL.md, USER.md: minimal placeholders
- Used by docs/openclaw-setup-order step 4"
```

---

## 3. docs(website): troubleshooting SOUL/AGENTS reply loop (en/ko)

**주제:** 문서 사이트 — 트러블슈팅 항목 추가 (iMessage에서 SOUL/AGENTS 반복 응답)

```bash
git add \
  website/docs/troubleshooting.md \
  website/i18n/ko/docusaurus-plugin-content-docs/current/troubleshooting.md
git commit -m "docs(website): add troubleshooting for SOUL/AGENTS reply loop (en/ko)

- Symptom: model keeps saying read SOUL.md/AGENTS.md instead of answering
- Cause: entries plugin / agent instructions without file tools
- Mitigations: disable entries for imessage, adjust system prompt, try different model"
```

---

## 4. docs: add design and ops docs, align with project, README link

**주제:** 설계·운영 문서 추가, 프로젝트 구조 반영, README 링크

```bash
git add \
  docs/TODO.md \
  docs/architecture.md \
  docs/backup-recovery.md \
  docs/commit-plan.md \
  docs/doc-vs-reality.md \
  docs/mobile-support.md \
  docs/monitoring.md \
  docs/multi-llm-strategy.md \
  docs/offline-mode.md \
  docs/openclaw-setup-order.md \
  docs/openclaw-workspace-setup.md \
  docs/update-policy.md \
  README.md
git commit -m "docs: add architecture, backup, monitoring, update-policy, workspace, multi-llm, offline, mobile, TODO

- architecture, openclaw-setup-order, openclaw-workspace-setup (openclaw-data + workspace)
- backup-recovery, monitoring, update-policy; backup script vs workspace note
- multi-llm-strategy, offline-mode, mobile-support, TODO
- doc-vs-reality: doc vs project checklist; commit-plan: topic-based commits
- README: add Update Policy doc link"
```

---

## 한 번에 실행 (복사용)

```bash
cd /Users/jaejin/Study/ai/agent-infrastructure

git add config/openclaw.json docker-compose.yml infra/openclaw/Dockerfile .env.example .gitignore
git commit -m "infra(openclaw): workspace volume, gateway rate limit, skipBootstrap, 2026.2.15

- config: skipBootstrap, auth.rateLimit (maxAttempts, windowMs, lockoutMs, exemptLoopback)
- compose: openclaw-data volume, workspace mount (SOUL/AGENTS), drop openclaw-sessions
- Dockerfile: OPENCLAW_VERSION 2026.2.15, PNPM_HOME, systemd package
- .env.example: OPENCLAW_VERSION 2026.2.15
- .gitignore: workspace/, /workspace-templates/ (root only; config/workspace-templates/ committed)"

git add config/workspace-templates/
git commit -m "config: add workspace templates for SOUL.md, AGENTS.md, USER.md

- AGENTS-chat-only.md: chat-only instructions (no file-read loop)
- SOUL.md, USER.md: minimal placeholders
- Used by docs/openclaw-setup-order step 4"

git add website/docs/troubleshooting.md website/i18n/ko/docusaurus-plugin-content-docs/current/troubleshooting.md
git commit -m "docs(website): add troubleshooting for SOUL/AGENTS reply loop (en/ko)

- Symptom: model keeps saying read SOUL.md/AGENTS.md instead of answering
- Cause: entries plugin / agent instructions without file tools
- Mitigations: disable entries for imessage, adjust system prompt, try different model"

git add docs/TODO.md docs/architecture.md docs/backup-recovery.md docs/commit-plan.md docs/doc-vs-reality.md docs/mobile-support.md docs/monitoring.md docs/multi-llm-strategy.md docs/offline-mode.md docs/openclaw-setup-order.md docs/openclaw-workspace-setup.md docs/update-policy.md README.md
git commit -m "docs: add architecture, backup, monitoring, update-policy, workspace, multi-llm, offline, mobile, TODO

- architecture, openclaw-setup-order, openclaw-workspace-setup (openclaw-data + workspace)
- backup-recovery, monitoring, update-policy; backup script vs workspace note
- multi-llm-strategy, offline-mode, mobile-support, TODO
- doc-vs-reality: doc vs project checklist; commit-plan: topic-based commits
- README: add Update Policy doc link"
```

---

커밋 전 Sensitive Data 점검 권장:

```bash
git diff --cached | grep -iE '(token|key|password|secret)=' | grep -v '\${'
git diff --cached | grep -iE '(jaejin|MacBook|192\.168|100\.64)'
```

(출력 없으면 통과)
