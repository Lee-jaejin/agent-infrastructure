---
id: getting-started
title: Getting Started
sidebar_position: 4
---

# Getting Started

Quick setup guide for the private AI system.

## Prerequisites

- macOS or Linux
- Podman and Podman Compose
- 16GB+ RAM (36GB recommended for 34B models)
- Node.js 20+

## Quick Setup

```bash
# Clone repository
git clone https://github.com/jaejin/agent-infrastructure.git
cd agent-infrastructure

# Run complete setup
./scripts/setup-all.sh
```

The setup script will:
1. Install Ollama and download models
2. Start Headscale container
3. Build and run OpenClaw container
4. Configure the model router

## Manual Setup

### Step 1: Ollama

```bash
# Install Ollama
brew install ollama

# Start service
ollama serve

# Download models
bash infra/ollama/models.sh
```

### Step 2: Headscale

```bash
cd infra/headscale
podman compose up -d
```

### Step 3: OpenClaw

```bash
cd infra/openclaw
podman compose up -d
```

### Step 4: Model Router Plugin

```bash
cd plugins/model-router
pnpm install
pnpm build
```

## Verify Installation

```bash
# Check Ollama
curl http://localhost:11434/api/tags

# Check Headscale
podman logs headscale

# Check OpenClaw
curl http://localhost:18789/health
```

## Next Steps

- [Headscale Setup](/headscale-setup) - Configure VPN coordinator
- [Mobile Support](/mobile-support) - Connect mobile devices
- [Model Router](/model-router) - Customize model routing
