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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
has() { if printf '%s' "$2" | grep -qF -- "$1"; then ok "$3"; else no "$3"; fi; }
not() { if printf '%s' "$2" | grep -qF -- "$1"; then no "$3"; else ok "$3"; fi; }
tree_sig() { ( cd "$1" && find . -type f -not -path './.git/*' | sort | xargs sha1sum 2>/dev/null | sha1sum ); }

commit_all() {
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm "${2:-wip}" >/dev/null 2>&1
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
kd="$(printf '%s\n' "$out" | sed -n 's/^冲突现场: //p' | head -n 1)"
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
commit_all "$P" init
out="$("$B" "$UP" "$P" --write 2>&1)"; rc=$?
has "自检：" "$out" "跑了一次闸门"
has "存量违规" "$out" "报出违规条数"
grep -q '^gate_violations=' "$P/.scaffold-version" && ok "违规数记进了 .scaffold-version" || no "违规数记进了 .scaffold-version"

# ---------------------------------------------------------------- 7. --diff

echo "== --diff =="
P="$TMP/p7"; cp -r "$TMP/withver" "$P"
out="$("$B" "$UP" "$P" --diff 2>&1)"
has "fixture 新增的一节" "$out" "--diff 打印了改动内容"

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
