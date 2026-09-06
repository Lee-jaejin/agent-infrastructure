# Model Router Plugin

Multi-LLM routing plugin for task-based model selection.

## Model Mapping

Default models are configured in `src/index.ts`. Routes by task type:

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
// => coding model from DEFAULT_MODELS

// Classify task only
const taskType = classifyTask("Why does this work that way?");
// => "reasoning"
```

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

## Build

```bash
cd plugins/model-router
pnpm install
pnpm build
```

---

## 한국어 (Korean)

### 모델 매핑

기본 모델은 `src/index.ts`에서 설정. 작업 유형별 라우팅:
- **coding**: 코드, 함수, 버그, 디버그
- **reasoning**: 왜, 분석, 비교, 논리
- **general**: 기타 모든 요청
