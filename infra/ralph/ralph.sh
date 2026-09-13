#!/bin/bash
# DEPRECATED (#9)
# 자율형 에이전트 진입점은 raven 텔레그램 게이트웨이로 이전
# 이 경로는 유지보수 대상 아님. 배경은 README 의 "자율형 에이전트" 참고
# Ralph - Long-running AI agent loop (Podman + Claude Code subscription)
# Forked from PageAI-Pro/ralph-loop, adapted for Podman isolation + model-router
#
# Usage: ./ralph.sh [--help] [--once] [--max-iterations N] [N] [--project-dir PATH]
#
# Requirements:
#   - podman (rootless)
#   - node >= 22
#   - ~/.claude/ with valid claude.ai subscription login
#   - .agent/tasks.json and .agent/PROMPT.md in project dir

set -e

echo "[deprecated] 이 경로는 raven 텔레그램 게이트웨이로 대체됐습니다. README 참고" >&2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default project dir is cwd; can override with --project-dir
PROJECT_DIR="$(pwd)"

# Parse --project-dir early (before sourcing lib which calls cd)
for arg in "$@"; do
  if [[ "$arg" == --project-dir=* ]]; then
    PROJECT_DIR="${arg#*=}"
  fi
done

cd "$PROJECT_DIR"

PROJECT_NAME=$(basename "$PROJECT_DIR")

# Load .env if present (provides NTFY_URL, RALPH_IMAGE, etc.)
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a && . "$PROJECT_DIR/.env" && set +a
fi

PRD_FILE="$PROJECT_DIR/.agent/prd/PRD.md"
PROGRESS_FILE="$PROJECT_DIR/.agent/logs/LOG.md"
HISTORY_DIR="$PROJECT_DIR/.agent/history"

source "$SCRIPT_DIR/scripts/lib/constants.sh"
source "$SCRIPT_DIR/scripts/lib/logging.sh"
source "$SCRIPT_DIR/scripts/lib/timing.sh"
source "$SCRIPT_DIR/scripts/lib/terminal.sh"
source "$SCRIPT_DIR/scripts/lib/spinner.sh"
source "$SCRIPT_DIR/scripts/lib/preview.sh"
source "$SCRIPT_DIR/scripts/lib/output.sh"
source "$SCRIPT_DIR/scripts/lib/cleanup.sh"
source "$SCRIPT_DIR/scripts/lib/promise.sh"
source "$SCRIPT_DIR/scripts/lib/notify.sh"
source "$SCRIPT_DIR/scripts/lib/display.sh"
source "$SCRIPT_DIR/scripts/lib/args.sh"
source "$SCRIPT_DIR/scripts/lib/preflight.sh"

# Podman image name
RALPH_IMAGE="${RALPH_IMAGE:-ralph-claude}"

# Timing
START_TIME=$(date +%s)
ITERATION_TIMES=()
TOTAL_ITERATION_TIME=0
PREV_ITERATION_TIME=0

# Session ID
SESSION_ID=$(date +%Y%m%d-%H%M%S)

# Temporary files
STEP_FILE=$(mktemp)
PREVIEW_LINE_FILE=$(mktemp)

# Background process tracking
AGENT_PID=""
OUTPUT_FILE=""
FULL_OUTPUT_FILE=""

