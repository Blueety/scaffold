# 个人项目工作流程

从想法到可运行代码的完整步骤。

流程骨架是四段：**Phase 1 网页对话澄清 → Phase 2 终端搭建 → Phase 3 单任务执行 → Phase 4 循环**。每次只改一件事，每件事都有产物，产物落在仓库里而不是聊天记录里。

---

## Phase 1: 想法澄清（网页对话）

> 工具: 浏览器里的 GPT / Claude / Gemini

### Step 1.1: 自由讨论

打开网页对话，聊你的想法。不需要管格式。

可以用 `web-chat-templates/` 里的模板辅助：
- `project-kickoff.md` — 第一次聊新项目，帮你理清想法、需求、验收标准
- `tech-stack-decision.md` — 讨论和确定技术栈（也可以直接在聊天中问）
- `frontend-design.md` — 讨论界面设计和视觉方向（技术栈定下来之后再用，纯后端 / CLI 项目跳过）
- `approach-comparison.md` — 比较不同实现方案

不一定要严格按模板走，关键是把想法聊清楚。

```
我想做一个 XXX，大概的需求是...
```

讨论过程中注意收集四类东西，它们之后会进项目仓库长期维护，而不是跟着聊天记录丢掉：

1. **术语** — 你反复用到的关键词，以及容易混淆的近义词
2. **被排除的方案** — 考虑过但没选的，以及为什么
3. **刻意偏离常规的地方** — 你要求反着来做的，以及理由（否则以后会被「修好」）
4. **代码里看不见的约束** — 合规、对方接口限制、环境限制，附出处

### Step 1.2: 生成 Task Brief

讨论清楚后，用 `web-chat-templates/task-brief.md` 的模板；提示词在 `web-chat-templates/README.md` 的「在网页对话中使用的提示词」一节。只此一处，别复制到别处。

### Step 1.2b: 决定技术栈

讨论需求时顺便问 AI：

```
根据这个项目的需求，推荐技术栈。
给出：语言、框架、包管理器、测试工具。
说明为什么选这些，有没有替代方案。
```

把决定记下来，Phase 2 初始化技术栈时直接用。

```
技术栈决定：
- 语言: TypeScript
- 框架: Next.js
- 包管理: npm
- 测试: Jest
```

不要等到 Phase 2 再想技术栈。那时候你已经在终端里了，来回切换成本更高。

带锁定成本的选择（数据库、认证服务商、部署目标）会被 Phase 2 的 Agent 写进 `docs/adr/`。

### Step 1.2c: 决定前端设计

有界面的项目才做，纯后端 / CLI 跳过。

技术栈定下来后，参考 `web-chat-templates/frontend-design.md`，把界面决策钉死：界面清单和线框图、视觉方向（hex / 字号 / 间距 / 参考物）、组件库、交互与状态、响应式、视觉验收标准。

关键：**不要让 AI 只给形容词**。「现代、简洁、大气」这类词没有信息量，本地 Agent 拿到会自己发挥，结果是它最熟悉的默认长相（居中 hero、紫色渐变、圆角卡片网格）。要么给具体值，要么明确排除。

讨论完的结论按模板收尾那段压缩，和 Step 1.2 的 Task Brief 一起进 Step 1.3 的 Task Handoff。

### Step 1.3: 压缩成 Task Handoff

拿到 Task Brief 后，参考 `web-chat-templates/task-handoff.md` 模板，压缩成 Task Handoff 交接卡。

**压缩规则：删讨论过程，留术语和决策。**

重点保留 Goal、Acceptance Criteria、Constraints。讨论过程的寒暄、试错、来回确认删掉——本地 Agent 不需要你的聊天记录。

但下面四类内容**原样带过来**，不要当成「冗余」删掉：

- 术语
- 已排除的方案
- 刻意反常规的地方
- 看不见的约束

它们之后会写进 `CONTEXT.md` 和 `docs/adr/`，删了就永久丢了。

### Step 1.4: 保存 Task Handoff

把 Task Handoff 保存到一个临时位置，Phase 3 会用到。

可以保存为：
- 浏览器剪贴板（直接复制）
- 或者一个临时文件，比如 `%TEMP%\task-handoff.md` / `/tmp/task-handoff.md`

