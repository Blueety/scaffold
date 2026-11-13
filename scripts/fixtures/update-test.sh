#!/usr/bin/env bash
#
# 更新器的验收 fixture。不进 CI 的自动环节（需要 git 且要跑十几秒），
# 但每次改 scaffold-update.sh 都要跑：bash scripts/fixtures/update-test.sh
#
# 覆盖的是「报告里出过事故的那几条」，不是行覆盖率：
#   - 冲突现场留不留得住（base/ours/theirs）
#   - 目标仓库脏时拒写、--force 放行
#   - 裁决生效：keep-local 之后不再起冲突；模板变了要提示
#   - union 只追加、不删本地行
#   - 落盘后跑闸门报数
#   - 预览不写盘
#
# 退出码 0 = 全过。

set -u
trap '' PIPE

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPDATE="$REPO_ROOT/scripts/scaffold-update.sh"
INIT="$REPO_ROOT/init.sh"
B="${BASH:-bash}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/update-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
has() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else no "$3"; fi; }
not() { if printf '%s' "$2" | grep -qF -- "$1"; then no "$3"; else ok "$3"; fi; }
tree_sig() { ( cd "$1" && find . -type f -not -path './.git/*' | sort | xargs sha1sum 2>/dev/null | sha1sum ); }

commit_all() {
    # 必须绕过钩子：fixture 要造「闸门会判红」的现场（空目标、旧格式 journal），
    # 钩子会在这一步把提交拦下，后面所有断言就都在测失败路径。
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm "${2:-wip}" >/dev/null 2>&1
}

# ---------------------------------------------------------------- fixture

echo "== 造 fixture =="
# 关键：项目要从**同一个 templates 副本**生成，否则基线和项目天然对不上，
# 自动比对会挑到错误的版本，后面所有断言都在测别的东西。
SCAF="$TMP/scaffold"
mkdir -p "$SCAF/scripts"
cp -r "$REPO_ROOT/templates" "$SCAF/templates"
cp "$REPO_ROOT/init.sh" "$SCAF/init.sh"
cp "$UPDATE" "$SCAF/scripts/scaffold-update.sh"
git -C "$SCAF" init -q .
git -C "$SCAF" add -A >/dev/null 2>&1
git -C "$SCAF" -c user.email=t@t -c user.name=t commit -qm base
UP="$SCAF/scripts/scaffold-update.sh"   # 脚本从自身位置推 SCAFFOLD_ROOT，指向 $SCAF

mkdir -p "$TMP/gen"
( cd "$TMP/gen" && "$B" "$SCAF/init.sh" demo >/dev/null 2>&1 ) || { echo "init.sh 失败"; exit 2; }
cp -r "$TMP/gen/demo" "$TMP/base-project"
commit_all "$TMP/base-project" init

# 让「新版模板」真的和旧版不同：改一个文件、加一个文件（只动 $SCAF，不动真实 templates/）
printf '\n## fixture 新增的一节\n' >> "$SCAF/templates/docs/commands.md"
printf '# 新文档\n' > "$SCAF/templates/docs/new-thing.md"
git -C "$SCAF" add -A >/dev/null 2>&1
git -C "$SCAF" -c user.email=t@t -c user.name=t commit -qm new
BASE_SHA="$(git -C "$SCAF" rev-parse HEAD~1)"

# p1 测「没有版本文件 → 按内容比对」；其余用例钉死基线，否则同一份内容可能同时
# 匹配两个版本，挑到哪个全看 tie-break，测的就不是要测的东西了。
cp -r "$TMP/base-project" "$TMP/withver"
printf 'scaffold=%s\nproject_name=demo\ncommit=%s\n' "$SCAF" "$BASE_SHA" > "$TMP/withver/.scaffold-version"
commit_all "$TMP/withver" version
ok "fixture 就绪"

# ---------------------------------------------------------------- 1. 预览

echo "== 预览不写盘 =="
P="$TMP/p1"; cp -r "$TMP/base-project" "$P"
before="$(tree_sig "$P")"
out="$("$B" "$UP" "$P" 2>&1)"
has "预览" "$out" "预览"
[ "$(tree_sig "$P")" = "$before" ] && ok "树没变" || no "树没变"
[ ! -f "$P/.scaffold-version" ] && ok "没写版本文件" || no "没写版本文件"
has "新增   docs/new-thing.md" "$out" "报出模板新增文件"

