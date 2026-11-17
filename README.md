<div align="center">

# Vibecoding 工作流脚手架

`scaffold` —— 一条命令生成项目骨架，骨架里带一套让 AI 按流程干活、并且能被机器检查的规则。

[English](README.en.md) | 简体中文

[![CI](https://github.com/Blueety/scaffold/actions/workflows/check.yml/badge.svg)](https://github.com/Blueety/scaffold/actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)
![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-informational)
![Runtime deps](https://img.shields.io/badge/runtime%20deps-none-success)

![闸门演示：提交被拦下，补上内容后通过](assets/demo.svg)

<sub>真实终端输出：任务计划的「目标」为空，提交被拦下；补上后通过。</sub>

</div>

和 AI 一起写代码，真正崩掉的地方很少是模型不够强：跳过计划直接改代码、验证只说「应该可以」、计划写一套实现另一套、上周踩过的坑这周再踩一遍。各种 prompt 模板和规范文档靠模型自觉；这里的规矩尽量做成**能跑的检查**——钩子直接拒提交，不是再提醒它一遍。

生成出来的是 markdown 和纯 POSIX sh：项目规范与角色提示词、七个流程 skill、五份任务模板、闸门检查器（`check-gates.sh` + `.awk`）、三个 git 钩子。没有语言、框架和依赖，技术栈你自己装，骨架只约定「AI 按什么流程干活」。

它假设你能派独立子 agent（Claude Code、Codex CLI，或任何能开子会话的编排器）：写计划的人和实施的人不共享上下文，这是整套设计的支点。没有这个原语的编辑器也能用其余部分，但那一条只能靠人自觉。

你要做的只有三件事：生成项目、把第一句话交给 Agent、在「计划批准」和「提交」两处看一眼。其余由 Agent 按项目里的 `AGENTS.md` 执行。

## 目录

- [闸门到底拦什么](#闸门到底拦什么)
- [什么时候别用](#什么时候别用)
- [开始](#开始)
- [前十分钟](#前十分钟)
- [对 Agent 说什么](#对-agent-说什么)
- [三件容易踩的事](#三件容易踩的事)
- [更新已生成的项目](#更新已生成的项目)
- [其余文档](#其余文档)

## 闸门到底拦什么

不是清单，是拒绝。顶上那张图是真终端输出：`plan.md` 的「目标」为空，`pre-commit` 钩子直接拒掉这次提交，报出是哪个文件的哪个字段；补上再提交就过。

同一时刻还会跑这些检查：`journal.md` 的验证结果必须有实际内容、不许写「应该可以」；`journal.md` 的每条提醒必须标去向（`docs` / `adr` / `memory` / `journal`）；`docs/architecture.md` 的模块表与实际 `src/` 目录双向比对；`[DEBUG-` 残留；`src/` 下动到四个以上文件却没声明档位，按低报拒掉。

在这一切之前，最贵的那道闸门是人：修 bug 在形成根因假设之前，必须有一条**已经对这个 bug 变红过**的命令。

## 什么时候别用

提前划清，免得装完才发现不合适：

- **要英文文档的话**：英文版只有 [`README.en.md`](README.en.md)。`INTRO.md`、`WORKFLOW.md`、`CONTRIBUTING.md`，以及生成出来的全部文档、任务模板、skill、角色提示词、闸门报错，都是中文。团队读不了中文，就先按翻译项目算，或者干脆别用。
- **一次性脚本、几十行的实验**：整套流程比活本身大。
- **验证只能靠人眼、又建不出客观信号的项目**：流程的骨架是闸门，没有能变红的命令就没有闸门。视觉类项目可以进——截图像素基线也是客观信号。
- **想完全无人值守跑**：两个检查点是人工闸门，设计上不接受预先授权。
- **没有独立子 agent 原语**：任务目录和闸门照用，但「计划与实施换人」只能靠人自觉。

也不必一次用全：只用 `tasks/` + 闸门也算用上了。

## 开始

需要 `git`；Windows 上有 PowerShell 5.1+，Linux / macOS / WSL 上有 `bash`（3.2 即可）、`awk`、`sed`。生成出来的项目不需要 Node、Python 或任何运行时。

```bash
git clone https://github.com/Blueety/scaffold.git
cd scaffold
bash init.sh my-project-name
```

Windows 用 `.\init.ps1 my-project-name`。默认执行策略（`Restricted`）下这条会报「禁止运行脚本」，换这行：

```powershell
powershell -ExecutionPolicy Bypass -File .\init.ps1 my-project-name
```

脚本在当前目录建 `my-project-name/`，同时 `git init`、写 `core.quotepath=false`、把 `.githooks/` 挂成钩子目录。没有 `install` 步骤，这不是 npm 包。

项目名允许字母、数字、`.`、`_`、`-` 和非 ASCII 字符（中文等，须是合法 UTF-8）；不能是 `.` / `..` / `.git`（不分大小写），不能以 `-` 开头或以 `.` 结尾，不能是 Windows 保留设备名（`CON` / `PRN` / `AUX` / `NUL` / `COM1`–`COM9` / `LPT1`–`LPT9`），也不能含空格、引号、路径分隔符、控制字符或 shell 元字符。

## 前十分钟

最短的「看到它到底在干什么」的路径：

1. `bash init.sh my-project-name && cd my-project-name` —— 骨架不替你提交，第一个提交是你的。
2. 打开生成项目里的 `AGENTS.md`。整套流程就在那里，Agent 每轮读的就是它。
3. 让它改**一个**文件，看它声明档位 T0 后直接动手：没有计划，不打断。
4. 让它碰 2–3 个文件：必须先落 `tasks/<日期>-<简述>/plan.md`，里面带验证命令。
5. 打开 `tasks/` 下刚生成的那份 `plan.md`，删掉「目标」那行再 `git commit`——钩子会拒掉。这就是它。

## 对 Agent 说什么

进到新项目里，把流程要求和需求一起交给它：

```
读 AGENTS.md，按 tasks/README.md 建任务目录，先写 prd.md 和 plan.md，别直接改代码。
需求：<一句话>
```

T0（改一两个文件、行为不变）可以直接做；T1 以上要落 `plan.md`，你批准之后它才会派实施子 agent。之后你只需要看两处：计划里的验证命令是不是真能跑，以及 `journal.md` 的验证结果是真实输出还是「应该可以」。

## 三件容易踩的事

**代码不在 `src/`。** 闸门默认只数 `src/` 下的模块和文件。技术栈把代码放在 `app/`、`web/`、`cmd/` 的话，用 `MODULE_ROOT=app` 跑闸门，或改 `scripts/check-gates.sh` 里那行默认值。不改的话模块表比对和规模底线会空转，闸门只打一条 `[!]` 提示，不拦。

**换了机器钩子失效。** `core.hooksPath` 写在 `.git/config` 里，不随 clone 走。clone 到别的机器后跑一次 `git config core.hooksPath .githooks`，否则钩子根本不执行。

**闸门说「写法不对」。** 机器只认文件第一行的 `<!-- gate -->` 头块，以及 `- **标签**:` 这种半角写法；全角冒号会被判成「没填」。模板是对的，照抄即可——真写歪了，报错会给出该写的样子。

## 更新已生成的项目

脚手架改了之后不用重新生成：

```bash
bash scripts/scaffold-update.sh ../my-project-name           # 预览，不写盘
bash scripts/scaffold-update.sh ../my-project-name --write   # 写盘（不提交）
```

只碰 `templates/` 里出现过的路径，`src/` 和 `tasks/` 一概不动。裁决、冲突现场、全部开关在 [`UPDATE.md`](UPDATE.md)。

## 其余文档

| 想知道什么 | 看哪里 |
|---|---|
| 四段流程全景图、一个任务怎么走、四道闸门、六条关键取舍 | [`INTRO.md`](INTRO.md)，第一次接触从这里开始 |
| 一个任务从需求到提交的逐步操作（Phase 1–4） | [`WORKFLOW.md`](WORKFLOW.md) |
| 生成出来的目录结构（唯一一份，`check-tree.ps1` 守着它） | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| 改这个脚手架本身：跑什么、约束、CI | [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`AGENTS.md`](AGENTS.md) |
| 在网页 AI（GPT / Claude / Gemini）里把讨论整理成任务，再交接给本地 agent | [`web-chat-templates/`](web-chat-templates/README.md) |

有问题、对哪条取舍有不同意见，或者你们的做法不一样——都可以开 issue。

## 许可

MIT，见 [`LICENSE`](LICENSE)。生成出来的项目属于你，没有署名要求。
