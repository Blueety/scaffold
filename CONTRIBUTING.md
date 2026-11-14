# 参与贡献

先读 [`AGENTS.md`](AGENTS.md)——那是这个仓库的硬约束，尤其是这三条：

1. `templates/` 必须**纯 LF**（一个 CR 会让两个 init 脚本产出不同的项目）；
2. `init.sh` 与 `init.ps1` 的项目名接受/拒绝集**完全一致**，产物**逐字节相同**；
3. **本文件里那棵树是唯一真源**，`templates/` 和两个脚本的产物都向它对齐。

生成出来的项目那套规则（任务分级、闸门、审查）**不适用于本仓库**，别把它们当贡献指南。

## 生成出来的项目

下面是骨架生成出来的样子。**这是唯一一份目录树**，`templates/` 和两个 init 脚本的产物都向它对齐；`check-tree.ps1` 会在全仓库找这棵树，多画一份就红。

```
my-project-name/
├── AGENTS.md              # 项目规范（含任务分级和闸门的指针）
├── CONTEXT.md             # 领域词表（空壳，首次术语定案时填）
├── README.md              # 项目说明
├── .gitignore             # Git 忽略规则
├── .gitattributes         # 锁 LF（脚本与钩子在 Linux/macOS 上必须无 CRLF）
├── .scaffold-kinds        # 模板文件分类：mechanism 本地一改就取模板 / content 按内容合并
├── src/                   # 源代码目录（空）
├── scripts/
│   ├── check-gates.sh     # 闸门检查器（plan / prd / journal / 切片 / review / 架构 / [DEBUG- 残留）
│   └── check-gates.awk    # 上面那个的判定逻辑（每个文件一次进程，见文件头）
├── .githooks/
│   ├── pre-commit         # 提交前调 check-gates.sh（并校验闸门文件本身没被偷偷改过）
│   ├── pre-merge-commit   # 合并提交走同一条检查（git 合并时不调用 pre-commit）
│   └── pre-push           # 推送前跑一次全量自查（cherry-pick / rebase / am 没有钩子入口）
├── docs/
│   ├── architecture.md    # 架构说明（活文档：模块/接口/数据模型/数据流）
│   ├── commands.md        # 命令说明
│   ├── pitfalls.md        # 易错点记录
│   ├── adr/
│   │   └── README.md      # 决策记录规范（为什么这么做）
│   └── agents/
│       ├── 架构师.md       # 架构师角色提示词
│       ├── 执行者.md       # 执行者角色提示词
│       └── 任务分级.md      # 档位判定：6 条信号 + 4 条升级规则
├── tasks/
│   ├── README.md          # 任务目录说明
│   └── _template/         # 任务模板
│       ├── prd.md
│       ├── plan.md
│       ├── journal.md
│       ├── review.md      # 审查裁决单（T2 / T3 必填）
│       └── slice.md       # 大需求拆切片时用（也承载决策条目）
└── skills/
    ├── bug-fix/
    │   └── SKILL.md       # Bug 修复流程（含闸门 A / B）
    ├── pre-review/
    │   └── SKILL.md       # 提交前双轴审查
    ├── receiving-review/
    │   └── SKILL.md       # 处理审查意见（防表演式附和 / 盲从）
    ├── self-audit/
    │   └── SKILL.md       # 一致性走查（活文档 vs 现实）
    ├── refactor/
    │   └── SKILL.md       # 重构：先造行为安全网，再改结构
    ├── research/
    │   └── SKILL.md       # 外查一手资料（后台子 agent + 带引用的 md）
    └── tdd/
        └── SKILL.md       # 测试驱动（seam 先约定）
```

## 改完要跑

`check-tree.ps1` 校验四样一致：上面那棵树、`templates/` 的实际内容、`init.sh` / `init.ps1` 实际生成的结果，以及两个脚本的产出逐字节相同（每个产物还要与对应模板替换占位符后逐字节相同）。文件名一致不代表内容一致——多一个换行、编码坏了、只在一边做的替换，都会让两个脚本产出不同而文件名分毫不差，所以逐文件比 SHA256。

```powershell
# Windows（权威检查：CONTRIBUTING 树 == templates/ == 两个脚本产物）
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1

# 改过闸门检查器或更新器时，另跑对应验收
bash scripts/fixtures/gate-test.sh     # 闸门判据，约 20–30 分钟
bash scripts/fixtures/update-test.sh   # 更新器，约 2–4 分钟
bash scripts/fixtures/name-test.sh     # 项目名接受集，约 1 分钟（没有 PowerShell 的机器会跳过）
# 项数不写在这里：它每加一条断言就漂一次（闸门 check_doc_counts 会拦）。
# 真实数字看各自的收尾输出（PASS n / FAIL m）。
```

只改了 `templates/` 里任何东西（哪怕一行文档）时，第一个会红的是 `gate-test.sh` 的 **`G-pristine`**：它在全新生成的项目上跑全量与 `--staged`，要求**零违规**。这条是为了兜「模板里新增了一个会被判断链的示例名 / 一句会被判成占位符的话」——那种错只有真的生成一个项目才看得见。

提交时 `.githooks/pre-commit` 会自动跑第一项（全量，约 20 秒）。被拦下就修，**不要**用 `git commit --no-verify` 绕过。

非 Windows 机器跑不了 `check-tree.ps1`（脚本自身拒绝非 Windows，`exit 3`，与有没有 `pwsh` 无关），那半边由 CI 覆盖。三组 job 每次 push 都跑：

| 任务 | 跑什么 | 为什么是这个平台 |
|---|---|---|
| `windows` | `check-tree.ps1` 全量 + 三个 fixture | 唯一能做「树 vs 两脚本产物」全量比对的平台 |
| `linux` | `templates/` vs `init.sh` 产物逐字节比对 + 三个 fixture（项目名一致性那项会跳过） | 覆盖 GNU 工具链；比对前按项目名展开占位符 |
| `macos` | 用系统 `/bin/bash`（3.2）生成项目，再用系统 `/bin/sh` 跑闸门 | 证明生成的项目不依赖 bash 4。macOS 的 `/bin/sh` 是 bash 3.2 的 POSIX 模式；Linux 的 `/bin/sh` 是 dash，会死在数组语法上 |

分发的 sh 脚本不许用进程替换 `< <(...)`：macOS 的 `/bin/sh` 会让整个文件解析失败，闸门一行都跑不到。`gate-test` 的 `G-tpl` 静态拦这条，`G-mb` 拦 awk 里的多字节方括号（Windows 的 gawk 按字节比，会把中文路径从中间切开）。

## 提交信息

一个提交一件事，写清**为什么**（不是「改了什么」——`git diff` 已经说了）。修缺陷时带上复现方式。

## 许可

提交即表示同意以 [MIT](LICENSE) 发布你的贡献。