# ---------------------------------------------------------------- 2. 冲突现场

echo "== 冲突现场 =="
P="$TMP/p2"; cp -r "$TMP/withver" "$P"
printf '\n本地改的一行\n' >> "$P/docs/commands.md"
commit_all "$P" local-edit
out="$("$B" "$UP" "$P" --write 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "冲突退出码 1" || no "冲突退出码 1（实际 $rc）"
has "冲突   docs/commands.md" "$out" "报出冲突"
kd="$(printf '%s\n' "$out" | sed -n 's/^现场目录: //p' | head -n 1)"
if [ -n "$kd" ] && [ -f "$kd/docs/commands.md.base" ] && [ -f "$kd/docs/commands.md.ours" ] && [ -f "$kd/docs/commands.md.theirs" ]; then
    ok "三方快照都在"
else
    no "三方快照都在（kd=$kd）"
fi
if [ -n "$kd" ] && grep -q '本地改的一行' "$kd/docs/commands.md.ours"; then ok "ours 是冲突前的内容"; else no "ours 是冲突前的内容"; fi
if [ -n "$kd" ] && [ -d "$P/.git/scaffold-work" ]; then ok "现场放在 .git 里（不进 git status）"; else no "现场放在 .git 里"; fi

# ---------------------------------------------------------------- 3. 脏树

echo "== 目标仓库脏 =="
P="$TMP/p3"; cp -r "$TMP/withver" "$P"
printf 'local\n' >> "$P/README.md"
ver_before="$(cat "$P/.scaffold-version")"
tree_before="$(tree_sig "$P")"
out="$("$B" "$UP" "$P" --write 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "脏树拒写，退出码 2" || no "脏树拒写，退出码 2（实际 $rc）"
has "拒绝写盘" "$out" "说明了原因"
[ "$(cat "$P/.scaffold-version")" = "$ver_before" ] && ok "脏树时版本文件没被改写" || no "脏树时版本文件没被改写"
[ "$(tree_sig "$P")" = "$tree_before" ] && ok "脏树时工作区没被动过" || no "脏树时工作区没被动过"
out="$("$B" "$UP" "$P" --write --force 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then ok "--force 放行"; else no "--force 放行（实际 $rc）"; fi

# ---------------------------------------------------------------- 4. 裁决 keep-local

echo "== 裁决 keep-local =="
P="$TMP/p4"; cp -r "$TMP/withver" "$P"
printf '\n本项目特有的段落\n' >> "$P/docs/commands.md"
commit_all "$P" local-edit
"$B" "$UP" "$P" --write --keep-local docs/commands.md >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "带裁决时不冲突" || no "带裁决时不冲突（实际 $rc）"
grep -q '^decision keep-local docs/commands.md ' "$P/.scaffold-version" && ok "裁决写进了 .scaffold-version" || no "裁决写进了 .scaffold-version"
grep -q '本项目特有的段落' "$P/docs/commands.md" && ok "本地内容保留" || no "本地内容保留"
commit_all "$P" after-update
out="$("$B" "$UP" "$P" 2>&1)"
has "跳过   docs/commands.md（已裁决 keep-local，模板未变）" "$out" "第二次跳过，不再打扰"
not "冲突   docs/commands.md" "$out" "第二次不冲突"

# 模板再变 → 必须提示重新判断
printf '\n## 又一次模板改动\n' >> "$SCAF/templates/docs/commands.md"
git -C "$SCAF" add -A >/dev/null 2>&1
git -C "$SCAF" -c user.email=t@t -c user.name=t commit -qm again
out="$("$B" "$UP" "$P" 2>&1)"
has "模板已变" "$out" "模板变了会提示重新判断"

# ---------------------------------------------------------------- 5. 裁决 union

echo "== 裁决 union =="
P="$TMP/p5"; cp -r "$TMP/withver" "$P"
printf '\n本地专有的 .gitignore 行\n' >> "$P/.gitignore"
commit_all "$P" local-edit
"$B" "$UP" "$P" --write --union .gitignore >/dev/null 2>&1
grep -q '本地专有的 .gitignore 行' "$P/.gitignore" && ok "union 不删本地行" || no "union 不删本地行"
grep -q 'tasks/\*\*/tmp/' "$P/.gitignore" && ok "union 追加了模板行" || no "union 追加了模板行"
grep -q '^decision union .gitignore ' "$P/.scaffold-version" && ok "union 记进了 .scaffold-version" || ok "union 记进了 .scaffold-version"

