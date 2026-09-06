---
id: ralph-loop
title: Ralph Loop
sidebar_position: 9
---

# Ralph Loop

Long-running autonomous agent loop powered by Claude Code subscription and Podman isolation.

Forked from [PageAI-Pro/ralph-loop](https://github.com/PageAI-Pro/ralph-loop), adapted to replace Docker sandbox with rootless Podman and integrate the model-router plugin for automatic model selection.

## How It Works

Each iteration, Ralph:

1. Reads the highest-priority incomplete task from `.agent/tasks.json`
2. Classifies the task via model-router → selects `claude-sonnet-4-6` or `claude-opus-4-6`
3. Runs `claude --dangerously-skip-permissions` inside a Podman container
4. Monitors output for completion / blocked / decide signals
5. Logs the iteration history and loops

```
./ralph.sh -n 20
  └── iteration 1
        ├── select-model → claude-sonnet-4-6  (coding task)
        ├── podman run ralph-claude -- claude --model claude-sonnet-4-6
        └── ✓ task committed
  └── iteration 2
        ├── select-model → claude-opus-4-6  (architecture task)
        ├── podman run ralph-claude -- claude --model claude-opus-4-6
        └── ✓ task committed
  └── 🎉 all tasks complete
```

## Model Selection

The model-router plugin automatically picks the model based on the current task description:

| Task Type | Model | When |
|-----------|-------|------|
| `coding` | `claude-sonnet-4-6` | code, bug, implement, test, build… |
| `reasoning` | `claude-opus-4-6` | analyze, compare, architecture, strategy… |
| `general` | `claude-sonnet-4-6` | everything else |

## Setup

### 1. Build the Podman image (once)

```bash
pnpm ralph:build
```

This builds a rootless Podman image with Node.js 22 and the Claude Code CLI.

### 2. Login with your claude.ai subscription (once)

```bash
pnpm ralph:login
```

Runs an interactive login inside the container and persists credentials to `~/.claude/`.

### 3. Create your task list

Create `.agent/tasks.json` in your project:

```json
[
  {
    "id": "TASK-001",
    "title": "Add input validation to the signup form",
    "description": "Implement and test input validation for email and password fields",
    "priority": 1,
    "status": "pending"
  },
  {
    "id": "TASK-002",
    "title": "Analyze current auth architecture",
    "description": "Analyze and document the current authentication strategy and trade-offs",
    "priority": 2,
    "status": "pending"
  }
]
```

Optionally create `.agent/PROMPT.md` with project-specific context (see [Prompt Layers](#prompt-layers)).

### 4. Run

```bash
# Run from your project directory
pnpm ralph -- --project-dir=/path/to/your/project -n 20

# Or run directly
bash infra/ralph/ralph.sh --project-dir=/path/to/your/project -n 20
```

## Prompt Layers

Ralph builds its prompt from three independent layers, combined at runtime:

| Layer | Source | Content |
|-------|--------|---------|
| **1. Framework** | `infra/ralph/.agent/PROMPT.md` | Task loop rules, COMPLETE/BLOCKED/DECIDE signal definitions |
| **2. Project** | `PROJECT_DIR/.agent/PROMPT.md` | Tech stack, conventions, domain constraints, completion criteria |
| **3. Behavior** | `AGENT_GUIDE_PATH/principles/` | Coding principles (Think Before Coding, Simplicity First…) |

Layer 1 is always included. Layers 2 and 3 are optional — if the files are missing, they are silently skipped.

### Project prompt (Layer 2)

Copy the example template and fill it in:

```bash
cp infra/ralph/.agent/PROMPT.project.example.md /path/to/your/project/.agent/PROMPT.md
```

Focus on project-specific context only. Do not repeat task loop rules (Layer 1) or behavior principles (Layer 3):

```markdown
## Overview
Next.js 14 SaaS app with Stripe, Prisma, PostgreSQL.

## Tech Stack
- TypeScript strict, pnpm, Vitest + Playwright

## Conventions
- Server Component by default; 'use client' only when necessary
- DB access via Prisma only, no raw SQL
- Conventional Commits

## Constraints
- No hardcoded secrets — use .env
- pnpm test must pass before commit
```

### Behavior principles (Layer 3)

Set `AGENT_GUIDE_PATH` in `.env` to point to your local [agent-guide](https://github.com/PageAI-Pro/agent-guide) checkout:

```bash
AGENT_GUIDE_PATH=/Users/yourname/Study/ai/agent-guide
```

Ralph reads `$AGENT_GUIDE_PATH/principles/README.md` on each invocation, so updates to agent-guide take effect automatically on the next run.

## Signals

Ralph detects special tags in Claude's output to control the loop:

| Signal | Tag | Behavior |
|--------|-----|----------|
| All done | `<COMPLETE>…</COMPLETE>` | Exit with success |
| Needs human input | `<BLOCKED>…</BLOCKED>` | Pause and notify |
| Needs decision | `<DECIDE>…</DECIDE>` | Pause and notify |

## Container Isolation

The Podman container runs with minimum privileges:

```
--security-opt no-new-privileges:true
--cap-drop ALL
--userns=keep-id
```

| Mount | Mode | Purpose |
|-------|------|---------|
| `PROJECT_DIR` → `/workspace` | `rw` | Claude reads and writes project files |
| `~/.claude` → `/root/.claude` | `ro` | Auth tokens (read-only, not writable by agent) |

## File Structure

```
infra/ralph/
├── Containerfile                    # Podman image definition
├── ralph.sh                         # Main loop script
├── projects.json                    # Multi-project registry (alias → path)
├── scripts/
│   ├── lib/                         # Logging, spinner, timing helpers
│   └── select-model.mjs             # Reads tasks.json → model-router → model name
└── .agent/
    ├── PROMPT.md                    # Layer 1: framework prompt (task loop, signals)
    ├── PROMPT.project.example.md    # Layer 2 template: copy to your project
    └── tasks.json                   # Example task list

scripts/
├── ralph-imsg-watch.sh              # Handles BLOCKED/DECIDE replies from ntfy
├── ralph-task-watch.sh              # Handles new task requests from ntfy
├── ralph-start-projects.sh         # Starts all per-project watchers at once
├── ralph-new-project.sh            # Scaffolds new project + GitHub + registers in projects.json
└── ralph-new-project-watch.sh      # Watches ntfy for new project creation requests
```

## Create a Project from iPhone

Send a single ntfy message to scaffold a new project directory, initialise git, create a private GitHub repo, and register it with Ralph — all in one step.

### Prerequisites

| Requirement | How to meet it |
|-------------|----------------|
| `RALPH_PROJECTS_BASE_DIR` set in `.env` | Base directory where new projects are created |
| `gh` CLI authenticated *(optional)* | Only for GitHub repo creation — `gh auth login` once |
| `GITHUB_OWNER` set in `.env` *(optional)* | GitHub user or org name |

```bash
# .env
RALPH_PROJECTS_BASE_DIR=/Users/yourname/projects
GITHUB_OWNER=your-github-username          # omit to skip GitHub step
NTFY_RALPH_NEW_PROJECT_TOPIC=ralph-new-project  # default, can omit
```

### Send from iPhone

Open `http://100.64.0.1:8095` in iPhone Safari → topic `ralph-new-project`

| Message format | Example |
|----------------|---------|
| Name only | `my-webapp` |
| Name + description | `my-webapp: E-commerce storefront in Next.js` |

### What happens

```
iPhone → "my-webapp: E-commerce storefront"
  → ralph:new-project-watch detects
  → Creates /projects/my-webapp/
      .agent/tasks.json     (empty task list)
      .agent/PROMPT.md      (from template — edit to add project context)
      README.md
      .gitignore
  → git init && initial commit
  → gh repo create your-github-username/my-webapp --private --push  (if GITHUB_OWNER set)
  → Registers "my-webapp" in infra/ralph/projects.json
  → Starts ralph:task-watch[my-webapp] automatically
  → Sends "[my-webapp] 프로젝트 생성 완료" to ntfy ralph topic
```

Once the notification arrives, immediately send tasks to `ralph-task-my-webapp` — the watcher is already running.

### Starting the watcher

Starts automatically with `yarn ralph:start-projects` (when `RALPH_PROJECTS_BASE_DIR` is set). To run standalone:

```bash
yarn ralph:new-project-watch
```

> **No restart needed for new projects.** `ralph-new-project-watch` starts a dedicated `ralph:task-watch` for every project it creates. You only need to restart `ralph:start-projects` after a machine reboot or if the process dies.

### Customise the project prompt

After creation, edit `.agent/PROMPT.md` in the new project to describe the tech stack and conventions (Layer 2 of the [Prompt Layers](#prompt-layers) system):

```bash
nano /Users/yourname/projects/my-webapp/.agent/PROMPT.md
```

---

## Multi-Project Mode

Run Ralph across multiple projects simultaneously, each with its own ntfy task topic.

### 1. Register projects

Edit `infra/ralph/projects.json`:

```json
{
  "webapp": "/Users/yourname/projects/webapp",
  "api": "/Users/yourname/projects/api"
}
```

Any git repository works. Each project's `.agent/tasks.json` is created automatically when the first task arrives.

### 2. Start all watchers

```bash
yarn ntfy:up
yarn ralph:start-projects   # starts ralph:watch + one ralph:task-watch per project
```

`ralph:start-projects` reads `projects.json` and starts:
- One `ralph:task-watch` per project, listening on `ralph-task-{name}`
- One shared `ralph:watch` for all BLOCKED/DECIDE replies

### 3. iPhone topics

| Action | ntfy topic |
|--------|-----------|
| Send task to webapp | `ralph-task-webapp` |
| Send task to api | `ralph-task-api` |
| Read all notifications | `ralph` |
| Reply to BLOCKED/DECIDE | `ralph-reply` |

Reply format when multiple projects may be waiting:
```
webapp: yes, go with option A
```

---

## iPhone Integration (ntfy)

Ralph sends DECIDE/BLOCKED/COMPLETE notifications to your iPhone via ntfy, and resumes when you reply. You can also send new tasks from your iPhone — giving Ralph its own chat channel separate from OpenClaw (iMessage).

| Agent | Channel |
|-------|---------|
| OpenClaw | iMessage |
| Ralph | ntfy web UI (iPhone via VPN) |

### 1. Configure `.env`

```bash
# ntfy server (runs on the control tower)
NTFY_URL=http://localhost:8095
NTFY_RALPH_TOPIC=ralph
NTFY_RALPH_REPLY_TOPIC=ralph-reply

# Single-project mode only
NTFY_RALPH_TASK_TOPIC=ralph-task
RALPH_PROJECT_DIR=/path/to/your/project

# Behavior principles (optional)
AGENT_GUIDE_PATH=/Users/yourname/Study/ai/agent-guide
```

> `NTFY_URL` uses `localhost` because Ralph and the watch scripts run on the same machine as ntfy. The iPhone connects via VPN IP (`http://100.64.0.1:8095`).

### 2. Start watch services

**Single-project:**
```bash
yarn ntfy:up
yarn ralph:watch &
yarn ralph:task-watch &
```

**Multi-project:**
```bash
yarn ntfy:up
yarn ralph:start-projects
```

### 3. Set up ntfy on iPhone

Requires: iPhone connected to headscale VPN — see [iPhone VPN Setup](./iphone-vpn-setup.md).

Open iPhone Safari → `http://100.64.0.1:8095`

| Action | Topic |
|--------|-------|
| Read notifications | `ralph` |
| Send task (single-project) | `ralph-task` |
| Send task (multi-project) | `ralph-task-{name}` |
| Reply to BLOCKED/DECIDE | `ralph-reply` |

### 4. Send a task from iPhone

1. Open `http://100.64.0.1:8095` in iPhone Safari (VPN must be connected)
2. Navigate to the relevant task topic → publish a message with the task description
3. `ralph:task-watch` detects it → adds to `tasks.json` → starts `yarn ralph` automatically

### 5. Reply to BLOCKED/DECIDE

When Ralph pauses and needs your input:

1. Open `http://100.64.0.1:8095` → topic `ralph` to read the question
   - Notification title includes the project name: `[webapp] Ralph BLOCKED`
2. Publish your answer to topic `ralph-reply`
   - Single project: just the answer text
   - Multi-project: prefix with project name: `webapp: yes, proceed`
3. `ralph:watch` detects the reply → resumes Ralph

### Full Flow

```
iPhone (ntfy web UI) → publishes to "ralph-task-webapp"
  → ralph:task-watch[webapp] detects → adds task to tasks.json → starts ralph
  → Ralph works...
  → Ralph hits BLOCKED/DECIDE → publishes "[webapp] Ralph BLOCKED" to "ralph" topic
  → iPhone sees notification in ntfy web UI
  → iPhone publishes "webapp: yes proceed" to "ralph-reply"
  → ralph:watch detects → writes HUMAN_REPLY.md → resumes Ralph
  → Ralph completes → publishes COMPLETE to "ralph" topic
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_IMAGE` | `ralph-claude` | Podman image name |
| `NTFY_URL` | — | ntfy server URL (e.g. `http://localhost:8095`) |
| `NTFY_RALPH_TOPIC` | `ralph` | Topic for outgoing BLOCKED/DECIDE/COMPLETE notifications |
| `NTFY_RALPH_REPLY_TOPIC` | `ralph-reply` | Topic for incoming human replies |
| `NTFY_RALPH_TASK_TOPIC` | `ralph-task` | Task topic (single-project mode only) |
| `RALPH_PROJECT_DIR` | — | Project path (single-project mode only) |
| `AGENT_GUIDE_PATH` | — | Path to agent-guide repo for Layer 3 behavior principles |
| `RALPH_PROJECTS_BASE_DIR` | — | Base directory for new projects created via iPhone |
| `GITHUB_OWNER` | — | GitHub user/org for repo creation (requires `gh auth login`) |
| `NTFY_RALPH_NEW_PROJECT_TOPIC` | `ralph-new-project` | Topic for incoming new project requests |

Set in `.env` or pass directly:

```bash
RALPH_IMAGE=my-ralph pnpm ralph -- -n 10
```

## Iteration History

Each iteration is saved to `.agent/history/ITERATION-{SESSION}-{N}.txt` for review.

## Monitoring

**Check if Ralph is running:**
```bash
pgrep -la "ralph\.sh"
```

**Check task status:**
```bash
cat /path/to/project/.agent/tasks.json | python3 -m json.tool
```
Task `status` is `pending` (queued), `completed` (done), or `cancelled` (skipped).

**Follow live iteration log:**
```bash
ls -t /path/to/project/.agent/history/ | head -3
tail -f /path/to/project/.agent/history/ITERATION-*.txt
```

**iPhone:** Watch the `ralph` ntfy topic — Ralph sends `[project] Ralph: starting`, `BLOCKED`, `DECIDE`, and `COMPLETE` notifications.

## Cancel or Revert Work

**Stop Ralph mid-task:**
```bash
pkill -f "ralph\.sh"
podman stop $(podman ps -q --filter ancestor=ralph-claude 2>/dev/null) 2>/dev/null || true
```

**Undo completed commits** (Ralph commits after each task):
```bash
cd /path/to/project
git log --oneline -10       # see what Ralph did
git reset --soft HEAD~1     # undo last commit, keep file changes
git reset --soft HEAD~3     # undo last 3 commits
git revert HEAD             # safe revert (preserves history, use if already pushed)
```

**Cancel a queued task** — edit `.agent/tasks.json` and set its `status` to `"cancelled"`.

**Natural pause point:** Ralph stops automatically on `BLOCKED` / `DECIDE` signals. Not replying to the ntfy notification holds it paused indefinitely.

## Keeping `ralph:start-projects` Running

Use tmux so the process survives terminal closes:

```bash
# Start in background tmux session
tmux new-session -d -s ralph 'cd /path/to/agent-infrastructure && yarn ralph:start-projects'

# Attach to see logs
tmux attach -t ralph

# Detach without stopping: Ctrl+B then D
```

On machine reboot, run the tmux command again (or add it to your shell profile / launchd).

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `OAuth token has expired` | Claude Code login expired | `yarn ralph:login` |
| `all tasks already completed` | Wrong `--project-dir` format | Use `--project-dir=VALUE` (with `=`, not space) |
| `must be run inside a git repository` | Project dir not a git repo | `git init && git commit --allow-empty -m "initial"` in the project dir |
| `timeout: command not found` | macOS lacks GNU `timeout` | Fixed — `timeout` removed from `ralph-new-project.sh` |
| `ralph already running` (false positive) | pgrep matched task-watch process | Fixed — pgrep now checks `ralph\.sh` specifically |
| Task queued but Ralph never starts | `ralph:start-projects` died | Restart with tmux; run `yarn ralph -- --project-dir=...` to trigger immediately |
| `ralph:new-project-watch` not starting | `RALPH_PROJECTS_BASE_DIR` not set | Add it to `.env` |
| GitHub repo creation fails | Repo already exists or `gh` not authenticated | Script continues without remote; add remote manually or run `gh auth login` |

## Relation to OpenClaw

Ralph is a separate tool that runs alongside OpenClaw — it is not part of the OpenClaw AI gateway. OpenClaw handles always-on multi-channel messaging with local Ollama models; Ralph runs autonomous coding sessions using your Claude Code subscription.