# Persistent Claude session dir (per project, survives between ralph runs)
# Contains only what Claude Code needs: credentials + settings + session state
# Does NOT copy host history, projects, todos, debug, telemetry, etc.
CLAUDE_SESSION_DIR="$PROJECT_DIR/.agent/.claude-session"
if [ ! -d "$CLAUDE_SESSION_DIR" ]; then
  mkdir -p "$CLAUDE_SESSION_DIR"
  # Settings (optional, one-time)
  [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$CLAUDE_SESSION_DIR/"
  # Session state (for continuity, one-time)
  [ -d "$HOME/.claude/session-env" ] && cp -r "$HOME/.claude/session-env" "$CLAUDE_SESSION_DIR/"
  [ -d "$HOME/.claude/sessions" ]    && cp -r "$HOME/.claude/sessions"    "$CLAUDE_SESSION_DIR/"
  # Ensure it stays out of git
  if [ -f "$PROJECT_DIR/.gitignore" ] && ! grep -q '\.claude-session' "$PROJECT_DIR/.gitignore"; then
    echo '.agent/.claude-session/' >> "$PROJECT_DIR/.gitignore"
  fi
fi
# Auth: always refresh from host (picks up renewed tokens from ralph:login)
[ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$CLAUDE_SESSION_DIR/"

trap cleanup EXIT
trap handle_interrupt INT

# Parse arguments (sets MAX_ITERATIONS, ONCE_FLAG; skips --project-dir)
parse_arguments "$@"

# Ensure log dir exists
mkdir -p "$(dirname "$PROGRESS_FILE")"

if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Pre-flight checks
check_git_repo
check_required_files
check_history_dir
check_ansi_support

# Verify podman image exists
if ! podman image exists "$RALPH_IMAGE" 2>/dev/null; then
  echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e "  ❌ ${RD}Podman image not found: $RALPH_IMAGE${R}"
  echo -e "  Build it first: ${C}pnpm ralph:build${R}"
  echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  exit 4
fi

show_ralph
echo -e " ${C}Starting Ralph${R} ・ ${Y}v$VERSION${R} ・ Max iterations: ${Y}$MAX_ITERATIONS${R} ・ Project: ${Y}$PROJECT_DIR${R}"
echo ""

# Pre-flight: check if all tasks already completed
TASKS_FILE="$PROJECT_DIR/.agent/tasks.json"
IDEA_FILE="$PROJECT_DIR/.agent/IDEA.md"
if [ -f "$TASKS_FILE" ] && command -v node &>/dev/null; then
  ALL_DONE=$(node -e "
    const t = JSON.parse(require('fs').readFileSync('$TASKS_FILE','utf8'));
    if (!Array.isArray(t) || t.length === 0) { process.stdout.write('empty'); process.exit(0); }
    const terminalStatuses = ['completed', 'done', 'cancelled', 'blocked'];
    const done = t.every(x => terminalStatuses.includes(x.status));
    process.stdout.write(done ? 'yes' : 'no');
  " 2>/dev/null || echo "no")
  if [ "$ALL_DONE" = "yes" ]; then
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ✅ ${GR}All tasks already completed.${R} Nothing to do."
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    exit $EXIT_COMPLETE
  fi
  if [ "$ALL_DONE" = "empty" ] && [ ! -f "$IDEA_FILE" ]; then
    echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ⚠️  ${Y}No tasks and no IDEA.md found.${R}"
    echo -e "  Write your idea to ${C}.agent/IDEA.md${R} and re-run."
    echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    exit 1
  fi
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION_START=$(date +%s)
  init_iteration_step_times

  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e "  ↪ ${R}Iteration ${Y}$i${R} of ${Y}$MAX_ITERATIONS${R}"
  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e ""

  # Select model via model-router based on current task
  MODEL=$(node "$SCRIPT_DIR/scripts/select-model.mjs" "$PROJECT_DIR" 2>/dev/null || echo "claude-sonnet-4-6")
  echo -e "  ${D}model: ${Y}$MODEL${R}"

  # Layer 3: agent-guide behavior principles (global, from AGENT_GUIDE_PATH)
  AGENT_GUIDE_SECTION=""
  if [ -n "${AGENT_GUIDE_PATH:-}" ] && [ -f "${AGENT_GUIDE_PATH}/principles/README.md" ]; then
    AGENT_GUIDE_SECTION="
## Behavior (from agent-guide: ${AGENT_GUIDE_PATH})

$(cat "${AGENT_GUIDE_PATH}/principles/README.md")"
  fi

  # Layer 2: project-specific context (optional, from PROJECT_DIR/.agent/PROMPT.md)
  PROJECT_PROMPT_SECTION=""
  if [ -f "${PROJECT_DIR}/.agent/PROMPT.md" ]; then
    PROJECT_PROMPT_SECTION="
## Project Context

$(cat "${PROJECT_DIR}/.agent/PROMPT.md")"
  fi

  # Layer 1 (framework: task loop + signals) + Layer 2 (project) + Layer 3 (behavior)
  PROMPT_CONTENT="PROJECT_ROOT=/workspace

$(cat "${SCRIPT_DIR}/.agent/PROMPT.md")${PROJECT_PROMPT_SECTION}${AGENT_GUIDE_SECTION}"

  start_spinner
  init_rolling_preview

  OUTPUT_FILE=$(mktemp)
  FULL_OUTPUT_FILE=$(mktemp)

  export PROMPT_CONTENT

  # Podman run (replaces: docker sandbox run claude . --)
  # - Source code: rw (agent needs to write code)
  # - ~/.claude-session: rw persistent (session survives between ralph runs)
  # - No new privileges, all caps dropped
  script -q "$OUTPUT_FILE" bash -c '
    podman run --rm \
      --security-opt no-new-privileges:true \
      --cap-drop ALL \
      --userns=keep-id \
      -e HOME=/tmp/claude-home \
      -v "'"$PROJECT_DIR"'":/workspace:rw \
      -v "'"$CLAUDE_SESSION_DIR"'":/tmp/claude-home/.claude:rw \
      -v "'"$HOME"'/.claude.json":/tmp/claude-home/.claude.json:ro \
      --workdir /workspace \
      '"$RALPH_IMAGE"' \
      --dangerously-skip-permissions \
      --model '"$MODEL"' \
      --output-format stream-json \
      --verbose \
      -p "$PROMPT_CONTENT"
  ' >/dev/null 2>&1 &
  AGENT_PID=$!

  LAST_POS=0

  while kill -0 "$AGENT_PID" 2>/dev/null; do
    if [ -f "$OUTPUT_FILE" ]; then
      CURRENT_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
      if [ "$CURRENT_SIZE" -gt "$LAST_POS" ]; then
        tail -c +$((LAST_POS + 1)) "$OUTPUT_FILE" 2>/dev/null | while IFS= read -r line; do
          if [ -n "$line" ]; then
            parsed=$(parse_json_content "$line")
            if [ -n "$parsed" ]; then
              echo "$parsed" >> "$FULL_OUTPUT_FILE"
              update_spinner_step "$parsed"
              update_preview_line "$parsed"
            fi
          fi
        done
        LAST_POS=$CURRENT_SIZE
      fi
    fi
    sleep 0.2
  done

  wait "$AGENT_PID" || true
  AGENT_PID=""

  if [ -f "$OUTPUT_FILE" ]; then
    CURRENT_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_SIZE" -gt "$LAST_POS" ]; then
      tail -c +$((LAST_POS + 1)) "$OUTPUT_FILE" 2>/dev/null | while IFS= read -r line; do
        if [ -n "$line" ]; then
          parsed=$(parse_json_content "$line")
          if [ -n "$parsed" ]; then echo "$parsed" >> "$FULL_OUTPUT_FILE"; fi
        fi
      done
    fi
  fi

  OUTPUT=$(cat "$FULL_OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE")

  # Auth error check
  if echo "$OUTPUT" | grep -q "Invalid API key\|not logged in\|authentication"; then
    stop_spinner
    clear_rolling_preview
    echo ""
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ❌ ${RD}Authentication Error${R}"
    echo -e "  Run: ${C}pnpm ralph:login${R}"
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    rm -f "$OUTPUT_FILE" "$FULL_OUTPUT_FILE"
    exit 5
  fi

  HISTORY_FILE="$HISTORY_DIR/ITERATION-${SESSION_ID}-${i}.txt"
  strip_ansi_file "$OUTPUT_FILE" "$HISTORY_FILE"

  FINAL_SUMMARY=$(extract_final_summary "$HISTORY_FILE")
  rm -f "$FULL_OUTPUT_FILE"
  FULL_OUTPUT_FILE=""

  stop_spinner
  record_step_time ""
  clear_rolling_preview

  # Build summary for both terminal display and ntfy notification
  NTFY_SUMMARY=""
  if [ -n "$FINAL_SUMMARY" ]; then
    display_final_summary "$FINAL_SUMMARY" 10
    NTFY_SUMMARY="$FINAL_SUMMARY"
  else
    FALLBACK_SUMMARY=$(echo "$OUTPUT" | tail -n 10)
    if [ -n "$FALLBACK_SUMMARY" ]; then
      display_final_summary "$FALLBACK_SUMMARY" 10
      NTFY_SUMMARY="$FALLBACK_SUMMARY"
    fi
  fi
  # Truncate for push notification readability
  NTFY_SUMMARY=$(echo "$NTFY_SUMMARY" | head -n 20 | cut -c1-500)

  rm -f "$OUTPUT_FILE"
  OUTPUT_FILE=""

  ITERATION_END=$(date +%s)
  ITERATION_DURATION=$((ITERATION_END - ITERATION_START))
  ITERATION_TIMES+=($ITERATION_DURATION)
  TOTAL_ITERATION_TIME=$((TOTAL_ITERATION_TIME + ITERATION_DURATION))
  ITERATION_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  ITERATION_STR=$(format_duration $ITERATION_DURATION)
  AVG_STR=$(format_duration $ITERATION_AVG)
  DELTA_STR=$(format_delta $ITERATION_DURATION $PREV_ITERATION_TIME)
  PREV_ITERATION_TIME=$ITERATION_DURATION

  if has_complete_tag "$OUTPUT" || has_complete_tag "$FINAL_SUMMARY"; then
    # Cross-check tasks.json — agent may emit COMPLETE prematurely
    TASKS_ACTUALLY_DONE=$(node -e "
      try {
        const t = JSON.parse(require('fs').readFileSync('$TASKS_FILE','utf8'));
        const terminal = ['completed','done','cancelled','blocked'];
        process.stdout.write((Array.isArray(t) && t.length > 0 && t.every(x => terminal.includes(x.status))) ? 'yes' : 'no');
      } catch(e) { process.stdout.write('no'); }
    " 2>/dev/null || echo "no")
    if [ "$TASKS_ACTUALLY_DONE" != "yes" ]; then
      echo -e "  ⚠️  ${Y}COMPLETE tag detected but tasks.json not all done — continuing...${R}"
      continue
    fi
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "[${PROJECT_NAME}] Ralph - COMPLETE" "All tasks finished in ${ELAPSED_STR}"
    send_ralph_ntfy "[${PROJECT_NAME}] Ralph COMPLETE (${ELAPSED_STR})" "${NTFY_SUMMARY:-All tasks finished.}"
    echo ""
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  🎉 ${GR}Ralph completed all tasks!${R}"
    echo -e "  ✅ Finished at iteration ${GR}$i${R} of ${GR}$MAX_ITERATIONS${R}"
    [ -n "$DELTA_STR" ] && echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}" \
                        || echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}"
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    exit $EXIT_COMPLETE
  fi

  if has_blocked_tag "$OUTPUT" || has_blocked_tag "$FINAL_SUMMARY"; then
    BLOCKED_REASON=$(extract_blocked_reason "$OUTPUT")
    [ -z "$BLOCKED_REASON" ] && BLOCKED_REASON=$(extract_blocked_reason "$FINAL_SUMMARY")
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - BLOCKED" "$BLOCKED_REASON"
    BLOCKED_BODY="${BLOCKED_REASON}"
    [ -n "$NTFY_SUMMARY" ] && BLOCKED_BODY="${BLOCKED_REASON}

${NTFY_SUMMARY}"
    send_ralph_ntfy "[${PROJECT_NAME}] Ralph BLOCKED" "$BLOCKED_BODY"
    printf '{"type":"BLOCKED","reason":"%s","ts":"%s"}\n' "$BLOCKED_REASON" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PROJECT_DIR/.agent/.ralph-waiting"
    display_blocked_message "$BLOCKED_REASON" "$i"
    [ -n "$DELTA_STR" ] && echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}" \
                        || echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}"
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    exit $EXIT_BLOCKED
  fi

  if has_decide_tag "$OUTPUT" || has_decide_tag "$FINAL_SUMMARY"; then
    DECIDE_QUESTION=$(extract_decide_question "$OUTPUT")
    [ -z "$DECIDE_QUESTION" ] && DECIDE_QUESTION=$(extract_decide_question "$FINAL_SUMMARY")
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - Decision Needed" "$DECIDE_QUESTION"
    DECIDE_BODY="${DECIDE_QUESTION}"
    [ -n "$NTFY_SUMMARY" ] && DECIDE_BODY="${DECIDE_QUESTION}

${NTFY_SUMMARY}"
    send_ralph_ntfy "[${PROJECT_NAME}] Ralph DECIDE" "$DECIDE_BODY"
    printf '{"type":"DECIDE","question":"%s","ts":"%s"}\n' "$DECIDE_QUESTION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PROJECT_DIR/.agent/.ralph-waiting"
    display_decide_message "$DECIDE_QUESTION" "$i"
    [ -n "$DELTA_STR" ] && echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}" \
                        || echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}"
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    exit $EXIT_DECIDE
  fi

  ELAPSED=$(($(date +%s) - START_TIME))
  ELAPSED_STR=$(format_duration $ELAPSED)

  if [ -n "$DELTA_STR" ]; then
    echo -e "${G}  └── ✓ Iteration $i complete${R} ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  else
    echo -e "${G}  └── ✓ Iteration $i complete${R} ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  fi

  STEP_TIMES_OUTPUT=$(format_step_times "ITERATION")
  [ -n "$STEP_TIMES_OUTPUT" ] && echo -e "${G}      └──${R} $STEP_TIMES_OUTPUT"

  sleep 2
done

ELAPSED=$(($(date +%s) - START_TIME))
ELAPSED_STR=$(format_duration $ELAPSED)

if [ ${#ITERATION_TIMES[@]} -gt 0 ]; then
  FINAL_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  FINAL_AVG_STR=$(format_duration $FINAL_AVG)
fi

play_notification_sound
show_notification "[${PROJECT_NAME}] Ralph - Max Iterations" "Reached limit of ${MAX_ITERATIONS} iterations. Check progress."
MAX_ITER_BODY="Reached ${MAX_ITERATIONS} iterations."
[ -n "${NTFY_SUMMARY:-}" ] && MAX_ITER_BODY="${MAX_ITER_BODY}

${NTFY_SUMMARY}"
send_ralph_ntfy "[${PROJECT_NAME}] Ralph max iterations (${MAX_ITERATIONS})" "$MAX_ITER_BODY"
echo ""
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
echo -e "  ⚠️  ${Y}Ralph reached max iterations${R} (${M}$MAX_ITERATIONS${R})"
[ ${#ITERATION_TIMES[@]} -gt 0 ] && echo -e "  ⏱️  Average iteration time: ${Y}$FINAL_AVG_STR${R}"
echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
display_session_step_totals
echo -e "  📋 Check progress: ${G}$PROGRESS_FILE${R}"
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
exit $EXIT_MAX_ITERATIONS
