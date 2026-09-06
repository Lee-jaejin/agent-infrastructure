---
id: intro
title: Introduction
sidebar_position: 1
slug: /
---

# OpenClaw Private

Private AI System for closed-circuit networks. Personal use only.

## Overview

This project provides a complete private AI infrastructure that:

- **No external cloud dependency** - All processing happens locally
- **Only designated devices can communicate** - Secured by WireGuard VPN
- **All communication encrypted** - End-to-end encryption via Headscale/Tailscale
- **Local LLM prevents data leakage** - Using Ollama for local inference
- **Container isolation protects host** - OpenClaw runs in isolated containers

## Components

| Component | Purpose |
|-----------|---------|
| **Headscale** | Self-hosted Tailscale coordinator |
| **Tailscale** | WireGuard VPN client |
| **Ollama** | Local LLM inference engine |
| **OpenClaw** | AI gateway in container |
| **Model Router** | Task-based model selection |

## Model Strategy

Task-based routing with locally hosted models (see `config/openclaw.json` for current model list):

| Task Type | Use Case |
|-----------|----------|
| **Coding** | Code generation, debugging |
| **Reasoning** | Analysis, complex logic |
| **General** | General conversation |

## Quick Start

```bash
# Clone repository
git clone https://github.com/jaejin/agent-infrastructure.git
cd agent-infrastructure

# Run setup
./scripts/setup-all.sh
```

See [Getting Started](/getting-started) for detailed instructions.
