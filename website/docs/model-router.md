---
id: model-router
title: Model Router
sidebar_position: 8
---

# Model Router Plugin

Multi-LLM routing plugin for task-based model selection.

## Model Mapping

Default models are configured in `plugins/model-router/src/index.ts`. Each task type routes to a different model:

| Task Type | Trigger Keywords |
|-----------|------------------|
| **coding** | code, function, bug, debug |
| **reasoning** | why, analyze, compare, logic |
| **general** | all other requests |

## Usage

```typescript
import { selectModel, classifyTask } from "@agent-infrastructure/model-router";

// Select model based on message
const model = selectModel("Find the bug in this code");
// => coding model

// Classify task only
const taskType = classifyTask("Why does this work that way?");
// => "reasoning"
```

## Korean Language Support

The router supports Korean keywords:

```typescript
// Korean coding keywords
selectModel("이 코드에서 버그를 찾아줘");
// => coding model

// Korean reasoning keywords
selectModel("왜 이렇게 동작하는지 분석해줘");
// => reasoning model
```

## Claude Provider

Use the `provider: "claude"` option to route to Claude models instead of Ollama:

```typescript
import { createModelRouter } from "@agent-infrastructure/model-router";

const router = createModelRouter({ provider: "claude" });

router.selectModel("Fix this bug");
// => "claude-sonnet-4-6"

router.selectModel("Analyze the architecture trade-offs");
// => "claude-opus-4-6"
```

Default Claude model mapping:

| Task Type | Model |
|-----------|-------|
| `coding` | `claude-sonnet-4-6` |
| `reasoning` | `claude-opus-4-6` |
| `general` | `claude-sonnet-4-6` |

This is used by [Ralph Loop](./ralph-loop.md) to automatically select the model per iteration.

## Custom Configuration

```typescript
import { createModelRouter } from "@agent-infrastructure/model-router";

const router = createModelRouter({
  models: {
    coding: "ollama/<your-coding-model>",
    reasoning: "ollama/<your-reasoning-model>",
  },
  debug: true, // enable debug logging
});

const model = router.selectModel("Implement this function");
```

## Keywords Reference

### Coding Keywords

English: `code`, `function`, `bug`, `debug`, `refactor`, `implement`, `class`, `method`, `variable`, `error`, `compile`, `syntax`, `api`, `endpoint`, `database`, `query`, `test`, `unit test`

Korean: `코드`, `함수`, `버그`, `디버그`, `리팩토링`, `구현`, `클래스`, `메서드`, `변수`, `에러`, `컴파일`, `문법`

### Reasoning Keywords

English: `why`, `analyze`, `compare`, `explain`, `reason`, `logic`, `think`, `evaluate`, `pros and cons`, `trade-off`, `decision`, `strategy`

Korean: `왜`, `분석`, `비교`, `설명`, `이유`, `논리`, `생각`, `평가`, `장단점`, `트레이드오프`, `결정`, `전략`

## Build

```bash
cd plugins/model-router
pnpm install
pnpm build
```

## Integration with OpenClaw

The model router can be integrated with OpenClaw's plugin system:

```json
{
  "plugins": {
    "model-router": {
      "enabled": true,
      "config": {
        "models": {
          "coding": "ollama/<coding-model>",
          "reasoning": "ollama/<reasoning-model>",
          "general": "ollama/<general-model>"
        }
      }
    }
  }
}
```
