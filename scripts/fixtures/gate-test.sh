#!/usr/bin/env bash
#
# 闸门检查器的验收 fixture。覆盖的是「改过就会退化的那几条判据」，不是行覆盖率：
#   G1  规模底线：仓库里有 T2 任务时，纯代码提交不能靠它短路
#   G2  plan.md 不写「目标」要报
#   G3  纯重命名（归档）不算改动存活；但拍平归档必须报
#
# 用法：bash scripts/fixtures/gate-test.sh
# 退出码 0 = 全过。需要 git 与 bash 4+。

set -u
trap '' PIPE

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT="$REPO_ROOT/init.sh"
B="${BASH:-bash}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
has() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else no "$3"; fi; }
not() { if printf '%s' "$2" | grep -qF -- "$1"; then no "$3"; else ok "$3"; fi; }

# 一个生成出来的项目 + git 仓库。安装钩子但用 -c core.hooksPath=/dev/null
# 绕过它：fixture 要造「闸门会判红」的历史状态，不能让钩子拦在造数据的路上。
new_project() {
    local d="$1"
    mkdir -p "$TMP/gen"
    ( cd "$TMP/gen" && "$B" "$INIT" "$(basename "$d")" >/dev/null 2>&1 ) || return 1
    cp -r "$TMP/gen/$(basename "$d")" "$d" || return 1
    rm -rf "$TMP/gen/$(basename "$d")"
    ( cd "$d" && git init -q . && git add -A \
      && git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm init ) >/dev/null 2>&1
}

wip_commit() {
    ( cd "$1" && git add -A \
      && git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm wip ) >/dev/null 2>&1
}

# 跑 --staged。cwd 无关：脚本自己找仓库根。
run_staged() {
    ( cd "$1" && "$B" scripts/check-gates.sh --staged 2>&1 )
}

# 一份能过闸门的 plan.md，$2 可选地留空「目标」
plan_text() {
    local tier="$1" empty_goal="${2:-0}"
    printf '# 实施计划\n\n## 任务概要\n\n'
    printf -- '- **档位**: `%s — 2 文件 / 0 调用方 / 行为有变 / 无覆盖测试 / 预估 40 行`\n' "$tier"
    printf -- '- **类型**: `加功能`\n'
    if [ "$empty_goal" = "1" ]; then
        printf -- '- **目标**:\n'
    else
        printf -- '- **目标**: 让 X 在 Y 时不再报错\n'
    fi
    printf -- '- **相关文件**:\n  - src/a.sh\n'
    printf -- '- **验证命令**: `bash scripts/check-gates.sh`\n\n'
    printf '## 步骤\n\n| # | 步骤 | 文件范围 | 风险 | 验证 |\n|---|---|---|---|---|\n'
    printf '| 1 | 改 a | src/a.sh | 低 | 跑闸门 |\n\n'
    printf '## 确认\n\n- [x] 已确认\n'
}

echo "== G1: 规模底线不被在飞任务短路 =="
P="$TMP/g1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-01-big"
plan_text T2 > "$P/tasks/2026-01-01-big/plan.md"
printf '# 需求\n\n## 档位\n\n- **档位**: `T2 — 6 文件`\n' > "$P/tasks/2026-01-01-big/prd.md"
wip_commit "$P"
# 纯代码提交：5 个文件，不碰任何任务目录
mkdir -p "$P/src"; for i in 1 2 3 4 5; do printf 'echo %s\n' "$i" > "$P/src/f$i.sh"; done
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "没有声明 T2/T3" "$out" "5 个代码文件却只有 T2 任务在飞 → 仍然拦下"

echo "== G1b: 跨提交累计（代码提交不碰任务目录）=="
P="$TMP/g1b"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-07-split" "$P/src"
plan_text T1 > "$P/tasks/2026-01-07-split/plan.md"
wip_commit "$P"                                   # 计划先提交
printf 'echo 1\n' > "$P/src/a.sh"; printf 'echo 2\n' > "$P/src/b.sh"
( cd "$P" && git add -A ) >/dev/null 2>&1               # 暂存但不提交：模拟「这次要提交的」
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
not "没有声明 T2/T3" "$out" "累计 2 个文件时不拦"
wip_commit "$P"                                         # 第一个提交：2 个文件
printf 'echo 3\n' > "$P/src/c.sh"; printf 'echo 4\n' > "$P/src/d.sh"
( cd "$P" && git add -A ) >/dev/null 2>&1               # 第二个提交在索引里，这次不碰 tasks/
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "累计" "$out" "两次提交各 2 个文件，累计 4 个 → 拦下"

