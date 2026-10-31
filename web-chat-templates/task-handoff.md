# Task Handoff

> 把网页对话的讨论压缩成这张卡。
> 位置：**Task Brief 之后、交给本地 Agent 之前**。
>
> **压缩规则：删讨论过程，留术语和决策。** 术语、已排除的方案、刻意反常规的做法、看不见的约束——这四类内容要原样带过来，不要当成「冗余」删掉。它们之后会被写进项目的 `CONTEXT.md` 和 `docs/adr/`。
>
> 先存到临时位置（`%TEMP%` / `/tmp`）——这时项目还不存在。走完 Phase 2 搭项目，Phase 3 开始时再粘进 `tasks/<日期>-<简述>/prd.md`。
>
> **每节都标了去处**：标 `→ prd.md` 的按 prd.md 模板逐项填；标 `→ 长期文档` 的在 Phase 2 就落成 `CONTEXT.md` / `docs/adr/` / `docs/architecture.md`，**不要在 prd.md 里再抄一遍**。

## Goal

<!-- → prd.md 的 `## Goal`。一句话说清楚要实现什么，以及为什么要做 -->

## 这一版要验证什么

<!-- → prd.md 的同名节。从 Task Brief 原样带过来，不要删。没有就删掉这一节。
     Spec 轴审查时会看「做完之后有没有拿到那个信号」。 -->

## Current Understanding

<!-- → 长期文档：Phase 2 的 Agent 拿它写 docs/architecture.md 的现状。
     prd.md 里不单独成节——已经确认的产品行为并进 `## Requirements`，
     技术方向和边界并进 `## Constraints`。

     网页对话阶段已经确认的产品行为、技术方向、边界 -->

## Requirements

<!-- → prd.md 的 `## Requirements`。必须实现什么 / 必须保持什么 -->

-

## 数据

<!-- → 长期文档：Phase 2 落成 docs/architecture.md 的「数据模型」。
     prd.md 里**不要**再抄一份——那是活文档，两边写会漂。

     实体 / 关系 / 归属（谁能写谁只能读）/ 字段格式约定 / 要不要软删除与审计字段 -->

-

## User Stories

<!-- → prd.md 的 `## User Stories`。从 Task Brief 原样带过来。
     少了一节，Phase 3 就得凭空补，Spec 轴也没法对。没有就写「无」。 -->

-

## Context Pointers

<!-- → prd.md 的 `## Context Pointers`。让本地 Agent 优先阅读的文件、目录、已有相似实现 -->

-
-

## Constraints

<!-- → prd.md 的 `## Constraints`。禁止行为、代码风格、依赖限制、兼容性要求 -->

-

## Out of Scope

<!-- → prd.md 的 `## Out of Scope`。本次明确不做什么 -->

-

## Not yet specified（雾区）

<!-- → prd.md 的同名节。确定在后面、但现在还没法精确表述的东西。
     判据是「能不能现在就把问题写清楚」，不是「能不能现在回答」——
     写不清楚就留在这，不要硬拆成假切片。没有就写「无」。 -->

-

## 验收标准

<!-- → prd.md 的 `## 验收标准`。写「什么算对」；命令写在下面的 `## Verification Plan`。
     每条都要能被一条命令或一个可观察现象判定——「功能正常」不算。
     行为类用 Given/When/Then；非行为类（性能、体积、限额）写阈值。
     Spec 轴会逐条拿它对代码或测试证据。 -->

1.

## Verification Plan

<!-- → prd.md 的 `## Verification Plan`。希望 Agent 运行的测试、lint、typecheck、build
     或手动验证。这时项目还不存在，可以写占位；真实命令由 Phase 2 的 Agent 按
     docs/commands.md 填。 -->

- [ ]

## Testing Notes

<!-- → prd.md 的 `## Testing Decisions`。从 Task Brief 原样带过来。
     要测的 seam / 好测试的标准 / 同库先例。没有就写「无」。 -->

-

## Risks

<!-- → prd.md 的 `## Risks`。你已经知道的风险，让 Agent 重点检查 -->

-

## 术语与决策

<!-- → 长期文档（Phase 2 落盘，别在 prd.md 里重复）：
       术语                     → CONTEXT.md（无条件）
       代码里看不见的约束        → docs/architecture.md 的 `## 约束`（无条件）
       已排除的方案 / 刻意反常规 → docs/adr/，**满足三条准入才写**
                                  （难以撤销 + 没背景会困惑 + 真实取舍）；
                                  不满足的留在 prd.md 的 `## 术语与决策`（快照）

     四类内容，压缩时不能删。缺哪类写「无」。 -->

**术语**

-

**已排除的方案**

-

**刻意偏离常规的地方**

-

**代码里看不见的约束**

-