# ---------------------------------------------------------------- 6. 落盘自检

echo "== 落盘后跑闸门 =="
P="$TMP/p6"; cp -r "$TMP/withver" "$P"
# 造存量违规：旧格式 plan（档位 / 类型写在散文行、头块里没有 → 判「未声明」，且「目标」为空）
mkdir -p "$P/tasks/2026-01-09-legacy"
printf '# 实施计划\n\n## 任务概要\n\n- **档位**: `T1 — 1 文件 / 0 调用方 / 行为有变 / 无覆盖测试 / 预估 5 行`\n- **类型**: `加功能`\n- **目标**:\n- **相关文件**:\n  - src/a.sh\n- **验证命令**: `bash scripts/check-gates.sh`\n\n## 步骤\n\n| # | 步骤 | 文件范围 | 风险 | 验证 |\n|---|---|---|---|---|\n| 1 | 改 a | src/a.sh | 低 | 跑闸门 |\n\n## 确认\n\n- [x] 已确认\n' > "$P/tasks/2026-01-09-legacy/plan.md"
commit_all "$P" init
out="$("$B" "$UP" "$P" --write 2>&1)"; rc=$?
has "自检：" "$out" "跑了一次闸门"
has "存量违规" "$out" "报出违规条数"
has "tasks/2026-01-09-legacy" "$out" "直方图按任务目录聚合（不压成 tasks/）"
grep -q '^gate_violations=' "$P/.scaffold-version" && ok "违规数记进了 .scaffold-version" || no "违规数记进了 .scaffold-version"

# ---------------------------------------------------------------- 7. --diff

echo "== --diff =="
P="$TMP/p7"; cp -r "$TMP/withver" "$P"
out="$("$B" "$UP" "$P" --diff 2>&1)"
has "fixture 新增的一节" "$out" "--diff 打印了改动内容"
# `| head` 关掉管道时，trap '' PIPE 会让 sed/grep 往 stderr 打 "Broken pipe"，
# 把真正的输出淹掉。这里只关心 stderr 有没有这行噪音。
err="$("$B" "$UP" "$P" --diff 2>&1 >/dev/null | head -3)"
not "Broken pipe" "$err" "管道被关掉时不吐 Broken pipe"

# ---------------------------------------------------------------- 8. 基线阈值

echo "== 基线一致率阈值 =="
P="$TMP/p8"; cp -r "$TMP/base-project" "$P"
# 把项目里几乎所有模板文件都改一行，一致率必然掉到阈值以下
while IFS= read -r f; do
    case "$f" in AGENTS.md|README.md) continue ;; esac
    [ -f "$P/$f" ] && printf '改过的行\n' >> "$P/$f"
done < <( cd "$SCAF/templates" && find . -type f | sed 's|^\./||' )
commit_all "$P" messy
out="$("$B" "$UP" "$P" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "低一致率拒绝合并（退出码 2）" || no "低一致率拒绝合并（实际 $rc）"
has "不敢拿它当 base" "$out" "说明了为什么拒绝"
has "--adopt-baseline" "$out" "给出 --adopt-baseline 这条出路"
out="$("$B" "$UP" "$P" --accept-guess 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then ok "--accept-guess 放行"; else no "--accept-guess 放行（实际 $rc）"; fi
has "按 --accept-guess" "$out" "放行时仍然提醒"

# ---------------------------------------------------------------- 9. --adopt-baseline

echo "== --adopt-baseline =="
P="$TMP/p9"; cp -r "$TMP/base-project" "$P"
rm -f "$P/.scaffold-version"
before="$(tree_sig "$P")"
out="$("$B" "$UP" "$P" --adopt-baseline "$BASE_SHA" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "adopt 退出码 0" || no "adopt 退出码 0（实际 $rc）"
# 「不动项目文件」= 除了新写的 .scaffold-version，git 看不到别的变化
changed="$( cd "$P" && git -c core.quotepath=false status --porcelain --untracked-files=all 2>/dev/null )"
if [ "$changed" = "?? .scaffold-version" ]; then ok "adopt 只写了基线文件"; else no "adopt 只写了基线文件（实际: $changed）"; fi
grep -q "^commit=$BASE_SHA\$" "$P/.scaffold-version" && ok "记下了指定提交" || no "记下了指定提交"
grep -q '^baseline_source=adopted$' "$P/.scaffold-version" && ok "来源标成 adopted" || no "来源标成 adopted"

