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
wip_commit "$P"                                   # 前 2 个代码文件：还不该拦
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
not "没有声明 T2/T3" "$out" "累计 2 个文件时不拦"
printf 'echo 3\n' > "$P/src/c.sh"; printf 'echo 4\n' > "$P/src/d.sh"
wip_commit "$P"                                   # 再 2 个，且这次没碰 tasks/
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "累计" "$out" "两次提交各 2 个文件，累计 4 个 → 拦下"

echo "== G1c: 躺着一个没归档的 T2 任务时，T1 的规模底线仍然有效 =="
P="$TMP/g1c"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-08-big" "$P/tasks/2026-01-08-small" "$P/src"
plan_text T2 > "$P/tasks/2026-01-08-big/plan.md"
plan_text T1 > "$P/tasks/2026-01-08-small/plan.md"
wip_commit "$P"
for i in 1 2 3 4 5; do printf 'echo %s\n' "$i" > "$P/src/f$i.sh"; done
wip_commit "$P"
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "累计" "$out" "T2 任务在飞不会让 T1 的底线失效"

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

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