不要关掉网页对话前没保存，丢了就得重新整理。

---

## Phase 2: 项目搭建（终端 + 本地 Agent）

> 工具: PowerShell / Bash + Claude Code / Codex / OpenCode

### Step 2.1: 创建项目脚手架

```bash
# 进入你的工作目录
cd <你的项目工作目录>

# 跑初始化脚本（在本仓库目录下）
bash init.sh my-project-name          # Linux / macOS / WSL
.\init.ps1 my-project-name            # Windows PowerShell

# 进入项目
cd my-project-name
```

此时项目只有空壳目录和模板文件，还没有源代码。

生成的骨架见 [`README.md` 的「生成的目录结构」](README.md#生成的目录结构)——那里是**唯一**一份目录树，由 `scripts/check-tree.ps1` 校验它与 `templates/` 的实际内容一致。

### Step 2.2: 初始化技术栈

根据你要做的项目，初始化实际的技术栈。这时候项目里才会出现 package.json、配置文件等。

常见示例（在项目目录内执行）：

```bash
# Next.js 项目（在当前目录初始化）
npx create-next-app@latest . --typescript --tailwind --app

# React + Vite 项目
npm create vite@latest . -- --template react-ts

# Node.js 后端
npm init -y
npm install express typescript @types/express

# Python 项目
uv init
uv add fastapi uvicorn
```

注意：有些框架的初始化命令会询问覆盖已有文件，选"否"保留脚手架文件。

初始化完后，项目里就有了 package.json（或 pyproject.toml）、配置文件、依赖目录。

### Step 2.3: 让 Agent 填写规范文件

空项目 Agent 没东西可读。技术栈初始化完、配置文件就位后，再让 Agent 帮你填。

对本地 Agent 说：

```
这个项目刚初始化完，技术栈是 [你说的具体技术栈]。

请帮我完成五件事：

1. 先阅读项目里的配置文件（package.json、tsconfig.json 等），
   了解实际用了什么工具和命令。

2. 填写 AGENTS.md 里的 Commands 部分（写实际命令，不要猜）。

3. 填写 docs/commands.md（列出所有验证命令和何时跑什么）。

4. 填写 docs/architecture.md（根据当前目录结构画出模块划分）。

5. 把下面这份 Task Handoff 里的术语与决策，落成长期文档：
   - 术语 → CONTEXT.md
   - 符合「难以撤销 + 没有背景会让人困惑 + 是真实取舍的结果」三条的决策 → docs/adr/0001-*.md
   - 只影响实现的细节不用写 ADR

   如果哪一条信息不足以判断，列出来问我，不要替我猜。

[粘贴 Step 1.3 的 Task Handoff]
```

Agent 会读你的配置文件，写出**实际命令**，不是猜的。

另外，`skills/` 目录里有四个流程模板：

| skill | 什么时候用 |
|---|---|
| `bug-fix` | 修 bug。核心是闸门 A：进入根因假设前必须先有一条能对**这个** bug 变红的命令 |
| `pre-review` | 提交前审查。Standards / Spec 双轴，分开报告不合并 |
| `tdd` | 写测试。写之前先书面列出 seam 并确认 |
| `research` | 外部一手事实挡路（第三方 API / 规范原文 / 版本声明）。派后台子 agent，产出带引用的 md；结论进 `CONTEXT.md` / ADR，文件本身过期即删 |

```
请参考 skills/bug-fix/SKILL.md 的流程来修这个 bug。
```

`docs/agents/` 里是角色提示词和流程细则（`架构师.md` / `执行者.md` 是角色；`任务分级.md` 是判档规则），不用再手动粘贴：

```
请阅读 docs/agents/执行者.md，按它的要求工作。
```

角色和 skill 不是一回事：角色是「谁在干活」（`docs/agents/`），流程是「怎么干」（`skills/`）。所以 `pre-review` 只有 `skills/pre-review/SKILL.md`，没有对应的角色文件——它是一次审查动作，不是一个人设。

### Step 2.4: 初始提交

init 脚本已创建 git 仓库，直接提交即可：

```bash
git add .
git commit -m "init: 项目脚手架 + 技术栈初始化"
```

到这里项目搭建完成。现在你有了：技术栈、项目规范（AGENTS.md）、领域词表（CONTEXT.md）、决策记录目录（docs/adr/）、文档目录（docs/）、任务目录（tasks/）、流程 skill（skills/）。

接下来进入 Phase 3，建议从小任务开始：修一个 bug、加一个小功能、补一个测试。

---

## Phase 3: 第一个任务（本地 Agent）

> 工具: Claude Code / Codex / OpenCode

### Step 3.1: 建任务目录

```bash
# 格式: tasks/<日期>-<简述>
mkdir tasks\2026-08-04-add-login
```

小改不用建目录，判定标准见 `docs/agents/任务分级.md`。T0 级别（单文件、无行为变化、无调用方）直接改直接跑测试。

### Step 3.2: 写 prd.md

把 Task Handoff 复制到 `tasks/<日期>-<简述>/prd.md`。
按 prd.md 模板逐项填写：Goal、Requirements、User Stories、Out of Scope、Not yet specified、Constraints、Context Pointers、Testing Decisions、Risks、Verification Plan。

`Not yet specified` 是**雾区**：确定在后面、但现在还没法精确表述的东西写在这里，**不要**硬拆成假切片。判据是「能不能现在就把问题写清楚」——能就开切片或决策条目，不能就留在这。每解掉一个决策，回来看一次这节。详见 `tasks/README.md`。

「档位」那一行**留空**——网页对话的 AI 没见过代码，判不了。由本地 Agent 在 3.3 只读分析后填。

```bash
# 例如
copy task-handoff.md tasks\2026-08-04-add-login\prd.md
```

### Step 3.3: 给 Agent 第一条消息

不要让 Agent 直接实现。先让它读代码：

```
下面是一份从网页对话整理出的 Task Handoff。
请先不要修改文件。

你的第一步：
1. 阅读相关代码和项目规范。
2. 先读 CONTEXT.md，之后描述和命名统一用里面的词；术语冲突当场指出。
3. 特别注意 prd.md 中的 Context Pointers 部分，优先阅读这些文件。
4. 找出现有相似实现。
5. 按 docs/agents/任务分级.md 声明档位，只落一行。
6. 总结你理解的任务、要改的文件、风险和验证命令。
7. 若某条关键信息只能从外部一手来源拿到，先按 skills/research/SKILL.md 落一份 research 文件，不要在主线程里读。
8. 等我确认后再实施。

[粘贴 prd.md 内容]
```

Agent 应该给出这样一行：

```
档位: T1 — 2 文件 / 0 调用方 / 行为有变 / 无覆盖测试 / 预估 40 行
```

档位是**建议值**，你可以一句话覆盖（`T3，我不确定根因`）。

#### 如果是修 bug：闸门 A

类型轴 = bug 时，在进入根因假设之前，Agent 必须先建出一条**能对这个 bug 变红**的命令，并实跑一次给你看输出。

```
先别猜根因。按 skills/bug-fix/SKILL.md 的 Phase 1 做：
构造一条能对这个 bug 变红的命令（测试 / curl / 无头浏览器 / 一次性 harness 都行），
实际跑一次，把调用和输出（脱敏后）贴给我。
拿不出这条命令就先停下，告诉我你试了哪些构造方式、缺什么。
```

拿不出这条命令就退回这一步。规模小也一样——改一个字符修一个偶发竞态，照样需要它。

### Step 3.4: 审阅计划

Agent 应该输出一个计划。检查：

- [ ] 档位声明与实际文件范围一致
- [ ] 文件范围合理
- [ ] 没有不必要的依赖
- [ ] 包含了测试，且 `## 测试 Seam` 一节填了（要测的 seam、公开接口是什么、为什么选它）
- [ ] 列出了验证命令
- [ ] 修 bug 时：`## 修 bug 时必填` 一节填了（回路命令、已实跑输出、3–5 个带预测的假设）

没问题就说"开始吧"。有问题就纠正。

### Step 3.5: 保存计划

让 Agent 把计划写入文件：

```
请把你刚才的计划保存到 tasks/<日期>-<简述>/plan.md。
```

下次会话接手时，Agent 先读 plan.md 就知道做到哪了。

### Step 3.6: 实现

```
按刚才确认的计划实施。保持最小改动，不要重构无关代码。
每完成一个逻辑步骤后运行验证。

写测试按 skills/tdd/SKILL.md：先红后绿，一次一个切片，
不要先把测试全写完再写实现。

调试日志统一加 [DEBUG-xxxx] 前缀，方便收尾清除。
```

### Step 3.7: 验证

不要接受"应该可以"。让 Agent 跑检查：

```
运行你计划里的验证命令。
如果 docs/commands.md 中有相关命令也一并运行。
如果有失败，先解释原因再修复。

修 bug 的话，第一步是重跑 Phase 1 那条回路命令，
把原症状已经消失的证据贴出来，然后再跑测试和 lint。
```

### Step 3.7b: 闸门 B — 清理

提交之前必须过。让 Agent 自证：

```
提交前确认并贴出命令输出：
1. grep [DEBUG- 没有残留
2. 一次性原型 / 临时脚本已删除
3. 如果新建了文件却只是为了调试，已经清掉
```

### Step 3.8: 审 diff

```bash
git diff
```

让 Agent 按 `skills/pre-review/SKILL.md` 出双轴报告：

```
请按 skills/pre-review/SKILL.md 审查从 <固定点> 到 HEAD 的 diff。
两轴分别报告，不要合并，不要跨轴排序。
```

你会拿到两块：

- **Standards** — 是否符合仓库写明规范 + 12 条坏味道基线 + 各维度检查
- **Spec** — 对照 prd.md 查：缺失 / 部分实现、范围蔓延、实现可疑

你自己也要看：

- [ ] 只有你预期的文件被改了
- [ ] 没有无关的格式化改动
- [ ] 没有遗留调试代码
- [ ] 有测试

### Step 3.9: 提交

```bash
git add .
git commit -m "feat: 添加 XXX 功能"
```

修 bug 时，commit message 里加一句根因（那个最终被证实的假设），让下一个调试的人能学到东西。

**一个任务目录对应一个主要提交。** 多切片任务里，每个切片完成时提交一次，把 SHA 回填到该切片文件的「主要提交」，状态改成 `completed`。

这条不只是习惯：Step 3.8 的双轴审查要「从固定点到 HEAD 的 diff」，而固定点默认就是**上一个任务的主要提交**。粒度乱了，审查范围就无从确定。

### Step 3.10: 记录经验

问 Agent：

```
这次任务有没有可以沉淀的规则或决策？
1. 会复用的规则 → docs/pitfalls.md
2. 同时满足下面三条的决策 → docs/adr/NNNN-slug.md（编号取现有最大值 +1）
   - 难以撤销
   - 没有背景会让人困惑
   - 是真实取舍的结果
只列会复用的，不要写泛化建议。不符合 ADR 三条的不要硬写。
```

### Step 3.11: 写执行日志

让 Agent 把这次任务的关键信息写入文件：

```
请把这次任务的执行日志保存到 tasks/<日期>-<简述>/journal.md。
内容包括：目标、主要提交的 SHA、改了哪些文件、验证结果、遇到的问题、下次注意什么、涉及的 ADR 编号、下一步。
```

这步的作用：下次会话接手时，Agent 读 journal.md 就知道前因后果，不用从头解释。

---

## Phase 4: 重复

每个新任务走一遍：

```
1. 判定档位（T0 免检，直接改）
2. 建 tasks/<日期>-<简述>/ 目录，从 tasks/_template/ 复制模板，写 prd.md
3. Agent 读代码 → 声明档位 → 给计划 → 你确认 → 存 plan.md
   修 bug 时：先过闸门 A（能变红的命令）
4. Agent 实现 → 跑检查（含 docs/commands.md）→ 过闸门 B（清理）
5. Agent 出双轴审 diff → 你确认
6. commit → 记录经验（pitfalls / ADR）→ 写 journal.md
```

大需求装不进单个会话时，先拆成多个任务文件 + 声明依赖，再做：

```
tasks/2026-08-04-add-login/
  prd.md            # 总目标
  01-schema.md      # 被谁挡: 无
  02-api.md         # 被谁挡: 01
  03-ui.md          # 被谁挡: 02
```

每个切片从 `tasks/_template/slice.md` 复制，字段（档位 / 优先级 / 完成后可以看到什么 / 完成标准 / 被谁挡 / 状态 / 主要提交）在模板里，`scripts/check-gates.sh` 会校验。

拆分时守住三条：

- **切片只装「已经知道怎么做」的活。** 某一步本质是待决策的问题（选型、取哪个口径、要不要做、做到多大）→ 先落一条**决策条目**（问题 + 结论 + 依据），拿到结论再拆执行切片。别把问题硬写成切片。
- **判据是「能不能现在就把问题精确表述出来」**，不是「能不能现在回答」。表述不出来 → 留在 `prd.md` 的 `## Not yet specified`（雾区），不要预切成切片大小的假切片。
- **切片必须垂直**（贯穿 schema / API / UI / 测试），不是一个横向的层；每个切片做完都能独立演示或验证。

**优先级 ≠ 可执行性。** P0 表示重要，依赖表示**现在能不能做**。所有前置都做完的切片叫**任务前沿**——下一个该做的就是前沿里优先级最高的那个。

每解掉一个决策条目，回来看一次雾区有没有能落成新切片 / 新决策条目的。

规则见 `tasks/README.md`。

---

## 快速参考

| 阶段 | 工具 | 产出 |
|---|---|---|
| 想法 | 网页对话 | Task Handoff 交接卡（含术语与决策） |
| 搭建 | 终端 + init 脚本 + 本地 Agent | 完整项目：技术栈 + AGENTS.md + CONTEXT.md + docs/ + tasks/ + skills/ |
| 任务 | 本地 Agent | prd.md → plan.md → diff → commit → journal.md |
| 外查 | 后台子 agent（`skills/research`） | `tasks/<日期>-<简述>/research/<slug>.md`（每条论断带一手链接） |
| 审查 | 双轴 pre-review + 你的眼睛 | 验证过的变更 |
| 记录 | pitfalls.md / docs/adr/ / CONTEXT.md | 下次能用的经验和决策 |

### 闸门清单

| 闸门 | 位置 | 判据 | 谁执行 |
|---|---|---|---|
| 档位声明 | 3.3 | 一行，6 条信号，可被用户覆盖（`docs/agents/任务分级.md`） | Agent 声明 + 人确认；`check-gates.sh` 验格式 |
| 闸门 A 反馈回路 | 3.3 末尾，仅修 bug | 一条**已实跑过**、能对**这个** bug 变红的命令 | 人确认；`check-gates.sh` 验字段非空 |
| seam 确认 | 3.4，涉及写测试 | 书面列出要测的 seam 并确认 | 人确认；`check-gates.sh` 验三行要么全填要么全空 |
| 闸门 B 清理 | 3.7b | `grep [DEBUG-` 无残留，一次性脚本已删 | **`check-gates.sh` 自动**（临时脚本那条仍需人看） |
| 双轴不合并 | 3.8 | Standards 与 Spec 分别出结论，不跨轴排序 | 人确认 |

前三条的「已实跑过」「合理」这类判断，机器只能验字段非空，验不了内容——别把检查通过当成闸门通过。

### 闸门检查器

`scripts/check-gates.sh` 把能机器判定的那部分固化下来：

```bash
scripts/check-gates.sh              # 全仓库自查
scripts/check-gates.sh --staged     # 只查已暂存内容（pre-commit 钩子用）
```

它随项目分发，并在 `git init` 后被 `core.hooksPath` 挂成 pre-commit 钩子——所以闸门 B 是**自动**过的，不靠自觉。临时绕过用 `git commit --no-verify`。

`--staged` 检查的是**索引里的内容**，不是工作区：「先 `git add` 了坏版本、事后又把文件改好」不会放行；反过来工作区脏但索引干净也不会误拦。

---

## 紧急恢复: Agent 跑偏时

如果 Agent 改错文件或卡住了：

```
停止实现。进入恢复模式。

请先不要修改文件，完成以下分析：
1. 当前任务原目标是什么。
2. 当前 diff 改了哪些文件。
3. 哪些改动和目标相关，哪些可能无关。
4. 当前失败的具体现象是什么。
5. 最可能的根因是什么。
6. 你建议保留、修改、撤销哪些改动。

注意：不要回滚用户已有改动。
```

然后决定：修复、撤销 Agent 的改动、还是开新会话重做。