# ---------------------------------------------------------------- 10. --refresh-gate-count

echo "== --refresh-gate-count =="
P="$TMP/p10"; cp -r "$TMP/withver" "$P"
commit_all "$P" init
"$B" "$UP" "$P" --write >/dev/null 2>&1
commit_all "$P" updated
before="$(tree_sig "$P")"
out="$("$B" "$UP" "$P" --refresh-gate-count 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "refresh 退出码 0" || no "refresh 退出码 0（实际 $rc）"
has "已更新 .scaffold-version" "$out" "说明了只更新计数"
grep -q '^gate_violations=' "$P/.scaffold-version" && ok "计数还在" || no "计数还在"
not "汇总:" "$out" "没有走合并流程"

# ---------------------------------------------------------------- 11. 机制文件

echo "== .scaffold-kinds: mechanism =="
# 机制文件两边都改过才算数：模板侧也要动一次
printf '\n模板给执行者加的一条\n' >> "$SCAF/templates/docs/agents/执行者.md"
git -C "$SCAF" add -A >/dev/null 2>&1
git -C "$SCAF" -c user.email=t@t -c user.name=t commit -qm touch-agent
P="$TMP/p11"; cp -r "$TMP/withver" "$P"
printf '\n本地给执行者加的一条\n' >> "$P/docs/agents/执行者.md"
commit_all "$P" local
out="$("$B" "$UP" "$P" --write 2>&1)"; rc=$?
has "覆盖   docs/agents/执行者.md" "$out" "机制文件直接取模板版"
not "冲突   docs/agents/执行者.md" "$out" "机制文件不再起冲突"
kd="$(printf '%s\n' "$out" | sed -n 's/^现场目录: //p' | head -n 1)"
if [ -n "$kd" ] && grep -q '本地给执行者加的一条' "$kd/docs/agents/执行者.md.ours" 2>/dev/null; then
    ok "本地改动备份进了现场"
else
    no "本地改动备份进了现场（kd=$kd）"
fi
grep -q '模板给执行者加的一条' "$P/docs/agents/执行者.md" && ok "文件已经是模板版" || no "文件已经是模板版"

# ---------------------------------------------------------------- 12. MANIFEST / JSON / --quiet

echo "== MANIFEST / JSON / --quiet =="
P="$TMP/p12"; cp -r "$TMP/withver" "$P"
commit_all "$P" init
out="$("$B" "$UP" "$P" --write --json "$TMP/out.json" 2>&1)"; rc=$?
has "这次写到的文件" "$out" "默认打印动作清单"
mf="$(printf '%s\n' "$out" | sed -n 's/^现场目录: //p' | head -n 1)"
if [ -n "$mf" ] && [ -f "$mf/MANIFEST" ]; then ok "MANIFEST 落了"; else no "MANIFEST 落了（mf=$mf）"; fi
if [ -f "$TMP/out.json" ] && grep -q '"baseline_source"' "$TMP/out.json"; then ok "JSON 有 baseline_source"; else no "JSON 有 baseline_source"; fi
if [ -f "$TMP/out.json" ] && grep -q '"files"' "$TMP/out.json"; then ok "JSON 有 files 数组"; else no "JSON 有 files 数组"; fi
P="$TMP/p12b"; cp -r "$TMP/withver" "$P"
commit_all "$P" init
out="$("$B" "$UP" "$P" --write --quiet 2>&1)"
not "这次写到的文件" "$out" "--quiet 不打印清单"
has "汇总:" "$out" "--quiet 仍给汇总"

# ---------------------------------------------------------------- 13. 跳过的文件给行数

echo "== --diff 下跳过文件给行数 =="
P="$TMP/p13"; cp -r "$TMP/withver" "$P"
printf '# 项目自己写的同名文件\n内容不同\n' > "$P/docs/new-thing.md"
commit_all "$P" own
out="$("$B" "$UP" "$P" --diff 2>&1)"
has "跳过   docs/new-thing.md" "$out" "报成跳过"
has "模板" "$out" "给了行数提示"

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
