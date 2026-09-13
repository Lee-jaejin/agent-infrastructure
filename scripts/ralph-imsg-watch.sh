#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# ralph-imsg-watch.sh — watches ntfy for ralph replies and resumes the loop
# Run in background: yarn ralph:watch  (or via yarn ralph:start-projects)
#
# Single-project flow:
#   ralph hits DECIDE/BLOCKED → POSTs to ntfy $NTFY_RALPH_TOPIC
#   user replies → publishes to $NTFY_RALPH_REPLY_TOPIC
#   this script detects reply → writes .agent/HUMAN_REPLY.md → restarts ralph
#
# Multi-project flow (infra/ralph/projects.json configured):
#   reply format: "project-name: your answer"
#   this script parses the prefix → finds the waiting project → resumes it
#   if no prefix given, auto-detects which project is waiting

set -euo pipefail

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECTS_FILE="${PROJECT_DIR}/infra/ralph/projects.json"

if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a && . "${PROJECT_DIR}/.env" && set +a
fi

NTFY_URL="${NTFY_URL:-http://localhost:8095}"
NTFY_REPLY_TOPIC="${NTFY_RALPH_REPLY_TOPIC:-ralph-reply}"
RALPH_PROJECT_DIR="${RALPH_PROJECT_DIR:-}"

if ! curl -sf "${NTFY_URL}/v1/health" >/dev/null 2>&1; then
  echo "ralph:watch: ntfy not reachable at ${NTFY_URL}" >&2
  echo "  → Run: yarn ntfy:up" >&2
  exit 1
fi

echo "ralph:watch: listening on ${NTFY_URL}/${NTFY_REPLY_TOPIC} ..."
[ -f "${PROJECTS_FILE}" ] && echo "ralph:watch: multi-project mode (${PROJECTS_FILE})"
[ -n "${RALPH_PROJECT_DIR}" ] && echo "ralph:watch: single-project dir: ${RALPH_PROJECT_DIR}"

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

  echo "ralph:watch: reply received: ${text}"

  # Resolve project dir + actual reply text via node (handles both single and multi-project)
  resolved=$(node -e "
    const fs = require('fs');
    const text = process.argv[1];
    const projectsFile = process.argv[2];
    const singleDir = process.argv[3];

    let projects = {};
    try { projects = JSON.parse(fs.readFileSync(projectsFile, 'utf8')); } catch(e) {}

    // Parse 'project-name: reply text' format
    const prefixMatch = text.match(/^([a-zA-Z0-9_-]+): (.+)$/s);
    if (prefixMatch) {
      const name = prefixMatch[1];
      const reply = prefixMatch[2].trim();
      if (projects[name]) {
        const waiting = projects[name] + '/.agent/.ralph-waiting';
        if (fs.existsSync(waiting)) {
          process.stdout.write(projects[name] + '\t' + reply);
          process.exit(0);
        }
      }
    }

    // No prefix or prefix not matched: find any waiting project
    for (const [, dir] of Object.entries(projects)) {
      if (fs.existsSync(dir + '/.agent/.ralph-waiting')) {
        process.stdout.write(dir + '\t' + text);
        process.exit(0);
      }
    }

    // Single-project fallback
    if (singleDir && fs.existsSync(singleDir + '/.agent/.ralph-waiting')) {
      process.stdout.write(singleDir + '\t' + text);
    }
  " -- "${text}" "${PROJECTS_FILE}" "${RALPH_PROJECT_DIR}" 2>/dev/null || true)

  if [ -z "${resolved}" ]; then
    echo "ralph:watch: not waiting, skipping"
    continue
  fi

  project_dir="${resolved%%$'\t'*}"
  actual_reply="${resolved#*$'\t'}"

  printf '# Human Reply\n\n%s\n' "${actual_reply}" > "${project_dir}/.agent/HUMAN_REPLY.md"
  rm -f "${project_dir}/.agent/.ralph-waiting"

  echo "ralph:watch: resuming ralph for ${project_dir}..."
  (cd "${PROJECT_DIR}" && yarn ralph -- "--project-dir=${project_dir}") || true

done < <(curl -sN "${NTFY_URL}/${NTFY_REPLY_TOPIC}/json" 2>/dev/null)