echo "== G1c: 躺着一个没归档的 T2 任务时，T1 的规模底线仍然有效 =="
P="$TMP/g1c"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-08-big" "$P/tasks/2026-01-08-small" "$P/src"
plan_text T2 > "$P/tasks/2026-01-08-big/plan.md"
plan_text T1 > "$P/tasks/2026-01-08-small/plan.md"
wip_commit "$P"
for i in 1 2 3 4 5; do printf 'echo %s\n' "$i" > "$P/src/f$i.sh"; done
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "累计" "$out" "T2 任务在飞不会让 T1 的底线失效"

echo "== G-arch-1: 模块表一格写两个路径 =="
P="$TMP/ga1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src/a" "$P/src/b"
printf 'echo a\n' > "$P/src/a/x.sh"; printf 'echo b\n' > "$P/src/b/y.sh"
cat > "$P/docs/architecture.md" <<'MD'
# 架构

## 模块划分

| 模块 | 路径 | 职责 |
|---|---|---|
| a | `src/a/x.sh` + `src/b/y.sh` | 两个文件 |
| b | `src/b/` | 目录 |
MD
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "但它不存在" "$out" "一格两个路径都真实存在时不报错"

echo "== G-arch-2: 一格里的第二个路径不存在仍要报 =="
sed -i 's|`src/a/x.sh` + `src/b/y.sh`|`src/a/x.sh` + `src/b/nope.sh`|' "$P/docs/architecture.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "但它不存在" "$out" "第二段不存在时照样拦下（修复不能变成静默忽略）"

echo "== G-arch-3: 相对段按上一段目录解析 =="
mkdir -p "$P/src/c/d"; printf 'x\n' > "$P/src/c/d/one.sh"; printf 'x\n' > "$P/src/c/d/two.sh"
# 先把 G-arch-2 的坏行改回来，再加一行「绝对路径 + 相对名」
sed -i 's|`src/a/x.sh` + `src/b/nope.sh`|`src/a/x.sh` + `src/b/y.sh`|' "$P/docs/architecture.md"
printf '| c | `src/c/d/one.sh` + `two.sh` | 相对段 |\n' >> "$P/docs/architecture.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "但它不存在" "$out" "相对段 two.sh 解析到 src/c/d/two.sh"

echo "== G-doc-1: 机制文件不许再要求「等人确认 seam」 =="
for f in docs/agents/执行者.md skills/tdd/SKILL.md AGENTS.md README.md tasks/README.md; do
    if grep -qE "seam 并等确认|并让用户确认|seam 并等待确认|需要 seam 确认|seam 已确认" "$REPO_ROOT/templates/$f"; then
        no "$f 仍要求等人确认 seam"
    else
        ok "$f 与任务分级一致"
    fi
done

