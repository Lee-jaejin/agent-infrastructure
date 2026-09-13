#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# ralph-new-project-watch.sh — watches ntfy for new project creation requests
# Run in background: yarn ralph:new-project-watch
# Included automatically by: yarn ralph:start-projects
#
# iPhone publishes to topic "ralph-new-project":
#   Just name:        "my-webapp"
#   With description: "my-webapp: My awesome web application"
#
# On receive:
#   1. Parses name and optional description
#   2. Calls ralph-new-project.sh (creates directory, git, GitHub, registers in projects.json)
#   3. Starts ralph:task-watch for the new project so iPhone can send tasks immediately
#
# Requirements: NTFY_URL, RALPH_PROJECTS_BASE_DIR

set -euo pipefail

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

NTFY_URL="${NTFY_URL:-http://localhost:8095}"
NTFY_NEW_PROJECT_TOPIC="${NTFY_RALPH_NEW_PROJECT_TOPIC:-ralph-new-project}"
NTFY_RALPH_TOPIC="${NTFY_RALPH_TOPIC:-ralph}"

if ! curl -sf "${NTFY_URL}/v1/health" >/dev/null 2>&1; then
  echo "ralph:new-project-watch: ntfy not reachable at ${NTFY_URL}" >&2
  echo "  → Run: yarn ntfy:up" >&2
  exit 1
fi

if [ -z "${RALPH_PROJECTS_BASE_DIR:-}" ]; then
  echo "ralph:new-project-watch: RALPH_PROJECTS_BASE_DIR is not set — new-project feature disabled" >&2
  echo "  Set RALPH_PROJECTS_BASE_DIR=/path/to/projects in .env to enable" >&2
  exit 1
fi

echo "ralph:new-project-watch: listening on ${NTFY_URL}/${NTFY_NEW_PROJECT_TOPIC} ..."
echo "ralph:new-project-watch: message format: 'name' or 'name: description'"

while IFS= read -r line; do
  [ -z "${line}" ] && continue

  text=$(node -e "
    try {
      const m = JSON.parse(process.argv[1]);
      if (m.event === 'message' && m.message && m.message.trim()) {
        process.stdout.write(m.message.trim());
      }
    } catch(e) {}
  " -- "${line}" 2>/dev/null || true)

  [ -z "${text}" ] && continue

  echo "ralph:new-project-watch: received: ${text}"

  # Parse "name: description" or just "name"
  project_name=""
  project_desc=""
  if [[ "${text}" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*(.+)$ ]]; then
    project_name="${BASH_REMATCH[1]}"
    project_desc="${BASH_REMATCH[2]}"
  elif [[ "${text}" =~ ^([a-zA-Z0-9_-]+)$ ]]; then
    project_name="${text}"
  else
    echo "ralph:new-project-watch: invalid format '${text}' — use 'name' or 'name: description'" >&2
    (curl -sf \
      -H "Title: [Ralph] 프로젝트 생성 실패" \
      -d "잘못된 형식: ${text}
사용법: 프로젝트명  또는  프로젝트명: 설명" \
      "${NTFY_URL}/${NTFY_RALPH_TOPIC}" >/dev/null 2>&1 || true) &
    continue
  fi

  echo "ralph:new-project-watch: creating project '${project_name}'..."

  # Notify start
  (curl -sf \
    -H "Title: [${project_name}] 프로젝트 생성 중..." \
    -d "디렉토리 초기화 및 GitHub 연동 중입니다." \
    "${NTFY_URL}/${NTFY_RALPH_TOPIC}" >/dev/null 2>&1 || true) &

  args=("--name=${project_name}")
  [ -n "${project_desc}" ] && args+=("--description=${project_desc}")

  if bash "${SCRIPT_DIR}/ralph-new-project.sh" "${args[@]}"; then
    new_project_dir="${RALPH_PROJECTS_BASE_DIR}/${project_name}"
    echo "ralph:new-project-watch: starting task-watch for '${project_name}'..."
    bash "${SCRIPT_DIR}/ralph-task-watch.sh" \
      "--name=${project_name}" \
      "--project-dir=${new_project_dir}" &
  else
    echo "ralph:new-project-watch: creation failed for '${project_name}'" >&2
    (curl -sf \
      -H "Title: [${project_name}] 프로젝트 생성 실패" \
      -d "생성 중 오류가 발생했습니다. 로그를 확인하세요." \
      "${NTFY_URL}/${NTFY_RALPH_TOPIC}" >/dev/null 2>&1 || true) &
  fi

done < <(curl -sN "${NTFY_URL}/${NTFY_NEW_PROJECT_TOPIC}/json" 2>/dev/null)
