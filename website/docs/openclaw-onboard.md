---
id: openclaw-onboard
title: OpenClaw Onboard
sidebar_position: 8
---

# OpenClaw Onboard Guide

Complete setup guide for the OpenClaw gateway, iMessage channel, and security hardening.

## Prerequisites

- Podman running with `openclaw` container built
- Ollama installed and serving on the host
- Headscale + Tailscale VPN configured

## 1. Gateway Configuration

### Config File vs Onboard Wizard

The `openclaw onboard` wizard **cannot write** to the config file when it is bind-mounted as a single file (`:ro` or not). This is a Podman limitation — `rename()` syscall fails on bind-mounted single files.

**Always edit `config/openclaw.json` on the host directly**, then restart:

```bash
# Edit config on host
vim config/openclaw.json

# Restart (NOT recreate) to preserve sessions
podman restart openclaw
```

### Recommended Settings

```json
{
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "tailscale": {
      "mode": "serve",
      "resetOnExit": true
    }
  }
}
```

| Key | Value | Description |
|-----|-------|-------------|
| `mode` | `local` | Run gateway on this machine |
| `bind` | `tailnet` | Bind to Tailscale IP only (VPN isolation) |
| `auth.mode` | `token` | Token-based authentication |
| `tailscale.mode` | `serve` | Expose via Tailnet (not Funnel) |
| `tailscale.resetOnExit` | `true` | Clean up serve config on exit |

### Environment Variables

All secrets go in `.env` (never committed). See `.env.example`:

```bash
OPENCLAW_GATEWAY_TOKEN=<your-token>
OLLAMA_HOST=http://host.containers.internal:11434
IMSG_SSH_USER=<your-macos-username>
```

## 2. iMessage Channel Setup

### Architecture

The container cannot run macOS `imsg` directly. An SSH bridge connects the container to the host:

```
Container          Host (macOS)
[openclaw] → SSH → [imsg-guard] → /opt/homebrew/bin/imsg
             ↑          ↑
        host-access   forced command
        network       (imsg only)
```

### Step 1: Generate SSH Key

```bash
mkdir -p ~/.openclaw/keys
ssh-keygen -t ed25519 -f ~/.openclaw/keys/openclaw_imsg -N "" -C "openclaw-imsg"
```

### Step 2: Register with Forced Command

Add to `~/.ssh/authorized_keys` (**one line**):

```
command="/path/to/agent-infrastructure/scripts/imsg-guard",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 <PUBLIC_KEY> openclaw-imsg
```

Security restrictions:
- `command="...imsg-guard"` — Only `imsg` commands allowed
- `no-port-forwarding` — Tunnel blocked
- `no-agent-forwarding` — SSH agent forwarding blocked
- `no-pty` — Shell access blocked

### Step 3: Docker Compose Volumes

In `docker-compose.yml`, the openclaw service needs:

```yaml
volumes:
  - ~/.openclaw/keys/openclaw_imsg:/home/node/.ssh/openclaw_imsg:ro
  - ./scripts/imsg-host:/usr/local/bin/imsg:ro

networks:
  - openclaw-internal   # egress-proxy communication
  - host-access         # SSH to host

environment:
  - IMSG_SSH_USER=${IMSG_SSH_USER}
```

### Step 4: Enable in Config

```json
{
  "channels": {
    "imessage": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist"
    }
  },
  "plugins": {
    "entries": {
      "imessage": {
        "enabled": true
      }
    }
  }
}
```

### Step 5: Verify

```bash
podman restart openclaw
sleep 3

# SSH bridge test
podman exec openclaw imsg --version

# Doctor check — should show "iMessage: ok"
podman exec openclaw openclaw doctor
```

## 3. DM Pairing Flow

### Initial Pairing

First-time setup requires `pairing` mode to approve your device:

1. Set `dmPolicy` to `pairing` in config
2. Restart: `podman restart openclaw`
3. Send iMessage from your phone to the OpenClaw Apple ID
4. Receive pairing code via iMessage
5. Approve:

```bash
podman exec openclaw openclaw pairing list imessage
podman exec openclaw openclaw pairing approve imessage <code>
```

### Switch to Allowlist

After approving, lock down to prevent strangers from triggering responses:

1. Edit config: change `dmPolicy` to `allowlist`
2. Restart: `podman restart openclaw`
3. Only approved devices receive responses; new senders are silently ignored

## 4. Security Layers

### imsg-guard (Forced Command Wrapper)

`scripts/imsg-guard` runs on the **host** via SSH forced command:

- Rejects shell metacharacters (`;`, `|`, `&`, `` ` ``, `$`, `()`, `<>`)
- Validates command starts with `/opt/homebrew/bin/imsg`
- Logs every attempt to `~/.openclaw/logs/imsg-audit.log`

```
2026-02-15T11:20:50Z OK /opt/homebrew/bin/imsg --version
2026-02-15T11:21:02Z REJECTED unauthorized ls /
2026-02-15T11:21:10Z REJECTED metachar /opt/homebrew/bin/imsg; cat /etc/passwd
```

### Network Isolation

```
┌──────────────────────────────────┐
│ openclaw-internal (internal)     │
│  [openclaw] ↔ [egress-proxy]    │
└──────────────────────────────────┘
┌──────────────────────────────────┐
│ host-access                      │
│  [openclaw] → SSH → host (imsg) │
└──────────────────────────────────┘
```

- `openclaw-internal`: `internal: true` — no external access, egress-proxy only
- `host-access`: SSH bridge to host for iMessage

### Bind Mount Read-Only

```yaml
- ./config/openclaw.json:/home/node/.openclaw/openclaw.json:ro
```

Config is read-only inside the container. All config changes happen on the host.

## 5. Operational Notes

### DO

- Edit config on host, then `podman restart openclaw`
- Use `podman exec` for read-only commands (`config get`, `doctor`, `pairing list`)
- Check audit log: `cat ~/.openclaw/logs/imsg-audit.log`

### DO NOT

- Use `podman compose run --rm` for state-changing commands — may reset session data
- Remove `:ro` from config bind mount in production
- Hardcode usernames, tokens, or IPs in committed files — use `${ENV_VAR}`

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `EBUSY: resource busy or locked` | Single file bind mount + write attempt | Edit config on host, not inside container |
| `imsg not found` | Bridge script mounted as wrong name | Mount as `/usr/local/bin/imsg` |
| `Network is unreachable` (SSH) | Missing `host-access` network | Add `host-access` network to compose |
| `Permission denied` (SSH) | Key not in authorized_keys or truncated | Check full key line in authorized_keys |
| Session lost after restart | Used `podman compose run --rm` | Use `podman restart` instead |
| Pairing code sent to strangers | `dmPolicy` is `pairing` | Switch to `allowlist` after approving |
