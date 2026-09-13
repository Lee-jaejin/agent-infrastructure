#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# ralph-new-project.sh — scaffold a new project and register it with Ralph
# Usage: bash scripts/ralph-new-project.sh --name=my-webapp [--description="My webapp"]
#
# What this does:
#   1. Creates RALPH_PROJECTS_BASE_DIR/name/
#   2. Initialises git + initial commit
#   3. Creates .agent/tasks.json and .agent/PROMPT.md from template
#   4. Creates a private GitHub repo and pushes (if GITHUB_OWNER is set and gh is authenticated)
#   5. Registers the project in infra/ralph/projects.json
#   6. Sends ntfy notification on completion
#
# Requirements:
#   RALPH_PROJECTS_BASE_DIR  — base directory for new projects (required)
#   GITHUB_OWNER             — GitHub user or org (optional; skip if not set)
#   gh CLI authenticated     — required only for GitHub step

set -euo pipefail

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${OPENCLAW_DIR}/.env" ]; then
  set -a && . "${OPENCLAW_DIR}/.env" && set +a
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PROJECT_NAME=""
PROJECT_DESC=""
for arg in "$@"; do
  case "$arg" in
    --name=*)        PROJECT_NAME="${arg#*=}" ;;
    --description=*) PROJECT_DESC="${arg#*=}" ;;
  esac
done

if [ -z "${PROJECT_NAME}" ]; then
  echo "ralph-new-project: --name=<project-name> is required" >&2
  exit 1
fi

# Validate: alphanumeric, hyphens, underscores only
if ! [[ "${PROJECT_NAME}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ralph-new-project: invalid name '${PROJECT_NAME}' (use letters, numbers, - or _)" >&2
  exit 1
fi

if [ -z "${RALPH_PROJECTS_BASE_DIR:-}" ]; then
  echo "ralph-new-project: RALPH_PROJECTS_BASE_DIR is not set" >&2
  echo "  Set it in .env: RALPH_PROJECTS_BASE_DIR=/path/to/projects" >&2
  exit 1
fi

NTFY_URL="${NTFY_URL:-http://localhost:8095}"
NTFY_RALPH_TOPIC="${NTFY_RALPH_TOPIC:-ralph}"
PROJECTS_FILE="${OPENCLAW_DIR}/infra/ralph/projects.json"
NEW_PROJECT_DIR="${RALPH_PROJECTS_BASE_DIR}/${PROJECT_NAME}"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [ -d "${NEW_PROJECT_DIR}" ]; then
  echo "ralph-new-project: directory already exists: ${NEW_PROJECT_DIR}" >&2
  exit 1
fi

# Check if name already registered
if [ -f "${PROJECTS_FILE}" ]; then
  if node -e "
    const p = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    if (p[process.argv[2]]) { process.exit(1); }
  " -- "${PROJECTS_FILE}" "${PROJECT_NAME}" 2>/dev/null; then
    : # not registered, continue
  else
    echo "ralph-new-project: project '${PROJECT_NAME}' already registered in projects.json" >&2
    exit 1
  fi
fi

echo "ralph-new-project: creating ${NEW_PROJECT_DIR} ..."

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
mkdir -p "${NEW_PROJECT_DIR}/.agent"

# Empty task list
echo "[]" > "${NEW_PROJECT_DIR}/.agent/tasks.json"

# PROMPT.md from template (strip only the file-level comment block at the top)
TEMPLATE="${OPENCLAW_DIR}/infra/ralph/.agent/PROMPT.project.example.md"
if [ -f "${TEMPLATE}" ]; then
  sed '/^# Project Context/,/^$/d' "${TEMPLATE}" > "${NEW_PROJECT_DIR}/.agent/PROMPT.md" || true
fi

# README
if [ -n "${PROJECT_DESC}" ]; then
  printf "# %s\n\n%s\n" "${PROJECT_NAME}" "${PROJECT_DESC}" > "${NEW_PROJECT_DIR}/README.md"
else
  printf "# %s\n" "${PROJECT_NAME}" > "${NEW_PROJECT_DIR}/README.md"
fi

# .gitignore
cat > "${NEW_PROJECT_DIR}/.gitignore" << 'GITIGNORE'
.env
.DS_Store
node_modules/
*.log
.agent/history/
.agent/logs/
.agent/.claude-session/
.agent/.ralph-waiting
GITIGNORE

# ---------------------------------------------------------------------------
# Git init
# ---------------------------------------------------------------------------
cd "${NEW_PROJECT_DIR}"
git init -b main
git add -A
git commit -m "chore: initial project setup"

echo "ralph-new-project: git initialised"

# ---------------------------------------------------------------------------
# GitHub (optional)
# ---------------------------------------------------------------------------
GITHUB_URL=""
if [ -n "${GITHUB_OWNER:-}" ] && command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "ralph-new-project: creating GitHub repo ${GITHUB_OWNER}/${PROJECT_NAME} ..."
    if GH_PROMPT_DISABLED=1 gh repo create "${GITHUB_OWNER}/${PROJECT_NAME}" \
        --private \
        --description "${PROJECT_DESC:-}" \
        --source=. \
        --remote=origin \
        --push 2>&1; then
      GITHUB_URL="https://github.com/${GITHUB_OWNER}/${PROJECT_NAME}"
      echo "ralph-new-project: GitHub → ${GITHUB_URL}"
    else
      echo "ralph-new-project: GitHub creation failed (continuing without remote)" >&2
    fi
  else
    echo "ralph-new-project: gh not authenticated — skipping GitHub step" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Register in projects.json
# ---------------------------------------------------------------------------
node -e "
  const fs = require('fs');
  const file = process.argv[1];
  const name = process.argv[2];
  const dir  = process.argv[3];
  let projects = {};
  try { projects = JSON.parse(fs.readFileSync(file, 'utf8')); } catch(e) {}
  projects[name] = dir;
  fs.writeFileSync(file, JSON.stringify(projects, null, 2) + '\n');
" -- "${PROJECTS_FILE}" "${PROJECT_NAME}" "${NEW_PROJECT_DIR}"

echo "ralph-new-project: registered in projects.json"

# ---------------------------------------------------------------------------
# ntfy notification
# ---------------------------------------------------------------------------
NTFY_BODY="${NEW_PROJECT_DIR}"
[ -n "${GITHUB_URL}" ] && NTFY_BODY="${NTFY_BODY}
${GITHUB_URL}"
NTFY_BODY="${NTFY_BODY}
Tasks: ntfy topic ralph-task-${PROJECT_NAME}"

(curl -sf \
  -H "Title: [${PROJECT_NAME}] 프로젝트 생성 완료" \
  -d "${NTFY_BODY}" \
  "${NTFY_URL}/${NTFY_RALPH_TOPIC}" >/dev/null 2>&1 || true) &

echo ""
echo "ralph-new-project: ✓ ${PROJECT_NAME} is ready"
echo "  Dir:    ${NEW_PROJECT_DIR}"
[ -n "${GITHUB_URL}" ] && echo "  GitHub: ${GITHUB_URL}"
echo "  Tasks:  ntfy topic ralph-task-${PROJECT_NAME}"
