#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# ralph-start-projects.sh — start ralph watchers for all projects in projects.json
# Usage: yarn ralph:start-projects
#
# Reads infra/ralph/projects.json and starts:
#   - one ralph:task-watch per project (listens on ralph-task-{name})
#   - one ralph:watch (listens on ralph-reply, handles all projects)
#
# iPhone sends tasks to: ralph-task-{name}  (one topic per project)
# iPhone replies to:     ralph-reply         (single topic, prefix: "name: answer")
# iPhone reads from:     ralph               (single topic, all project notifications)

set -euo pipefail

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECTS_FILE="${PROJECT_DIR}/infra/ralph/projects.json"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

if [ ! -f "${PROJECTS_FILE}" ]; then
  echo "ralph:start-projects: ${PROJECTS_FILE} not found" >&2
  echo "  Create it with your project aliases:" >&2
  echo '  {"webapp": "/path/to/webapp", "api": "/path/to/api"}' >&2
  exit 1
fi

# Cleanup all child processes on exit
trap 'echo "ralph:start-projects: stopping all watchers..."; kill 0' EXIT INT TERM

# Start single reply-watch (handles all projects)
echo "Starting ralph:watch (reply handler for all projects)..."
bash "${SCRIPT_DIR}/ralph-imsg-watch.sh" &

# Start new-project-watch (creates projects on demand from iPhone)
if [ -n "${RALPH_PROJECTS_BASE_DIR:-}" ]; then
  echo "Starting ralph:new-project-watch (creates projects on demand)..."
  bash "${SCRIPT_DIR}/ralph-new-project-watch.sh" &
fi

# Start one task-watch per project
while IFS=$'\t' read -r name dir; do
  echo "Starting ralph:task-watch[${name}] → ${dir}"
  bash "${SCRIPT_DIR}/ralph-task-watch.sh" "--name=${name}" "--project-dir=${dir}" &
done < <(node -e "
  const p = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
  Object.entries(p).forEach(([k, v]) => process.stdout.write(k + '\t' + v + '\n'));
" -- "${PROJECTS_FILE}")

echo ""
echo "All watchers running. iPhone topics:"
node -e "
  const p = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
  Object.keys(p).forEach(name => {
    console.log('  send task  → ralph-task-' + name);
  });
  console.log('  reply      → ralph-reply  (prefix: \"name: answer\")');
  console.log('  read alerts → ralph');
" -- "${PROJECTS_FILE}"
[ -n "${RALPH_PROJECTS_BASE_DIR:-}" ] && \
  echo "  create project → ralph-new-project  (\"name\" or \"name: description\")"
echo ""
echo "Press Ctrl+C to stop all."

wait