echo "== G1d: 索引干净时规模底线不误报 =="
P="$TMP/g1d"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-09-old" "$P/src"
plan_text T1 > "$P/tasks/2026-01-09-old/plan.md"
for i in 1 2 3 4 5 6; do printf 'echo %s\n' "$i" > "$P/src/f$i.sh"; done
wip_commit "$P"                                   # 6 个文件进历史，任务声明是 T1
out="$(run_staged "$P")"                          # 索引干净
not "没有声明 T2/T3" "$out" "没有暂存改动时不报规模底线"
# 反向：真暂存一个代码文件，累计照旧生效，并且点名是哪个任务
printf 'echo 7\n' > "$P/src/f7.sh"; ( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "没有声明 T2/T3" "$out" "有暂存内容时累计照旧生效"
has "2026-01-09-old" "$out" "报错点出是哪个任务超了规模底线"

echo "== G1e: 模板目录不被当成任务（只改 src 时不许 100% 拦）=="
P="$TMP/g1e"; new_project "$P" || { echo "建项目失败"; exit 2; }
# 让「模板 plan.md 进入历史」那笔提交拉长：一段历史之后才出现代码
printf 'echo 1\n' > "$P/src/f1.sh"; wip_commit "$P" code1
printf 'echo 2\n' > "$P/src/f2.sh"; wip_commit "$P" code2
printf 'echo 3\n' > "$P/src/f3.sh"; wip_commit "$P" code3
printf 'echo 4\n' > "$P/src/f4.sh"; wip_commit "$P" code4
printf 'echo 5\n' > "$P/src/f5.sh"; wip_commit "$P" code5
# 现在只改 1 个 src 文件并暂存：没有任何任务目录被碰
printf 'echo 1 # 注释\n' > "$P/src/f1.sh"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "tasks/_template" "$out" "模板目录不被当成任务累计"
# 反向：5 个文件全在索引里、仓库里只有 T2 任务在飞 → 仍要拦，且主语是「本次改动」。
# T2 任务必须先提交：否则这次提交碰了任务目录、cands 非空，走的是「该任务自己是 T2」
# 那条提前返回，测不到这个分支。
rm -rf "$P/tasks"/*
mkdir -p "$P/tasks/2026-01-10-big"; plan_text T2 > "$P/tasks/2026-01-10-big/plan.md"
wip_commit "$P" t2task
for i in 1 2 3 4 5; do printf 'echo %s # x\n' "$i" > "$P/src/f$i.sh"; done
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "本次改动" "$out" "只有 T2 在飞时，本次索引的 5 个文件仍被拦"

echo "== G-link: 文档里的相对路径必须存在 =="
P="$TMP/gl1"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '\n见 `docs/nope.md`。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "docs/nope.md" "$out" "指向不存在文件的相对路径被报出来"
# 围栏代码块里的路径不算引用（示例命令常出现不存在的路径）
printf '\n```bash\ncat docs/nope.md\n```\n' >> "$P/AGENTS.md"
sed -i 's|见 `docs/nope.md`。|见 `docs/commands.md`。|' "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "docs/nope.md" "$out" "围栏代码块里的路径不检查、改对之后不报"
# 带占位符的示例路径不检查
printf '\n写进 `tasks/<日期>-<简述>/plan.md`。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "plan.md 不存在" "$out" "带占位符的示例路径不检查"

echo "== G-adr: 取代关系必须互指 =="
P="$TMP/gadr"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '# 甲\n\nStatus: accepted\n' > "$P/docs/adr/0001-a.md"
printf '# 乙\n\nStatus: accepted\nSupersedes: ADR-0001\n' > "$P/docs/adr/0002-b.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "没有" "$out" "只写 Supersedes、旧篇没写 Superseded-By → 报"
# 补上反向互链，但 Status 还写着 accepted
printf '# 甲\n\nStatus: accepted\nSuperseded-By: ADR-0002\n' > "$P/docs/adr/0001-a.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "应为 superseded" "$out" "写了 Superseded-By 却仍是 accepted → 报"
sed -i 's/^Status: accepted$/Status: superseded/' "$P/docs/adr/0001-a.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "[x]" "$out" "两边互指且状态正确 → 通过"
# 引用了不存在的编号
printf '\n另见 ADR-0009。\n' >> "$P/docs/adr/0002-b.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "ADR-0009" "$out" "引用不存在的 ADR 被报出来"

echo "== G2: plan.md 的「目标」为空要报 =="
P="$TMP/g2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-02-x"
plan_text T1 1 > "$P/tasks/2026-01-02-x/plan.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "「目标」为空" "$out" "空目标被报出来"
# 反向：填上就不该报
sed -i 's/^- \*\*目标\*\*:$/- **目标**: 写清楚了/' "$P/tasks/2026-01-02-x/plan.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "「目标」为空" "$out" "填上目标后不再报"

echo "== G3: 纯重命名的归档不该被判红 =="
P="$TMP/g3"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-03-legacy"
# 旧格式：journal 缺新模板的节，直接提交（模拟历史遗留）
printf '# 旧日志\n\n随手记的东西。\n' > "$P/tasks/2026-01-03-legacy/journal.md"
wip_commit "$P"
mkdir -p "$P/tasks/_archive"
( cd "$P" && git mv tasks/2026-01-03-legacy tasks/_archive/ ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "2026-01-03-legacy" "$out" "归档提交不再逐条判旧格式"
[ "$(printf '%s' "$out" | grep -c '^  \[x\]')" -eq 0 ] 2>/dev/null && ok "归档提交整体通过" || {
    printf '%s\n' "$out" | grep '^  \[x\]' | head -3 | sed 's/^/       /'
    no "归档提交整体通过"
}

echo "== G3b: 拍平归档仍然要报 =="
P="$TMP/g3b"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-04-flat"
printf '# 旧日志\n' > "$P/tasks/2026-01-04-flat/journal.md"
wip_commit "$P"
# 没有先 mkdir：git 把目录改名成 _archive，文件被拍平
( cd "$P" && git mv tasks/2026-01-04-flat tasks/_archive ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "_archive/ 顶层不该有文件" "$out" "拍平归档被报出来"

echo "== 回归：普通 T1 提交照常通过 =="
P="$TMP/g4"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-05-small" "$P/src"
plan_text T1 > "$P/tasks/2026-01-05-small/plan.md"
printf 'echo hi\n' > "$P/src/a.sh"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
[ "$(printf '%s' "$out" | grep -c '^  \[x\]')" -eq 0 ] 2>/dev/null && ok "T1 单文件提交通过" || {
    printf '%s\n' "$out" | grep '^  \[x\]' | head -3 | sed 's/^/       /'
    no "T1 单文件提交通过"
}

echo "== journal 的「下次注意什么」必须写去向 =="
P="$TMP/g5"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-06-note"

# 整份 journal 用函数生成：只有「下次注意什么」这一节随用例变，
# 拼字符串改文件会在多条目那条用例上写出不可读的 sed。
journal_head() {
    cat <<'HDR'
# 执行日志

## 目标

修好 a

## 主要提交

- **主要提交**: `abc1234`

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `src/a.sh` | 改一行 |

## 验证结果

| 命令 | 结果 |
|---|---|
| `bash scripts/check-gates.sh` | 通过 |

- 未运行的检查及原因: 无

- 被打回: 1 次

## 遇到的问题

- 重跑了两次才过：第一次忘了同步 b（提交 abc1234）

## 下次注意什么
HDR
}
journal_tail() {
    cat <<'FTR'

## 涉及的 ADR

- 无

## 下一步

- 无

## 雾区变化

- **解掉的雾区项**: 无
- **新增的雾区项**: 无

## 一致性走查

- **本次是否走查**: 未到触发条件

## 结束状态

- **结束状态**: `DONE`
FTR
}
write_journal() {  # $1 = 下次注意什么 这一节的内容
    { journal_head; printf '%s\n' "$1"; journal_tail; } > "$P/tasks/2026-01-06-note/journal.md"
}
staged_run() { ( cd "$P" && git add -A ) >/dev/null 2>&1; run_staged "$P"; }

write_journal "- 改 A 必须同步 B"
out="$(staged_run)"
has "没有去向" "$out" "没写去向的提醒被报出来"
# 模板自带的 `- 被打回: N 次` 不能算成一条验证结果
not "验证结果」里没有一行结果" "$out" "「被打回」不计入验证结果条目"

write_journal "- 改 A 必须同步 B
  → pitfalls"
out="$(staged_run)"
not "没有去向" "$out" "箭头写在下一行也算去向"

write_journal "- 改 A 必须同步 B
  → pitfalls
- 少写一条测试"
out="$(staged_run)"
has "少写一条测试" "$out" "多条目时逐条判，缺去向的那条被报出来"
not "改 A 必须同步 B" "$out" "已经写了去处的条目不再报"

write_journal "- 无"
out="$(staged_run)"
not "没有去向" "$out" "写「无」不算违规"

# 顿号 / 全角括号编号也要认作条目起始，否则整节被并成一条，静默免检
write_journal "1、第一条没有去向
2、第二条 → pitfalls
3）第三条也没有去向"
out="$(staged_run)"
has "第一条没有去向" "$out" "顿号编号的条目被单独检查"
has "第三条也没有去向" "$out" "全角括号编号的条目被单独检查"
not "第二条 → pitfalls" "$out" "写了去向的顿号条目不被误报"

# 散文（没有条目符号）也要能在报错里看到原文，而不是空着
write_journal "这是一句散文，没有条目符号也没有去向"
out="$(staged_run)"
has "这是一句散文" "$out" "散文条目的报错带原文（不是空消息）"

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
