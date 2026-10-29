# 个人项目脚手架

一键生成 Vibe Coding 开发系统所需的目录结构和规范文件。

## 用法

### Windows (PowerShell)

```powershell
.\init.ps1 my-project-name
```

### Linux / macOS / WSL (Bash)

```bash
bash init.sh my-project-name
```

脚本会在当前目录下创建 `my-project-name/` 并生成完整目录结构。

## 生成的目录结构

```
my-project-name/
├── AGENTS.md              # 项目规范（含任务分级和闸门的指针）
├── CONTEXT.md             # 领域词表（空壳，首次术语定案时填）
├── README.md              # 项目说明
├── .gitignore             # Git 忽略规则
├── src/                   # 源代码目录（空）
├── docs/
│   ├── architecture.md    # 架构说明
│   ├── commands.md        # 命令说明
│   ├── pitfalls.md        # 易错点记录
│   ├── adr/
│   │   └── README.md      # 决策记录规范（为什么这么做）
│   └── agents/
│       ├── 架构师.md       # 架构师角色提示词
│       ├── 执行者.md       # 执行者角色提示词
│       └── 任务分级.md      # 档位判定：6 条信号 + 3 条升级规则
├── tasks/
│   ├── README.md          # 任务目录说明
│   └── _template/         # 任务模板
│       ├── prd.md
│       ├── plan.md
│       └── journal.md
└── skills/
    ├── bug-fix/
    │   └── SKILL.md       # Bug 修复流程（含闸门 A / B）
    ├── pre-review/
    │   └── SKILL.md       # 提交前双轴审查
    ├── research/
    │   └── SKILL.md       # 外查一手资料（后台子 agent + 带引用的 md）
    └── tdd/
        └── SKILL.md       # 测试驱动（seam 先约定）
```

## 生成后要做的事

1. **初始化技术栈**：在项目目录里运行 `npm init`、`create-next-app`、`uv init` 等。
2. **让 Agent 填写规范**：配置文件就位后，让本地 Agent 读配置文件并填写 AGENTS.md、CONTEXT.md 和 docs/（含把 Task Handoff 里的决策落成 `docs/adr/0001-*.md`）。
3. **提交**：`git add . && git commit -m "init: 项目脚手架 + 技术栈"`

完整流程见 [WORKFLOW.md](WORKFLOW.md)。

## 设计原则

- 模板只写 AI 推不出来的东西。其余写成指针，指向 `docs/`
- 规则必须可检查，不写空话
- **每个流程都有退出门槛**，不是只有步骤清单。见 `docs/agents/任务分级.md`、`skills/bug-fix/SKILL.md` 的闸门 A / B
- 任务有状态（prd/plan/journal），新会话能接续
- 经验沉淀到 `docs/pitfalls.md`，决策沉淀到 `docs/adr/`，术语沉淀到 `CONTEXT.md`——都不留在聊天记录里
- 角色提示词进仓库（`docs/agents/`），不靠每次手动粘贴
- 验证是默认步骤，不是可选项
