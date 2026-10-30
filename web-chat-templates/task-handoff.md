# Task Handoff

> 把网页对话的讨论压缩成这张卡。
> 位置：**Task Brief 之后、交给本地 Agent 之前**。
>
> **压缩规则：删讨论过程，留术语和决策。** 术语、已排除的方案、刻意反常规的做法、看不见的约束——这四类内容要原样带过来，不要当成「冗余」删掉。它们之后会被写进项目的 `CONTEXT.md` 和 `docs/adr/`。
>
> 先存到临时位置（`%TEMP%` / `/tmp`）——这时项目还不存在。走完 Phase 2 搭项目，Phase 3 开始时再粘进 `tasks/<日期>-<简述>/prd.md`。

## Goal

<!-- 一句话说清楚要实现什么，以及为什么要做 -->

## 这一版要验证什么

<!-- 从 Task Brief 原样带过来，不要删。没有就删掉这一节。
     它一路进 prd.md，Spec 轴审查时会看「做完之后有没有拿到那个信号」。 -->

## Current Understanding

<!-- 网页对话阶段已经确认的产品行为、技术方向、边界 -->

## User Stories

<!-- 从 Task Brief 原样带过来——prd.md 的 `## User Stories` 就是从这里来的。
     少了一节，Phase 3 就得凭空补，Spec 轴也没法对。没有就写「无」。 -->

-

## Context Pointers

<!-- 让本地 Agent 优先阅读的文件、目录、已有相似实现 -->

-
-

## Constraints

<!-- 禁止行为、代码风格、依赖限制、兼容性要求 -->

-

## Out of Scope

<!-- 本次明确不做什么 -->

-

## Done When

<!-- 可验证的验收条件 -->

- [ ]

## Verification

<!-- 希望 Agent 运行的测试、lint、typecheck、build 或手动验证 -->

- [ ]

## Testing Notes

<!-- 从 Task Brief 原样带过来——prd.md 的 `## Testing Decisions` 就是从这里来的。
     没有就写「无」。 -->

-

## Risks

<!-- 你已经知道的风险，让 Agent 重点检查 -->

-

## 术语与决策

<!-- 四类内容，压缩时不能删。缺哪类写「无」。 -->

**术语**

-

**已排除的方案**

-

**刻意偏离常规的地方**

-

**代码里看不见的约束**

-
