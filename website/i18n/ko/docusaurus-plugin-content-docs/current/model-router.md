---
id: model-router
title: Model Router
sidebar_position: 8
---

# Model Router 플러그인

작업 기반 모델 선택을 위한 멀티 LLM 라우팅 플러그인입니다.

## 모델 매핑

기본 모델은 `plugins/model-router/src/index.ts`에서 설정. 작업 유형별로 다른 모델을 라우팅:

| 작업 유형 | 트리거 키워드 |
|----------|--------------|
| **coding** | code, function, bug, debug |
| **reasoning** | why, analyze, compare, logic |
| **general** | 기타 모든 요청 |

## 사용법

```typescript
import { selectModel, classifyTask } from "@agent-infrastructure/model-router";

// 메시지 기반 모델 선택
const model = selectModel("이 코드에서 버그를 찾아줘");
// => coding 모델

// 작업 분류만
const taskType = classifyTask("왜 이렇게 동작하는지 설명해줘");
// => "reasoning"
```

## 한국어 지원

라우터는 한국어 키워드를 지원합니다:

```typescript
// 한국어 코딩 키워드
selectModel("이 코드에서 버그를 찾아줘");
// => coding 모델

// 한국어 추론 키워드
selectModel("왜 이렇게 동작하는지 분석해줘");
// => reasoning 모델
```

## Claude 프로바이더

`provider: "claude"` 옵션으로 Ollama 대신 Claude 모델로 라우팅:

```typescript
import { createModelRouter } from "@agent-infrastructure/model-router";

const router = createModelRouter({ provider: "claude" });

router.selectModel("이 버그를 수정해줘");
// => "claude-sonnet-4-6"

router.selectModel("아키텍처 트레이드오프를 분석해줘");
// => "claude-opus-4-6"
```

기본 Claude 모델 매핑:

| 태스크 유형 | 모델 |
|------------|------|
| `coding` | `claude-sonnet-4-6` |
| `reasoning` | `claude-opus-4-6` |
| `general` | `claude-sonnet-4-6` |

[Ralph Loop](./ralph-loop.md)에서 이터레이션마다 모델을 자동 선택할 때 사용합니다.

## 커스텀 설정

```typescript
import { createModelRouter } from "@agent-infrastructure/model-router";

const router = createModelRouter({
  models: {
    coding: "ollama/<코딩-모델>",
    reasoning: "ollama/<추론-모델>",
  },
  debug: true, // 디버그 로깅 활성화
});

const model = router.selectModel("이 함수를 구현해줘");
```

## 키워드 참조

### 코딩 키워드

영어: `code`, `function`, `bug`, `debug`, `refactor`, `implement`, `class`, `method`, `variable`, `error`, `compile`, `syntax`, `api`, `endpoint`, `database`, `query`, `test`, `unit test`

한국어: `코드`, `함수`, `버그`, `디버그`, `리팩토링`, `구현`, `클래스`, `메서드`, `변수`, `에러`, `컴파일`, `문법`

### 추론 키워드

영어: `why`, `analyze`, `compare`, `explain`, `reason`, `logic`, `think`, `evaluate`, `pros and cons`, `trade-off`, `decision`, `strategy`

한국어: `왜`, `분석`, `비교`, `설명`, `이유`, `논리`, `생각`, `평가`, `장단점`, `트레이드오프`, `결정`, `전략`

## 빌드

```bash
cd plugins/model-router
pnpm install
pnpm build
```

## OpenClaw 연동

Model Router는 OpenClaw의 플러그인 시스템과 연동할 수 있습니다:

```json
{
  "plugins": {
    "model-router": {
      "enabled": true,
      "config": {
        "models": {
          "coding": "ollama/<코딩-모델>",
          "reasoning": "ollama/<추론-모델>",
          "general": "ollama/<범용-모델>"
        }
      }
    }
  }
}
```
