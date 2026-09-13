#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# ralph-task-watch.sh — watches a ntfy topic for new tasks and starts ralph
# Run in background: yarn ralph:task-watch
#
# Single-project mode (RALPH_PROJECT_DIR in .env):
#   yarn ralph:task-watch &
#
# Multi-project mode (infra/ralph/projects.json):
#   bash scripts/ralph-task-watch.sh --name=webapp --project-dir=/path/to/webapp
#   (use yarn ralph:start-projects to start all at once)
#
# Flow:
#   user publishes task description to ralph-task-{name} ntfy topic
#   this script detects it → appends task to tasks.json → starts ralph
#   ralph hits BLOCKED/DECIDE → ralph:watch handles the reply flow
#
# Requirements: NTFY_URL must be reachable; RALPH_PROJECT_DIR set (single-project mode)

set -euo pipefail

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

# Parse --name= and --project-dir= (multi-project mode)
PROJECT_NAME=""
RALPH_PROJECT_DIR="${RALPH_PROJECT_DIR:-}"
for arg in "$@"; do
  case "$arg" in
    --name=*)         PROJECT_NAME="${arg#*=}" ;;
    --project-dir=*)  RALPH_PROJECT_DIR="${arg#*=}" ;;
  esac
done

if [ -z "${RALPH_PROJECT_DIR}" ]; then
  echo "ralph:task-watch: RALPH_PROJECT_DIR is not set" >&2
  echo "  → Set RALPH_PROJECT_DIR=/path/to/your/project in .env" >&2
  exit 1
fi

# Derive project name from directory if not given
if [ -z "${PROJECT_NAME}" ]; then
  PROJECT_NAME=$(basename "${RALPH_PROJECT_DIR}")
fi

NTFY_URL="${NTFY_URL:-http://localhost:8095}"
# Multi-project: per-project topic. Single-project: use NTFY_RALPH_TASK_TOPIC from env.
if [ $# -gt 0 ]; then
  NTFY_TASK_TOPIC="ralph-task-${PROJECT_NAME}"
else
  NTFY_TASK_TOPIC="${NTFY_RALPH_TASK_TOPIC:-ralph-task}"
fi

TASKS_FILE="${RALPH_PROJECT_DIR}/.agent/tasks.json"

if ! curl -sf "${NTFY_URL}/v1/health" >/dev/null 2>&1; then
  echo "ralph:task-watch[${PROJECT_NAME}]: ntfy not reachable at ${NTFY_URL}" >&2
  echo "  → Run: yarn ntfy:up" >&2
  exit 1
fi

echo "ralph:task-watch[${PROJECT_NAME}]: listening on ${NTFY_URL}/${NTFY_TASK_TOPIC} ..."
echo "ralph:task-watch[${PROJECT_NAME}]: project dir: ${RALPH_PROJECT_DIR}"

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

  echo "ralph:task-watch[${PROJECT_NAME}]: new task: ${text}"

  # Ensure tasks.json exists
  if [ ! -f "${TASKS_FILE}" ]; then
    mkdir -p "$(dirname "${TASKS_FILE}")"
    echo "[]" > "${TASKS_FILE}"
  fi

  # Append task entry
  task_id="TASK-$(date +%s)"
  node -e "
    const fs = require('fs');
    const [file, id, desc] = process.argv.slice(1);
    const tasks = JSON.parse(fs.readFileSync(file, 'utf8'));
    const maxPriority = tasks.reduce((m, t) => Math.max(m, t.priority || 0), 0);
    tasks.push({
      id,
      title: desc.slice(0, 80),
      description: desc,
      priority: maxPriority + 1,
      status: 'pending'
    });
    fs.writeFileSync(file, JSON.stringify(tasks, null, 2));
    console.log('Task added:', id);
  " -- "${TASKS_FILE}" "${task_id}" "${text}"

  # Check if ralph is already running for this project
  if pgrep -f "ralph\.sh.*project-dir=${RALPH_PROJECT_DIR}" >/dev/null 2>&1; then
    echo "ralph:task-watch[${PROJECT_NAME}]: ralph already running, task queued"
    (curl -sf \
      -H "Title: [${PROJECT_NAME}] Ralph: task queued" \
      -d "Task queued: ${text:0:100}" \
      "${NTFY_URL}/${NTFY_RALPH_TOPIC:-ralph}" >/dev/null 2>&1 || true) &
  else
    echo "ralph:task-watch[${PROJECT_NAME}]: starting ralph..."
    (curl -sf \
      -H "Title: [${PROJECT_NAME}] Ralph: starting" \
      -d "Starting task: ${text:0:100}" \
      "${NTFY_URL}/${NTFY_RALPH_TOPIC:-ralph}" >/dev/null 2>&1 || true) &
    (cd "${PROJECT_DIR}" && yarn ralph -- "--project-dir=${RALPH_PROJECT_DIR}") || true
  fi
done < <(curl -sN "${NTFY_URL}/${NTFY_TASK_TOPIC}/json" 2>/dev/null)
