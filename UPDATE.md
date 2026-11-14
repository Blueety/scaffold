# 更新已生成的项目

> 脚手架在演进，已经生成的项目**不用重新生成**。这个脚本按文件把新模板推进去，保留本地改动。
>
> 参考手册。第一次用只看「两条命令」和「它碰什么、不碰什么」两节就够了，其余按需查。

## 两条命令

```bash
bash scripts/scaffold-update.sh ../my-project-name           # 预览，不写盘
bash scripts/scaffold-update.sh ../my-project-name --write   # 真的写
```

## 它碰什么、不碰什么

逐文件三方合并：**项目现状** × **生成时的旧模板** × **当前模板**。

| 情况 | 结果 |
|---|---|
| 项目没动过这个文件 | 直接升级到新模板 |
| 项目改过、模板没动 | 原样保留（`mechanism` 类除外：本地一改就取模板版，见下） |
| 两边都改过 | `templates/.scaffold-kinds` 标成 `mechanism` 的取模板版（本地改动备份到现场）；其余走 `git merge-file`，合不拢就写冲突标记并返回 1 |
| 模板新增 | 加进去；项目已有同名文件则跳过，不覆盖（`mechanism` 类除外） |
| 模板删掉 | 项目没动过就删，改过就保留并报告 |

`mechanism` 的判定只看「本地 vs 模板」：两者不一致就取模板版，不管模板那一版动没动。理由是这类文件的正确状态就是模板原样，本地改动应当报上游；把「模板没动」当作放行条件，等于本地悄悄改过的钩子每次同步都原样通过。

只碰 `templates/` 里出现过的路径——`src/`、`tasks/<任务>`、`.git/` 一概不动。脚本不做提交，写完自己看 `git diff`。

## 写盘前后的三件事

**目标仓库有未提交改动时拒绝写盘**（退出码 2）：脚本写的是模板路径，你改的可能是同一批文件，混在一起提交就说不清谁写了什么。先提交或 stash，或加 `--force`。

**写盘时留现场**：`<项目>/.git/scaffold-work/<时间戳>/` 里有 `MANIFEST`（这次每条动作一行）、`REVISIONS`（base / new / 基线来源），冲突文件另有 `.ours` / `.base` / `.theirs`。放在 `.git/` 下是为了不进 `git status`——不用改项目的 `.gitignore`。

**写盘后会跑一次目标仓库的闸门**，报出存量违规数与分布，并记进 `.scaffold-version`（下次对比增减）。新装进去的规则对历史文件是全红的，这个数字应该在落盘那一刻就知道，而不是等你启用钩子才发现。

## 基线（旧模板）从哪来

按优先级：

| 来源 | 怎么来的 |
|---|---|
| `--from <sha>` | 你直接指定 |
| `.scaffold-version` 的 `commit=` | 上次更新成功后写入 |
| 按内容比对 | 拿项目文件对脚手架历史，挑最像的版本，报一致率 |

第三条是给**这个功能出现之前**生成的项目用的自举路径。一致率 < 80% 时**不合并**（退出码 2）：挑错版本会把「模板演进」和「本地改写」混成同一批冲突，比不合并危险得多。三条出路：

```bash
bash scripts/scaffold-update.sh ../p --from <sha>            # 知道就指定
bash scripts/scaffold-update.sh ../p --adopt-baseline        # 只记基线，不合并
bash scripts/scaffold-update.sh ../p --adopt-baseline <sha>
bash scripts/scaffold-update.sh ../p --accept-guess          # 确认可用，硬着头皮合
```

`--adopt-baseline` 专治「脚手架历史被重写过、按内容比对不可信」——写完基线，之后每次同步都从它算起。选中的来源会记进 `baseline_source=`，下次不再重猜。

## 三类文件

| 分类 | 例子 | 本地与模板不一致时 |
|---|---|---|
| `mechanism` | `docs/agents/*`、`skills/*`、`scripts/check-gates.*`、`.githooks/*`、`tasks/_template/*` | 取模板版；本地改动备份到现场。不论模板那一版动没动——这类文件本地改了应当报上游，而不是留着 |
| `content` | `AGENTS.md`、`docs/commands.md`、`docs/pitfalls.md` | 照常三方合并；想免掉反复冲突用下面的裁决 |
| 未列出 | 其余 | 默认三方合并，和不分类时一样 |

清单在 `templates/.scaffold-kinds`，只影响更新器，闸门不读它。

## 裁决：让「本地说了算」的文件不再反复冲突

`docs/commands.md`、`docs/pitfalls.md` 这类文件，模板只给骨架、项目填满内容。它们和模板的差异是**永久分歧**，不是待合并的临时差异——不记下来，每次同步都得重新判一遍，而且模板一合并就可能把项目内容拼进去。

```bash
# 这个文件永远保留项目版本
bash scripts/scaffold-update.sh ../p --write --keep-local docs/commands.md

# 这个文件取并集：模板新增的行追加进来，本地一行不删
bash scripts/scaffold-update.sh ../p --write --union .gitignore
```

裁决记在 `.scaffold-version` 的 `decision` 段，附上当时的模板 blob。之后：

- 模板没再变 → 直接跳过，不再打扰
- 模板又变了 → `keep-local` 会提示「重新判断」（内容不动，不会偷偷合并）
- `union` 会把新增的行追加进来，本地内容一条不丢

预览时裁决同样生效（只是不落盘），所以可以先看效果再决定要不要 `--write`。

## 其他开关

| 开关 | 作用 |
|---|---|
| `--diff` | 预览时打印改动内容；跳过的同名文件也给两边行数 |
| `--json <路径>` | 结果写成 JSON（基线、来源、每文件动作、闸门数），给 CI 用 |
| `--refresh-gate-count` | 只重跑闸门、更新计数，不合并（清零常跨几个工作日） |
| `--quiet` | 不打印动作清单 |
| `--force` | 目标仓库脏也写 |

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File scripts\scaffold-update.ps1 ..\my-project --write
```

`PATH` 里的 `bash.exe` 常常是 System32 下的 WSL 桩，跑不了 Windows 路径，报错还会被控制台代码页吃成一行 `?`。这个包装器会先找 Git for Windows 自带的 bash，找不到就说清楚。脚本启动时也会自检 `find` 是不是 POSIX 的——Windows 的 `find.exe` 抢在前面时什么都不输出，会把「找不到文件」误读成别的结论。

脚手架 `templates/` 有未提交改动时照样能跑（「新版」取工作区），但**不记录基线提交**——下次更新会重新比对，等你把脚手架提交了就自愈。

这个**更新器**需要 bash 4 以上（macOS 自带的是 3.2，用 `brew install bash` 装的那个）。**生成出来的项目不需要**——`scripts/check-gates.sh` 只用 bash 3.2 就有的语法，macOS 上 `/bin/sh` 直接能跑（CI 的 macos 任务就是在验这条）。
