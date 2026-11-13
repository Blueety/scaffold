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

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
# 分段计时：闸门 fixture 一轮十几分钟，某一段变慢时没有这个就只能靠猜。
# 设置 FIXTURE_TIME=1 才打印，平时保持输出干净。
_t0=$SECONDS
sec() { [ -n "${FIXTURE_TIME:-}" ] && printf '[%4ds] %s\n' "$((SECONDS - _t0))" "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
# 原地替换。不能用 `sed -i`：BSD（macOS 自带）的 -i 必须带备份后缀，
# 写成 `sed -i '...' file` 在 macOS 上直接报 invalid command code。
subst() { # $1=文件 $2=sed 脚本
    sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

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
    printf '<!-- gate\ntier: %s\ntype: feat\n-->\n\n' "$tier"
    printf '# 实施计划\n\n## 任务概要\n\n'
    if [ "$empty_goal" = "1" ]; then
        printf -- '- **目标**:\n'
    else
        printf -- '- **目标**: 让 X 在 Y 时不再报错\n'
    fi
    printf -- '- **相关文件**:\n  - src/a.sh\n'
    printf -- '- **验证命令**: `bash scripts/check-gates.sh`\n\n'
    printf '## 步骤\n\n| # | 步骤 | 文件范围 | 风险 | 验证 |\n|---|---|---|---|---|\n'
    printf '| 1 | 改 a | src/a.sh | 低 | 跑闸门 |\n\n'
    printf '## 预估 diff 范围\n\n- 新增文件: 无\n- 修改文件: src/a.sh\n- 删除文件: 无\n\n'
    printf '## 确认\n\n- [x] 已确认\n'
}

# 一份能过闸门的 prd.md。$1 = 头块里的档位（不传 = 头块里不声明档位）
prd_text() {
    printf '<!-- gate\n'
    [ -n "${1:-}" ] && printf 'tier: %s\n' "$1"
    printf -- '-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n'
}

# 一份能过闸门的 review.md。$1 可选地挖空某处：
#   empty_原文  empty_结论  empty_审查者
review_text() {
    local hole="${1:-}"
    printf '# 审查裁决单\n\n## 审查范围\n\n'
    [ "$hole" = "empty_审查者" ] && printf -- '- **审查者**:\n' || printf -- '- **审查者**: 独立子 agent\n'
    printf -- '- **固定点**: `abc1234`\n'
    printf -- '- **给了它什么**: prd.md、plan.md、diff、AGENTS.md\n'
    printf -- '- **轮次**: 1\n\n'
    printf '## 审查者原文\n\n'
    [ "$hole" = "empty_原文" ] || printf '审查者：第 1 行少了一个边界判断。\n'
    printf '\n## 逐条处理\n\n| # | 审查者发现（原文摘要） | 处理 | 依据 |\n|---|---|---|---|\n| 1 | 缺边界判断 | 改，补了 else 分支 | 重跑闸门通过 |\n\n'
    printf '## 审查者明确未判断的\n\n- 无\n\n'
    printf '## 结论\n\n'
    [ "$hole" = "empty_结论" ] || printf '可以合。\n'
}

sec "G1: 规模底线不被在飞任务短路"
echo "== G1: 规模底线不被在飞任务短路 =="
P="$TMP/g1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-01-big"
plan_text T2 > "$P/tasks/2026-01-01-big/plan.md"
prd_text T2 > "$P/tasks/2026-01-01-big/prd.md"
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

sec "G1c: 躺着一个没归档的 T2 任务时，T1 的规模底线仍然有效"
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

sec "G-arch-1: 模块表一格写两个路径"
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

sec "G-arch-2: 一格里的第二个路径不存在仍要报"
echo "== G-arch-2: 一格里的第二个路径不存在仍要报 =="
subst "$P/docs/architecture.md" 's|`src/a/x.sh` + `src/b/y.sh`|`src/a/x.sh` + `src/b/nope.sh`|'
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "但它不存在" "$out" "第二段不存在时照样拦下（修复不能变成静默忽略）"

sec "G-arch-3: 相对段按上一段目录解析"
echo "== G-arch-3: 相对段按上一段目录解析 =="
mkdir -p "$P/src/c/d"; printf 'x\n' > "$P/src/c/d/one.sh"; printf 'x\n' > "$P/src/c/d/two.sh"
# 先把 G-arch-2 的坏行改回来，再加一行「绝对路径 + 相对名」
subst "$P/docs/architecture.md" 's|`src/a/x.sh` + `src/b/nope.sh`|`src/a/x.sh` + `src/b/y.sh`|'
printf '| c | `src/c/d/one.sh` + `two.sh` | 相对段 |\n' >> "$P/docs/architecture.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "但它不存在" "$out" "相对段 two.sh 解析到 src/c/d/two.sh"

sec "G-doc-1: 机制文件不许再要求「等人确认 seam」"
echo "== G-doc-1: 机制文件不许再要求「等人确认 seam」 =="
for f in docs/agents/执行者.md skills/tdd/SKILL.md AGENTS.md README.md tasks/README.md; do
    if grep -qE "seam 并等确认|并让用户确认|seam 并等待确认|需要 seam 确认|seam 已确认" "$REPO_ROOT/templates/$f"; then
        no "$f 仍要求等人确认 seam"
    else
        ok "$f 与任务分级一致"
    fi
done

sec "G1d: 索引干净时规模底线不误报"
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

sec "G-link: 文档里的相对路径必须存在"
echo "== G-link: 文档里的相对路径必须存在 =="
P="$TMP/gl1"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '\n见 `docs/nope.md`。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "docs/nope.md" "$out" "指向不存在文件的相对路径被报出来"
# 围栏代码块里的路径不算引用（示例命令常出现不存在的路径）
printf '\n```bash\ncat docs/nope.md\n```\n' >> "$P/AGENTS.md"
subst "$P/AGENTS.md" 's|见 `docs/nope.md`。|见 `docs/commands.md`。|'
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "docs/nope.md" "$out" "围栏代码块里的路径不检查、改对之后不报"
# 带占位符的示例路径不检查
printf '\n写进 `tasks/<日期>-<简述>/plan.md`。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "plan.md 不存在" "$out" "带占位符的示例路径不检查"

sec "G-adr: 取代关系必须互指"
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
subst "$P/docs/adr/0001-a.md" 's/^Status: accepted$/Status: superseded/'
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "[x]" "$out" "两边互指且状态正确 → 通过"
# 引用了不存在的编号
printf '\n另见 ADR-0009。\n' >> "$P/docs/adr/0002-b.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "ADR-0009" "$out" "引用不存在的 ADR 被报出来"

echo "== G-anchor: 代码里的决策锚点（只提示，不失败）=="
P="$TMP/ganc"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '# 甲\n\nStatus: accepted\n' > "$P/docs/adr/0001-a.md"
printf 'x=1  # 决策: ADR-0001 用整数\n' > "$P/src/a.py"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
not "[!] 锚点" "$out" "锚点指向存在的 ADR 时不提示"
[ "$rc" -eq 0 ] && ok "有效锚点不影响退出码" || no "有效锚点不影响退出码"
# 悬空锚点：提示，但闸门仍然通过
printf 'y=2  # 决策: ADR-0009\n' >> "$P/src/a.py"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
has "ADR-0009" "$out" "指向不存在的 ADR 被提示"
[ "$rc" -eq 0 ] && ok "悬空锚点不拦截提交" || no "悬空锚点不拦截提交"
# 没写目标
printf 'z=3  # 决策: 以后再说\n' >> "$P/src/a.py"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "锚点没写目标" "$out" "没写目标的锚点被提示"
# .md 里的同类字样不算锚点（文档里会写这个约定本身）
printf '\n写法：`# 决策: ADR-0099`\n' >> "$P/docs/adr/README.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "ADR-0099" "$out" "markdown 文档里的示例不算锚点"

sec "G-link-2: 不是路径的行内代码不当断链"
echo "== G-link-2: 不是路径的行内代码不当断链 =="
P="$TMP/gl2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tests"; printf 'def test_shutdown(): pass\n' > "$P/tests/test_web.py"
cat >> "$P/AGENTS.md" <<'EOF'

部署设 `APP_COOKIES_FILE=/srv/cookies.txt`；发布看 `youtu.be/`；
测试见 `tests/test_web.py::test_shutdown`；细节见 `docs/architecture.md:120`。
EOF
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "APP_COOKIES_FILE" "$out" "env 赋值不是断链"
not "youtu.be/" "$out" "裸域名不是断链"
not "::test_shutdown" "$out" "pytest node id 只判文件部分"
not ":120" "$out" "带行号的引用只判文件部分（文件存在就不报）"
# 负向：剥掉后缀之后仍然断链，必须报
printf '\n真断链 `docs/nope.md:12`，另一个 `tests/nope.py::test_x`。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "docs/nope.md" "$out" "带行号的真断链照样报"
has "tests/nope.py" "$out" "node id 的文件部分不存在时照样报"
not "::test_x" "$out" "报的是文件路径，不是整串 node id"
# 违规条数与屏幕上打出来的行数一致（曾经差 1：末尾空行被算成一项）
n_lines="$(printf '%s\n' "$out" | grep -c '^  \[x\]')"
n_declared="$(printf '%s\n' "$out" | sed -n 's/^闸门检查失败：\([0-9]*\) 项。$/\1/p')"
[ "$n_lines" = "$n_declared" ] && ok "失败条数与打出来的行数一致（$n_lines）" \
    || no "失败条数与打出来的行数一致（显示 $n_lines，声明 $n_declared）"

sec "G-link-3: tasks/README.md 属于被查的活文档"
echo "== G-link-3: tasks/README.md 属于被查的活文档 =="
P="$TMP/gl3"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '\n活文档：见 `docs/not-here.md`。\n' >> "$P/tasks/README.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "docs/not-here.md" "$out" "tasks/README.md 里的断链要报"
# _template 与任务目录仍然跳过
printf '\n示例：`docs/nowhere.md`。\n' >> "$P/tasks/_template/plan.md"
mkdir -p "$P/tasks/2026-01-01-x"
printf '# 计划\n\n见 `docs/gone.md`。\n' > "$P/tasks/2026-01-01-x/plan.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "docs/nowhere.md" "$out" "tasks/_template/ 跳过（填空模板）"
not "docs/gone.md" "$out" "任务目录跳过（快照）"

echo "== G-link-4: 扫描尊重 .gitignore（不扫 venv 之类）=="
P="$TMP/gl4"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/venv/lib/pkg"
printf 'venv/\n' > "$P/.gitignore"
printf '上游包自带的说明，见 `their/missing.md`。\n' > "$P/venv/lib/pkg/README.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "their/missing.md" "$out" ".gitignore 里的目录不被扫"
# 负向：同样内容放进已跟踪目录时必须报（不是「含 venv 就跳过」）
mkdir -p "$P/docs"; printf '见 `their/missing.md`。\n' > "$P/docs/x.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "their/missing.md" "$out" "被跟踪的文档里的断链照报"

echo "== G-link-5: 更多非路径写法（日期占位 / 类名 / 模块属性 / npm 包 / 简称）=="
P="$TMP/gl5"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/web/static/skin"; printf 'x\n' > "$P/web/static/skin/tokens.css"
printf 'x\n' > "$P/web/app.py"
cat >> "$P/AGENTS.md" <<'EOF'

- 产物：`reports/YYYY-MM-DD.md`
- 样式：`.card/.kpi-card/.topbar`
- 常量：`src/econ_calendar.KINDS`；属性：`web/app.py:_ASSET_FILES`、`src/env_util.require_env`
- 依赖：`@scope/pkg@1.2.0`
- 简称：`skin/tokens.css`（真实路径 `web/static/skin/tokens.css`）
EOF
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "YYYY-MM-DD" "$out" "日期占位符不是断链"
not ".card/.kpi-card" "$out" "类名列表不是断链"
not "econ_calendar.KINDS" "$out" "常量引用不是断链"
not "env_util.require_env" "$out" "模块函数引用不是断链"
not "@scope/pkg@1.2.0" "$out" "npm 包名不是断链"
not "skin/tokens.css" "$out" "子目录简称能按后缀解析到"
not "web/app.py" "$out" "模块属性只判文件部分，文件在就不报"
# 负向：把简称改成一个确实不存在的前缀，仍要报（后缀解析不能变成万能放行）
subst "$P/AGENTS.md" 's|`skin/tokens.css`（真实路径|`nope/tokens.css`（真实路径|'
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "nope/tokens.css" "$out" "后缀解析对不上的仍要报"

sec "G-link-6: --staged 不得把 .gitignore 里的产物当成断链"
echo "== G-link-6: --staged 不得把 .gitignore 里的产物当成断链 =="
P="$TMP/gl6"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/reports"; printf 'x\n' > "$P/reports/backtest.md"
printf 'reports/\n' >> "$P/.gitignore"
printf '\n产物：`reports/backtest.md`\n' >> "$P/AGENTS.md"
( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm add >/dev/null 2>&1 )
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "reports/backtest.md" "$out" "全量自查：产物不被当断链"
printf 'x\n' > "$P/src/touch.sh"; ( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "reports/backtest.md" "$out" "--staged：产物不被当断链（钩子不该每次提交都红）"

sec "G-link-7: 只查活文档，第三方目录里的 README 不扫"
echo "== G-link-7: 只查活文档，第三方目录里的 README 不扫 =="
P="$TMP/gl7"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/vendor/pkg"; printf '第三方：见 `../nowhere.md`\n' > "$P/vendor/pkg/README.md"
printf '\n活文档断链：`docs/not-here.md`\n' >> "$P/docs/pitfalls.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "nowhere.md" "$out" "vendor 里的第三方 README 不被扫"
has "docs/not-here.md" "$out" "活文档里的断链照报"

sec "G2: plan.md 的「目标」为空要报"
echo "== G2: plan.md 的「目标」为空要报 =="
P="$TMP/g2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-02-x"
plan_text T1 1 > "$P/tasks/2026-01-02-x/plan.md"
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "「目标」为空" "$out" "空目标被报出来"
# 反向：填上就不该报
subst "$P/tasks/2026-01-02-x/plan.md" 's/^- \*\*目标\*\*:$/- **目标**: 写清楚了/'
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
not "「目标」为空" "$out" "填上目标后不再报"

# 差一点的写法（全角冒号）判「没填」，但要额外指出来——否则人盯着一行已填好的字找原因
subst "$P/tasks/2026-01-02-x/plan.md" 's/^- \*\*目标\*\*: 写清楚了$/- **目标**：写清楚了/'
( cd "$P" && git add -A ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "「目标」为空" "$out" "全角冒号的字段行算没填"
has '只认 `- **目标**: 值`' "$out" "并报出这一行写法不对（不是只报空）"

sec "G3: 纯重命名的归档不该被判红"
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

sec "G3b: 拍平归档仍然要报"
echo "== G3b: 拍平归档仍然要报 =="
P="$TMP/g3b"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-04-flat"
printf '# 旧日志\n' > "$P/tasks/2026-01-04-flat/journal.md"
wip_commit "$P"
# 没有先 mkdir：git 把目录改名成 _archive，文件被拍平
( cd "$P" && git mv tasks/2026-01-04-flat tasks/_archive ) >/dev/null 2>&1
out="$(run_staged "$P")"
has "_archive/ 顶层不该有文件" "$out" "拍平归档被报出来"

sec "回归：普通 T1 提交照常通过"
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

sec "journal 的「下次注意什么」必须写去向"
echo "== journal 的「下次注意什么」必须写去向 =="
P="$TMP/g5"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-06-note"

# 整份 journal 用函数生成：只有「下次注意什么」这一节随用例变，
# 拼字符串改文件会在多条目那条用例上写出不可读的 sed。
journal_head() {
    cat <<'HDR'
<!-- gate
status: DONE
commit: abc1234
rejections: 1
-->

# 执行日志

## 目标

修好 a

## 主要提交

见头块

## 改动文件清单

| 文件 | 改动 |
|---|---|
| `src/a.sh` | 改一行 |

## 验证结果

| 命令 | 结果 |
|---|---|
| `bash scripts/check-gates.sh` | 通过 |

- 未运行的检查及原因: 无

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

见头块
FTR
}
write_journal() {  # $1 = 下次注意什么 这一节的内容
    { journal_head; printf '%s\n' "$1"; journal_tail; } > "$P/tasks/2026-01-06-note/journal.md"
}
staged_run() { ( cd "$P" && git add -A ) >/dev/null 2>&1; run_staged "$P"; }

write_journal "- 改 A 必须同步 B"
out="$(staged_run)"
has "没有去向" "$out" "没写去向的提醒被报出来"

# 唯一写法：条目里有一行正好是 `去向: <docs|adr|memory|journal>`
write_journal "- 改 A 必须同步 B
  去向: docs"
out="$(staged_run)"
not "没有去向" "$out" "去向写在条目下一行也算"

write_journal "- 改 A 必须同步 B
  去向：docs"
out="$(staged_run)"
has "没有去向" "$out" "全角冒号不再被认成去向（写歪就是没写）"

write_journal "- 改 A 必须同步 B
  去向: pitfalls"
out="$(staged_run)"
has "没有去向" "$out" "去向必须是四种字面量之一"

write_journal "- 改 A 必须同步 B
  → docs"
out="$(staged_run)"
has "没有去向" "$out" "旧的箭头写法不再算去向"

write_journal "- 改 A 必须同步 B
  去向: docs
- 少写一条测试"
out="$(staged_run)"
has "少写一条测试" "$out" "多条目时逐条判，缺去向的那条被报出来"
not "改 A 必须同步 B" "$out" "已经写了去处的条目不再报"

write_journal "- 无"
out="$(staged_run)"
not "没有去向" "$out" "写「无」不算违规"

# 顿号 / 全角括号编号也要认作条目起始，否则整节被并成一条，静默免检
write_journal "1、第一条没有去向
2、第二条
  去向: journal
3）第三条也没有去向"
out="$(staged_run)"
has "第一条没有去向" "$out" "顿号编号的条目被单独检查"
has "第三条也没有去向" "$out" "全角括号编号的条目被单独检查"
not "第二条" "$out" "写了去向的顿号条目不被误报"

# 散文（没有条目符号）也要能在报错里看到原文，而不是空着
write_journal "这是一句散文，没有条目符号也没有去向"
out="$(staged_run)"
has "这是一句散文" "$out" "散文条目的报错带原文（不是空消息）"

# 头块里的 status 写歪 = 违规，并给出正确写法；没填 = 还没收尾，不查收尾字段
write_journal "- 无"
subst "$P/tasks/2026-01-06-note/journal.md" 's/^status: DONE$/status: done/'
out="$(staged_run)"
has "取值不对" "$out" "status 用小写是违规（大小写不兼容）"
has "status: DONE" "$out" "报错给出 status 的正确写法"

write_journal "- 无"
subst "$P/tasks/2026-01-06-note/journal.md" 's/^status: DONE$/status:/'
out="$(staged_run)"
not "取值不对" "$out" "status 留空 = 还没收尾，不算违规"
not '`commit:` 没填' "$out" "没收尾时不查 commit"

write_journal "- 无"
subst "$P/tasks/2026-01-06-note/journal.md" 's/^status: DONE$/status: DONE_WITH_CONCERNS/'
subst "$P/tasks/2026-01-06-note/journal.md" 's/^commit: abc1234$/commit:/'
out="$(staged_run)"
has '`commit:` 没填' "$out" "结束状态是 DONE 类时头块的 commit 必须回填"

echo "== R1: review.md 的字段契约（「填全」真的查了吗）=="
P="$TMP/r1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-07-rev" "$P/src"
plan_text T2 > "$P/tasks/2026-01-07-rev/plan.md"
echo "echo hi" > "$P/src/r.sh"

# 有 T2 任务、代码已在计划里、却没有裁决单
wip_commit "$P"                      # 计划先落盘（这时任务还没开工，不要求裁决单）
echo "echo hi" > "$P/src/a.sh"       # plan_text 的「相关文件」写的就是 src/a.sh
out="$(staged_run "$P")"
has "review.md" "$out" "提交计划范围内的代码时，T2 任务还没有裁决单要拦"

# 裁决单只有标题：整节留空照样不该过
review_text empty_原文 > "$P/tasks/2026-01-07-rev/review.md"
out="$(staged_run "$P")"
has "审查者原文" "$out" "「审查者原文」留空要拦（它才是「真的审过」的证据）"

review_text empty_结论 > "$P/tasks/2026-01-07-rev/review.md"
out="$(staged_run "$P")"
has "结论" "$out" "「结论」留空要拦"

review_text empty_审查者 > "$P/tasks/2026-01-07-rev/review.md"
out="$(staged_run "$P")"
has "审查者" "$out" "「审查者」留空要拦"

review_text > "$P/tasks/2026-01-07-rev/review.md"
out="$(staged_run "$P")"
not "review.md" "$out" "填全的裁决单不再被报"

sec "R2: plan.md 的目标与预估规模"
echo "== R2: plan.md 的目标与预估规模 =="
P="$TMP/r2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-08-plan"
plan_text T1 > "$P/tasks/2026-01-08-plan/plan.md"
subst "$P/tasks/2026-01-08-plan/plan.md" 's/^- \*\*目标\*\*: .*/- **目标**: 无/'
out="$(staged_run "$P")"
has "「目标」为空" "$out" "「目标」写「无」要拦（空目标的计划等于没计划）"

plan_text T1 > "$P/tasks/2026-01-08-plan/plan.md"
subst "$P/tasks/2026-01-08-plan/plan.md" 's/^- 新增文件: 无/- 新增文件:/; s/^- 修改文件: src\/a.sh/- 修改文件:/; s/^- 删除文件: 无/- 删除文件:/'
out="$(staged_run "$P")"
has "预估 diff 范围" "$out" "预估规模三行全空要拦"

plan_text T1 > "$P/tasks/2026-01-08-plan/plan.md"
out="$(staged_run "$P")"
not "预估 diff 范围" "$out" "填了预估规模的计划不再被报"

echo "== G-attack: 对抗性变体（每条都来自实跑里打穿过的写法）=="
P="$TMP/atk"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"

# 零宽字符 / -diff 属性 / 同名后缀 / 大写 .MD / 清理脚本
# （全角字母、全角括号、花式连字符**不在判据内**——见 check-gates.sh 的边界说明，
#  因此这里不写断言：写了就会逼着以后重新加映射表。）
printf 'x=1 # [DEBU\342\200\213G-zw]\n' > "$P/src/zw.py"
printf 'x=1 # [DEBUG\342\200\213-zw2]\n' > "$P/src/zw2.py"      # 插在 G 之后
printf 'x=1 # [DEBUG\357\273\277-zw3]\n' > "$P/src/zw3.py"      # BOM
printf 'x=1 # [DEBUG-diff]\n' > "$P/src/d.py"
printf '*.py -diff\n' >> "$P/.gitattributes"
printf 'x=1 # [DEBUG-suffix]\n' > "$P/src/my-check-gates.sh"
printf 'u=1 # [DEBUG-upper]\n' > "$P/src/UPPER.MD"
printf '# gate-b: mentions-marker\n# 清理脚本本体\ngrep -rn .\[DEBUG- src/\n' > "$P/scripts/clean-debug.sh"
out="$(staged_run "$P")"
has "zw.py" "$out" "零宽字符插在 DEBU 与 G 之间的调试标记要拦"
has "zw2.py" "$out" "零宽字符插在 G 与 - 之间的调试标记要拦"
has "zw3.py" "$out" "BOM 插在中间的调试标记要拦"
has "d.py" "$out" "「.gitattributes 标了 -diff」不能成为免死金牌"
has "my-check-gates.sh" "$out" "同名后缀的文件不豁免（排除项要写精确路径）"
not "UPPER.MD" "$out" "大写 .MD 是文档，不该当代码扫"
not "clean-debug.sh" "$out" "清理脚本首行声明 mentions-marker，整个文件豁免"

# 头块声明 T2、没有 plan.md、同一次提交 6 个代码文件
P="$TMP/atk2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-09-t2" "$P/src"
prd_text T2 > "$P/tasks/2026-01-09-t2/prd.md"
for i in 1 2 3 4 5 6; do printf 'x\n' > "$P/src/m$i.py"; done
out="$(staged_run "$P")"
has "没有 plan.md" "$out" "声明 T2 却没有计划，不能豁免规模底线"

# 头块写歪 = 违规，并给出正确写法（全角冒号 / 大小写变体都不再兼容）
P="$TMP/atk3"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-10-t3" "$P/src"
printf '<!-- gate\ntier\357\274\232 T3\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
echo "echo x" > "$P/src/x.sh"
out="$(staged_run "$P")"
has "gate 头块第 1 行写法不对" "$out" "头块里的全角冒号是违规（不再静默兼容）"
has '只认 `键: 值`' "$out" "报错说明唯一写法"

printf '<!-- gate\ntier: t3\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
out="$(staged_run "$P")"
has "取值不对" "$out" "头块里的 t3（小写）是违规（大小写不兼容）"
has '正确写法 `tier: T2`' "$out" "报错给出 tier 的正确写法"

# 头块的其余写法违规：没闭合 / 不在第一行 / 不认识的键 / 同一个键写两遍
printf '<!-- gate\ntier: T3\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
out="$(staged_run "$P")"
has "没有闭合" "$out" "缺 `-->` 要报"
not "缺「## 验收标准」" "$out" "头块没闭合时只报这一个原因（不连带报缺节）"

printf '# 需求\n\n<!-- gate\ntier: T3\n-->\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
out="$(staged_run "$P")"
has "必须在文件第一行" "$out" "头块不在第一行要报"

printf '<!-- gate\ntier: T3\nstatus: DONE\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
out="$(staged_run "$P")"
has "不认键" "$out" "prd 头块里写 journal 的键要报"

printf '<!-- gate\ntier: T3\ntier: T3\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3/prd.md"
out="$(staged_run "$P")"
has "写了两遍" "$out" "同一个键写两遍要报"

# 散文里写档位不再被读：6 个代码文件照样触发规模底线
P="$TMP/atk3b"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-10-t3b" "$P/src"
printf '# 需求\n\n档位: T3\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-10-t3b/prd.md"
for i in 1 2 3 4 5 6; do printf 'x\n' > "$P/src/n$i.py"; done
out="$(staged_run "$P")"
has "没有声明 T2/T3" "$out" "散文里的「档位: T3」不再算声明"

# 任务目录里的文件名不在约定里
P="$TMP/atk4"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-11-skip"
printf '# 随便\n\n没有类型字段\n' > "$P/tasks/2026-01-11-skip/100-x.md"
out="$(staged_run "$P")"
# 三位以上数字开头按 tasks/README.md 的约定是笔记：只提示，不算违规。
has "当笔记处理" "$out" "3 位编号的文件按笔记处理（有提示，不静默）"
not "不认识的任务文件名" "$out" "笔记文件名不报违规"

printf '# 随便\n\n没有类型字段\n' > "$P/tasks/2026-01-11-skip/upper.MD"
out="$(staged_run "$P")"
has "不认识的任务文件名" "$out" "真·不认识的文件名（大写 .MD）要报出来"

# 链接变体
P="$TMP/atk5"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/docs"
{ printf '\n'
  printf -- '- 锚点：`docs/nope.md#section`\n'
  printf -- '- 标题：[x](docs/nope2.md "title")\n'
  printf -- '- 查询：`docs/nope4.md?x=1`\n'
} >> "$P/AGENTS.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "docs/nope.md" "$out" "带 #锚点 的断链要报"
has "docs/nope2.md" "$out" "带链接标题的断链要报"
has "docs/nope4.md" "$out" "带查询串的断链要报"

sec "G-extra: 复核抓到的假阴性 / 假阳性"
echo "== G-extra: 复核抓到的假阴性 / 假阳性 =="

# 列表形态的「无」不能算已填
P="$TMP/ex1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-12-rel"
plan_text T1 > "$P/tasks/2026-01-12-rel/plan.md"
subst "$P/tasks/2026-01-12-rel/plan.md" 's|^  - src/a.sh$|  - 无|'
out="$(staged_run "$P")"
has "没有一个像路径的条目" "$out" "「相关文件」写成列表形态的「无」要拦"

# 目标的「非目标」顶替
P="$TMP/ex2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-13-shadow"
plan_text T1 > "$P/tasks/2026-01-13-shadow/plan.md"
subst "$P/tasks/2026-01-13-shadow/plan.md" 's|^- \*\*目标\*\*: .*|- **非目标**: 这次什么都不做|'
out="$(staged_run "$P")"
has "「目标」为空" "$out" "「非目标」不能顶替「目标」"

# 架构表里的双斜杠 / 内部点段
P="$TMP/ex3"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src/auth" && echo x > "$P/src/auth/a.py"
printf '%s\n' '# 架构' '' '## 模块划分' '' '| 模块 | 路径 | 负责人 |' '|---|---|---|' '| 认证 | `src//auth` | 我 |' > "$P/docs/architecture.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "模块表里没有它" "$out" "src//auth 与 src/auth 等价"
printf '%s\n' '# 架构' '' '## 模块划分' '' '| 模块 | 路径 | 负责人 |' '|---|---|---|' '| 认证 | `src/./auth` | 我 |' > "$P/docs/architecture.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "模块表里没有它" "$out" "src/./auth 与 src/auth 等价"

# 预估 diff 三行都写「无」是合法写法
P="$TMP/ex4"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-14-diff"
plan_text T1 > "$P/tasks/2026-01-14-diff/plan.md"
# 三行**全部**写「无」（纯文档任务的真实形态）——这里必须真的三行都改成「无」，
# 只改一行的话测的是「至少一行有内容」这条旧路径。
subst "$P/tasks/2026-01-14-diff/plan.md" 's|^- 新增文件: 无|- 新增文件: 无|; s|^- 修改文件: src/a.sh|- 修改文件: 无|'
out="$(staged_run "$P")"
not "预估 diff 范围" "$out" "预估 diff 三行全写「无」是合法写法（纯文档 / 纯配置任务）"

plan_text T1 > "$P/tasks/2026-01-14-diff/plan.md"
subst "$P/tasks/2026-01-14-diff/plan.md" 's|^- 新增文件: 无|- 新增文件:|; s|^- 修改文件: src/a.sh|- 修改文件:|; s|^- 删除文件: 无|- 删除文件:|'
out="$(staged_run "$P")"
has "预估 diff 范围" "$out" "三行值全空仍要拦（对照组）"

# 散文里提到 T2 不能改变档位（也就不能换来规模豁免）
P="$TMP/ex5"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-15-annot" "$P/src"
plan_text T1 > "$P/tasks/2026-01-15-annot/plan.md"
printf '\n档位: T2 只是备注，真要升档得改头块的 tier。\n' >> "$P/tasks/2026-01-15-annot/plan.md"
for i in 1 2 3 4; do printf 'x\n' > "$P/src/z$i.py"; done
out="$(staged_run "$P")"
has "没有声明 T2/T3" "$out" "散文里提到 T2 不算声明，规模底线仍生效"

sec "G-idx: 检查内容必须等于提交内容"
echo "== G-idx: 检查内容必须等于提交内容 =="
P="$TMP/idx1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-16-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-16-t2/plan.md"
wip_commit "$P"
# 索引里有、物化树里没有（skip-worktree 正是稀疏检出的实现方式）
( cd "$P" && git update-index --skip-worktree README.md )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"; rc=$?
has "无法可信地物化" "$out" "skip-worktree 让文件缺失时必须中止，不能静默跳过"
if [ "$rc" -eq 2 ]; then ok "物化不可信时退出码是 2（环境问题，不是内容违规）"; else no "物化不可信时退出码是 2（实际 $rc）"; fi
( cd "$P" && git update-index --no-skip-worktree README.md )

# smudge 过滤器：索引里是原文，物化出来是另一份 —— 检查器看到的是假的那份
printf 'AAA\n' > "$P/data.txt"
( cd "$P" && git add data.txt && git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -qm data >/dev/null
  echo 'data.txt filter=smudge' > .git/info/attributes
  git config filter.smudge.clean 'cat'
  git config filter.smudge.smudge 'sed s/AAA/BBB/'
  git rm -q --cached data.txt && git add data.txt )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"; rc=$?
has "物化出来的内容与索引 blob 不同" "$out" "smudge 过滤器改写内容时必须中止（索引里是原文，检查器看到的是洗白版）"
if [ "$rc" -eq 2 ]; then ok "smudge 场景退出码是 2"; else no "smudge 场景退出码是 2（实际 $rc）"; fi
( cd "$P" && git config --unset filter.smudge.smudge && rm -f .git/info/attributes && git reset -q )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"; rc=$?
not "无法可信地物化" "$out" "恢复标记后闸门正常工作"
if [ "$rc" -eq 0 ]; then ok "恢复标记后退出码回到 0"; else no "恢复标记后退出码回到 0（实际 $rc）"; fi

sec "G-pristine: 全新项目零改动必须全绿"
echo "== G-pristine: 全新项目零改动必须全绿 =="
P="$TMP/pst"; new_project "$P" || { echo "建项目失败"; exit 2; }
( cd "$P" && git add -A )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then ok "全新项目 --staged 零违规"; else no "全新项目 --staged 零违规（实际 $rc）"; printf '%s\n' "$out" | head -5; fi
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then ok "全新项目全量自查零违规"; else no "全新项目全量自查零违规（实际 $rc）"; printf '%s\n' "$out" | head -5; fi

sec "G-first: 尚无 HEAD 的首次提交也必须零违规"
echo "== G-first: 尚无 HEAD 的首次提交也必须零违规 =="
P="$TMP/first"; rm -rf "$P"
( cd "$TMP" && "$B" "$INIT" first >/dev/null 2>&1 )
( cd "$P" && git add -A )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"; rc=$?
if [ "$rc" -eq 0 ]; then ok "无 HEAD 时 --staged 通过"; else no "无 HEAD 时 --staged 通过（实际 $rc）"; printf '%s\n' "$out" | head -5; fi
( cd "$P" && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 )
if [ "$( cd "$P" && git rev-list --count HEAD 2>/dev/null )" = "1" ]; then ok "首次提交成功（钩子也过）"; else no "首次提交成功"; fi

echo "== G-rootref: 不带 / 的引用是**已知边界**（断言它不被报）=="
P="$TMP/rr1"; new_project "$P" || { echo "建项目失败"; exit 2; }
printf '\n参见 \140NOTHERE.md\140。\n' >> "$P/AGENTS.md"
out="$( cd "$P" && git add -A && "$B" scripts/check-gates.sh --staged 2>&1 )"
not "NOTHERE.md" "$out" "根级引用不查（模板自己的示例名会红，这是有意的边界）"

sec "G-fw: tab 注释与单引号"
echo "== G-fw: tab 注释与单引号 =="
P="$TMP/fw1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'grep -q foo f\t# [DEBUG-tab]\n' > "$P/src/tabcomment.js"
printf '#!/bin/sh\n# gate-b: mentions-marker\ngrep -E "foo|\\[DEBUG-" src/\n' > "$P/scripts/squote.sh"
printf '#!/bin/sh\n# 说明这一行\n# gate-b: mentions-marker\ngrep -E "foo|\\[DEBUG-" src/\n' > "$P/scripts/squote2.sh"
out="$(staged_run "$P")"
has "tabcomment.js" "$out" "tab 后的行尾注释里的 marker 也要报"
not "squote.sh" "$out" "shebang 之后第二行的声明有效（可执行脚本的唯一出口）"
has "squote2.sh" "$out" "声明被挤到第三行就无效（只认 shebang 之后那一行）"

sec "G-adr-bold: 加粗字段 / 根级断链 / 百分号 / 验证结果占位符"
echo "== G-adr-bold: 加粗字段 / 根级断链 / 百分号 / 验证结果占位符 =="
P="$TMP/adb"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/docs/adr" "$P/docs"
printf '# 甲\n\n- **Status**: accepted\n' > "$P/docs/adr/0001-a.md"
printf '# 乙\n\n- **Status**: accepted\n- **Supersedes**: ADR-0099\n' > "$P/docs/adr/0002-b.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "ADR-0099" "$out" "加粗的 Supersedes 也要检查引用的文件是否存在"

# 不带 `/` 的根级引用**不查**：模板自己的示例名（`0001-slug.md`、`NN-描述.md`）
# 会被判断链，新项目一生成就红。这条边界写进 AGENTS.md，不在这里断言。

P="$TMP/adb3"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/docs" && echo x > "$P/docs/我 的.md"
printf '\n[看](docs/%%E6%%88%%91%%20%%E7%%9A%%84.md)\n' >> "$P/docs/commands.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "我 的" "$out" "百分号编码的中文文件名不该被误报断链"

sec "G-hdr: 文件头声明豁免（无声明 / 首行声明 / 写歪的声明）"
echo "== G-hdr: 文件头声明豁免（无声明 / 首行声明 / 写歪的声明） =="
P="$TMP/hdr1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'const a = "[DEBUG-1]";\n' > "$P/src/undecl.js"
printf '# gate-b: mentions-marker\nconst b = "[DEBUG-2]";\ngrep -q "[DEBUG-3]" f\n' > "$P/src/decl.js"
printf '# gate-b: mentions-marker \nconst c = "[DEBUG-4]";\n' > "$P/src/trail.js"
printf '# gate-b: mentions marker\nconst d = "[DEBUG-5]";\n' > "$P/src/alt.js"
out="$(staged_run "$P")"
has "undecl.js" "$out" "无声明文件里的 marker = 违规"
not "src/decl.js" "$out" "第一行精确声明 = 整文件豁免（字符串里的 marker 也不报）。注：必须带 src/ 前缀——`grep -F decl.js` 会匹配到 undecl.js 的违规行，产生假失败"
has "trail.js" "$out" "声明行尾多一个空白 = 声明无效"
has "alt.js" "$out" "写法差一点（mentions marker，少了冒号）= 声明无效"

sec "G-prefix: 内容里有时间戳 / 工具行不再豁免"
echo "== G-prefix: 内容里有时间戳 / 工具行不再豁免 =="
P="$TMP/px1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'console.log("[DEBUG-x]", "12:30:45");\n' > "$P/src/ts.js"
printf 'grep -q "foo\\"|\\[DEBUG-" f\n' > "$P/scripts/esc2.sh"
printf 'VAR=1 VAR2=2 grep -q "[DEBUG-x]" f\n' > "$P/scripts/assign2.sh"
out="$(staged_run "$P")"
has "ts.js" "$out" "内容里带时间戳不能把 marker 吞进前缀"
has "esc2.sh" "$out" "工具行的引号 / 转义不再豁免（无声明 = 违规）"
has "assign2.sh" "$out" "赋值前缀的 grep 不再豁免（无声明 = 违规）"

sec "G-dash: 工具行豁免废除（包装器 / 引号 / 赋值前缀都要声明）"
echo "== G-dash: 工具行豁免废除（包装器 / 引号 / 赋值前缀都要声明） =="
P="$TMP/ds1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'grep -q foo\\|\\[DEBUG- f\n' > "$P/scripts/esc.sh"
printf 'sudo -u root grep -q "[DEBUG-x]" f\n' > "$P/scripts/sudo.sh"
printf 'git -C dir grep -q "[DEBUG-x]" f\n' > "$P/scripts/gitc.sh"
printf '# gate-b: mentions-marker\nsudo -u root grep -q "[DEBUG-x]" f\n' > "$P/scripts/decl.sh"
out="$(staged_run "$P")"
has "esc.sh" "$out" "找标记的工具行无声明也违规"
has "sudo.sh" "$out" "sudo -u root 前缀不再是豁免（无声明 = 违规）"
has "gitc.sh" "$out" "git -C dir 前缀不再是豁免（无声明 = 违规）"
not "scripts/decl.sh" "$out" "同样的工具行加了首行声明就整文件豁免（带路径前缀，避免误配其他文件名）"

sec "G-exempt3: 声明豁免 / 报告路径"
echo "== G-exempt3: 声明豁免 / 报告路径 =="
P="$TMP/ex10"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'grep -q "a|\\[DEBUG-" f\n' > "$P/scripts/q1.sh"
printf 'FOO=1 grep -q "[DEBUG-x]" f\n' > "$P/scripts/q3.sh"
printf 'grep -q foo f & echo "[DEBUG-1] x"\n' > "$P/src/amp.js"
printf 'grep -q "[DEBUG-" f && echo "[DEBUG-2] x"\n' > "$P/src/chain.js"
printf 'const s = "[DEBUG-x]";\n' > "$P/src/中文.js"
out="$(staged_run "$P")"
has "q1.sh" "$out" "引号里的 | 不再换来豁免（无声明 = 违规）"
has "q3.sh" "$out" "FOO=1 grep 不再豁免（无声明 = 违规）"
has "amp.js" "$out" "单个 & 之后还有 marker 要报"
has "chain.js" "$out" "&& 之后的 echo 里还有 marker 要报"
has "src/中文.js" "$out" "报告里的路径要保留原文（归一化只作用于内容）"

echo "== G-loc: LC_ALL=C 下同样有效 + 预筛间隙 =="
P="$TMP/lc1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src"
printf 'const a = "[DEB\342\200\213UG-1]";\n' > "$P/src/zw-bug.js"
printf 'const b = "[DEBU\342\201\245G-2]";\n' > "$P/src/u2065.js"
printf 'const c = "[DE\342\200\213BUG-3]";\n' > "$P/src/zw-de.js"
# 12 字节间隙（4 个汉字）：预筛若限长度，归一化根本没机会跑
printf 'const d = "[DE\344\270\255\346\226\207\344\270\255\346\226\207BUG-4]";\n' > "$P/src/gap.js"
git -C "$P" add -A
out="$( cd "$P" && LC_ALL=C "$B" scripts/check-gates.sh --staged 2>&1 )"
has "zw-bug.js" "$out" "LC_ALL=C 下零宽变体仍要拦（连字符替换不能写字节类）"
has "u2065.js" "$out" "LC_ALL=C 下 U+2065 仍要拦"
has "zw-de.js" "$out" "LC_ALL=C 下零宽插在 D/E 之间仍要拦"
has "gap.js" "$out" "预筛间隙不限长度（12 字节间隙也要进候选）"

sec "G-exempt2: 有声明的工具行 / staged 与工作区各读各的"
echo "== G-exempt2: 有声明的工具行 / staged 与工作区各读各的 =="
P="$TMP/ex9"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
printf 'grep -q foo debug.txt && echo "[DEBUG-1] x"\n' > "$P/src/and-echo.js"
printf '# gate-b: mentions-marker\nLC_ALL=C grep -q "[DEBUG-x]" f\n' > "$P/scripts/clean-lc.sh"
printf '# gate-b: mentions-marker\ncommand grep -q "[DEBUG-x]" f\n' > "$P/scripts/clean-cmd.sh"
out="$(staged_run "$P")"
has "and-echo.js" "$out" "无声明文件里 && 之后的 marker 要报"
not "clean-lc.sh" "$out" "首行声明的 LC_ALL=C grep 整文件豁免"
not "clean-cmd.sh" "$out" "首行声明的 command grep 整文件豁免"

# staged 的豁免读索引、全量的豁免读工作区——两边可以不一致
P="$TMP/ex12"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/scripts"
printf '# gate-b: mentions-marker\ngrep -q "[DEBUG-x]" f\n' > "$P/scripts/idxhdr.sh"
( cd "$P" && git add -A )
printf 'no header\ngrep -q "[DEBUG-x]" f\n' > "$P/scripts/idxhdr.sh"
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
not "idxhdr.sh" "$out" "staged 的豁免看索引第一行（工作区改掉不算）"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "idxhdr.sh" "$out" "全量的豁免看工作区第一行（改掉就报）"

sec "G-tier-head: prd / 切片的档位也取三版本"
echo "== G-tier-head: prd / 切片的档位也取三版本 =="
P="$TMP/th1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-25-t" "$P/src"
prd_text T2 > "$P/tasks/2026-01-25-t/prd.md"
plan_text T1 > "$P/tasks/2026-01-25-t/plan.md"
wip_commit "$P"
# 工作区把 prd 头块的 tier 改成 T1（不 stage），HEAD 里仍是 T2
prd_text T1 > "$P/tasks/2026-01-25-t/prd.md"
( cd "$P" && printf 'echo a\n' > src/a.sh && git add src/a.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "prd.md 的 T2 在 HEAD 里，工作区改小也躲不过"

sec "G-tier-note: journal 不是档位来源"
echo "== G-tier-note: journal 不是档位来源 =="
P="$TMP/tn1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-26-t" "$P/src"
plan_text T1 > "$P/tasks/2026-01-26-t/plan.md"
printf '# 日志\n\n档位: T2（散文，不是头块）\n' > "$P/tasks/2026-01-26-t/journal.md"
wip_commit "$P"
( cd "$P" && printf 'echo a\n' > src/a.sh && git add src/a.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
not "review.md" "$out" "journal 里的档位散文不触发审查（它不是档位来源）"

echo "== G-norm: 归一化（控制字符 / 未列出的格式字符 / locale）=="
P="$TMP/nm1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src"
printf 'const a = "[DE\001BUG-1]";\n' > "$P/src/soh-in.js"
printf 'const b = "[DEBUG\001-2]";\n' > "$P/src/soh-after.js"
printf 'const c = "[DEBU\335\234G-3]";\n' > "$P/src/u061c.js"
printf 'const d = "[DEBUG\343\200\200-4]";\n' > "$P/src/ideosp.js"
out="$(staged_run "$P")"
has "soh-in.js" "$out" "ASCII 控制字符插在 DEBUG 内部要拦"
has "soh-after.js" "$out" "控制字符插在连字符前要拦"
has "u061c.js" "$out" "未列出的 Unicode 格式字符（U+061C）要拦"
has "ideosp.js" "$out" "全角空格当连字符前的空白也要拦"
# LC_ALL=C 下行为一致（CI 常用 C locale）
( cd "$P" && LC_ALL=C "$B" scripts/check-gates.sh --staged ) | grep -q "u061c.js" \
    && ok "LC_ALL=C 下同样拦（判据不依赖 locale）" || no "LC_ALL=C 下同样拦"

P="$TMP/nm2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src"
printf 'const x = "[DEBUG-1]";\n' > "$P/x.apk"
printf 'const y = "[DEBUG-2]";\n' > "$P/y.o"
printf 'const z = "[DEBUG-3]";\n' > "$P/z.tar"
out="$(staged_run "$P")"
not "x.apk" "$out" "归档/目标文件后缀（.apk）不参与闸门 B"
not "y.o" "$out" "目标文件后缀（.o）不参与闸门 B"
not "z.tar" "$out" "归档后缀（.tar）不参与闸门 B"

sec "G-adr-fmt: ADR 编号必须是 4 位"
echo "== G-adr-fmt: ADR 编号必须是 4 位 =="
P="$TMP/ad1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/docs/adr"
printf '# 甲\n\nStatus: accepted\n' > "$P/docs/adr/0001-a.md"
printf '# 乙\n\nStatus: accepted\nSupersedes: ADR-00012\n' > "$P/docs/adr/0002-b.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "编号必须是 4 位" "$out" "5 位编号不能被静默截成 4 位"
n="$(printf '%s' "$out" | grep -c '编号必须是 4 位')"
if [ "$n" -le 1 ]; then ok "同一处编号只报一次"; else no "同一处编号只报一次（实际 $n 次）"; fi

sec "G-hookmode: 钩子缺失与可执行位"
echo "== G-hookmode: 钩子缺失与可执行位 =="
P="$TMP/hm1"; new_project "$P" || { echo "建项目失败"; exit 2; }
( cd "$P" && rm -f .githooks/pre-merge-commit )
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
has "有缺失" "$out" "工作区缺 pre-merge-commit 时全量自查要判失败（否则 merge 不经过任何检查）"
if [ "$rc" -eq 1 ]; then ok "缺 merge 钩子时退出码 1"; else no "缺 merge 钩子时退出码 1（实际 $rc）"; fi

sec "G-revdel: 删掉裁决单也要拦"
echo "== G-revdel: 删掉裁决单也要拦 =="
P="$TMP/rd1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-24-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-24-t2/plan.md"
review_text > "$P/tasks/2026-01-24-t2/review.md"
wip_commit "$P"
( cd "$P" && git rm -q tasks/2026-01-24-t2/review.md )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "不能删" "$out" "T2 任务把 review.md 删掉的提交要拦"

sec "G-resid: 闸门 B 的残余变体"
echo "== G-resid: 闸门 B 的残余变体 =="
P="$TMP/rs1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/scripts"
# 两个不可见字符同时打断 BUG 与 DEB
printf 'const a = "[DE\342\200\213B\342\200\213UG-1]";\n' > "$P/src/two-zw.js"
# U+180E（蒙古文元音分隔符）
printf 'const b = "[DEBU\341\240\216G-2]";\n' > "$P/src/u180e.js"
# 归档里的标记不该被当成残留（.tar 不在后缀排除表里会把提交永久卡死）
printf 'const x = "[DEBUG-1]";\n' > "$P/a.js"
( cd "$P" && tar cf src/mini.tar a.js && rm -f a.js )
# 带声明的找标记脚本（工具行豁免已废除，声明是唯一出路）
printf '# gate-b: mentions-marker\nenv FOO=1 grep -n .\\[DEBUG- src/two-zw.js\n' > "$P/scripts/clean2.sh"
out="$(staged_run "$P")"
has "two-zw.js" "$out" "两个不可见字符同时打断 BUG/DEB 也要拦"
has "u180e.js" "$out" "U+180E 插在 BUG 里也要拦"
not "mini.tar" "$out" "压缩包里的标记不参与闸门 B（否则提交永远红）"
not "clean2.sh" "$out" "首行声明的 env VAR=1 grep 整文件豁免"

sec "G-union: tier 与相关文件对三个版本取并集"
echo "== G-union: tier 与相关文件对三个版本取并集 =="
P="$TMP/un1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-22-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-22-t2/plan.md"
wip_commit "$P"
# HEAD 是 T2；把索引里的计划降成 T1（相关文件留着），再提交范围内的代码
plan_text T1 > "$P/tasks/2026-01-22-t2/plan.md"
( cd "$P" && printf 'echo a\n' > src/a.sh && git add src/a.sh tasks/2026-01-22-t2/plan.md )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "HEAD 里的 T2 声明不能被索引里的 T1 洗掉"

P="$TMP/un2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-23-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-23-t2/plan.md"
wip_commit "$P"
# 索引里仍是 src/a.sh；工作区把「相关文件」改成 src/b.sh（不 stage），只提交 src/b.sh
subst "$P/tasks/2026-01-23-t2/plan.md" 's|src/a.sh|src/b.sh|g'
( cd "$P" && printf 'echo b\n' > src/b.sh && git add src/b.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "工作区版本的相关文件同样算归属"

sec "G-case: 闸门 B 大小写与 BUG 内部的零宽"
echo "== G-case: 闸门 B 大小写与 BUG 内部的零宽 =="
P="$TMP/ca1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src"
printf 'const a = "[debug-x]";\n' > "$P/src/lower.js"
printf 'const b = "[DEB\342\200\213UG-x]";\n' > "$P/src/zw-bug.js"
printf 'const c = "[DEBU\342\200\213G-x]";\n' > "$P/src/zw-ug.js"
out="$(staged_run "$P")"
has "lower.js" "$out" "小写 [debug-x] 也要拦（说法是大小写不敏感）"
has "zw-bug.js" "$out" "零宽插在 BUG 内部也要拦"
has "zw-ug.js" "$out" "零宽插在 U/G 之间也要拦"

sec "G-hp: core.hooksPath 的等价写法与钩子缺失"
echo "== G-hp: core.hooksPath 的等价写法与钩子缺失 =="
P="$TMP/hp1"; new_project "$P" || { echo "建项目失败"; exit 2; }
( cd "$P" && git config core.hooksPath .githooks/ )
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
not "core.hooksPath 不是" "$out" "`.githooks/`（尾斜杠）是等价写法，不该提示没装钩子"
if [ "$rc" -eq 0 ]; then ok "尾斜杠写法下全量自查通过"; else no "尾斜杠写法下全量自查通过（实际 $rc）"; fi
( cd "$P" && git config core.hooksPath .githooks && git rm -q --cached .githooks/pre-commit )
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"; rc=$?
has "有缺失" "$out" "钩子不在索引里要判失败（不只是提示）"
if [ "$rc" -eq 1 ]; then ok "钩子缺失时退出码 1"; else no "钩子缺失时退出码 1（实际 $rc）"; fi

sec "G-planonly: 只提交计划不该被 review 拦"
echo "== G-planonly: 只提交计划不该被 review 拦 =="
P="$TMP/po1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-17-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-17-t2/plan.md"
out="$(staged_run "$P")"
not "review.md" "$out" "T2 只提交 plan.md（还没开工）不要求裁决单 —— 否则「先提交计划」这条路被堵死"

# 「开工」的依据也只有 gate 头块：头块宣告结束状态 = 已开工，裁决单躲不掉；
# 头块 status 留空、或只在正文里写结束状态，都还算计划阶段。
printf '<!-- gate\nstatus: DONE\ncommit: abc1234\nrejections: 0\n-->\n\n# 执行日志\n' > "$P/tasks/2026-01-17-t2/journal.md"
out="$(staged_run "$P")"
has "review.md" "$out" "journal 头块宣告 DONE = 已开工，T2 必须有裁决单"

printf '<!-- gate\nstatus:\ncommit:\nrejections: 0\n-->\n\n# 执行日志\n' > "$P/tasks/2026-01-17-t2/journal.md"
out="$(staged_run "$P")"
not "review.md" "$out" "journal 头块 status 留空 = 还没收尾，不要求裁决单"

printf '# 执行日志\n\n## 结束状态\n\n- **结束状态**: `DONE`\n' > "$P/tasks/2026-01-17-t2/journal.md"
out="$(staged_run "$P")"
not "review.md" "$out" "正文里写结束状态不再算开工依据（只读头块）"

sec "G-crlf: 行尾 CR 不能让判定变样（MSYS 会吞，Linux / macOS 不会）"
echo "== G-crlf: 行尾 CR 不能让判定变样 =="
P="$TMP/crlf"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-28-t2"
plan_text T2 > "$P/tasks/2026-01-28-t2/plan.md"
# awk 造 CRLF：macOS 的 sed 不认替换里的 \r，BSD / GNU 都吃 awk 这条路
awk 'BEGIN{ORS="\r\n"}{print}' "$P/tasks/2026-01-28-t2/plan.md" > "$P/tasks/2026-01-28-t2/p.tmp" &&
    mv "$P/tasks/2026-01-28-t2/p.tmp" "$P/tasks/2026-01-28-t2/plan.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "起始行写法不对" "$out" "CRLF 的 plan.md：头块照样认得（行尾 CR 不算多余空白）"
not "档位未声明" "$out" "CRLF 的 plan.md：tier 读得到"
# 开工判定的 grep 也是行首行尾锚定，同样不能被 CR 打断
printf '<!-- gate\r\nstatus: DONE\r\ncommit: abc1234\r\nrejections: 0\r\n-->\r\n\r\n# 执行日志\r\n' > "$P/tasks/2026-01-28-t2/journal.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "review.md" "$out" "CRLF 的 journal 头块 status 照样算开工（T2 要裁决单）"

sec "G-prdopt: prd.md 的 tier 可选，但填了就要合法"
echo "== G-prdopt: prd.md 的 tier 可选，但填了就要合法 =="
P="$TMP/prdopt"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-29-prd"
# 计划阶段的正常形态：prd 先落盘、档位在 Step 3.3 才定，头块里留空
printf '<!-- gate\ntier:\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-29-prd/prd.md"
out="$(staged_run "$P")"
not "档位" "$out" "prd.md 头块 tier 留空不报（档位 3.3 才定）"
not "gate 头块" "$out" "prd.md 的空头块本身不是语法错误"
# 填了就按值域判
printf '<!-- gate\ntier: T9\n-->\n\n# 需求\n\n## 验收标准\n\n- 能跑\n' > "$P/tasks/2026-01-29-prd/prd.md"
out="$(staged_run "$P")"
has "取值不对" "$out" "prd.md 头块 tier 写错值要报"

sec "G-scope: 审查归属取 HEAD ∪ 索引 ∪ 工作区"
echo "== G-scope: 审查归属取 HEAD ∪ 索引 ∪ 工作区 =="
P="$TMP/su1"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-18-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-18-t2/plan.md"
wip_commit "$P"
# 计划从索引里消失、只提交计划范围内的代码
( cd "$P" && git rm -q --cached tasks/2026-01-18-t2/plan.md && printf 'echo a\n' > src/a.sh && git add src/a.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "计划被移出索引后，范围内的代码仍要求裁决单（HEAD 里还有那份计划）"
( cd "$P" && git reset -q && git checkout -- tasks/2026-01-18-t2/plan.md 2>/dev/null )

# 计划只写在工作区、根本没 git add —— 归属照样要生效（这一条以前漏掉：find 扫的是物化树）
P="$TMP/su2"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-19-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-19-t2/plan.md"
( cd "$P" && printf 'echo a\n' > src/a.sh && git add src/a.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "计划没 git add 也要算归属（工作区也是候选来源）"

# 「相关文件」不在 src 下（scripts/）同样要归属
P="$TMP/su3"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-20-t2" "$P/scripts"
plan_text T2 > "$P/tasks/2026-01-20-t2/plan.md"
subst "$P/tasks/2026-01-20-t2/plan.md" 's|src/|scripts/|g'
wip_commit "$P"
# 计划的「相关文件」经上面的 sed 已变成 scripts/a.sh，提交的必须是同一个文件
( cd "$P" && printf '#!/bin/sh\n' > scripts/a.sh && git add scripts/a.sh )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "归属不限 MODULE_ROOT（scripts/ 下的文件同样要审查）"

# 文件名带空格：整行候选也要能匹配上
P="$TMP/su4"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/tasks/2026-01-21-t2" "$P/src"
plan_text T2 > "$P/tasks/2026-01-21-t2/plan.md"
subst "$P/tasks/2026-01-21-t2/plan.md" 's|src/a.sh|src/我的 文件.js|g'
wip_commit "$P"
( cd "$P" && printf 'x\n' > "src/我的 文件.js" && git add "src/我的 文件.js" )
out="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 )"
has "review.md" "$out" "带空格的文件名不能因为按空格切词而逃过归属检查"
# 同一条违规不该打印两次
n="$( cd "$P" && "$B" scripts/check-gates.sh --staged 2>&1 | grep -c '本次提交的' )"
if [ "$n" -le 1 ]; then ok "同一任务的归属违规只报一次"; else no "同一任务的归属违规只报一次（实际 $n 次）"; fi

echo "== G-env: 模块根缺失与钩子丢失要说出来（只提示，不拦）=="
P="$TMP/genv"; new_project "$P" || { echo "建项目失败"; exit 2; }

# init.sh 会建空 src/，但 git 不跟踪空目录 —— 模拟 clone 之后的样子
rmdir "$P/src" 2>/dev/null || true
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "模块根" "$out" "模块根不存在时给出提示（否则闸门全绿但什么都没查）"
( cd "$P" && "$B" scripts/check-gates.sh >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "模块根提示不影响退出码" || no "模块根提示把退出码变成了 $rc"

mkdir -p "$P/src"
( cd "$P" && git config core.hooksPath other-hooks ) >/dev/null 2>&1
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "core.hooksPath" "$out" "钩子目录不是 .githooks 时提示（钩子丢了是静默的）"
( cd "$P" && git config core.hooksPath .githooks ) >/dev/null 2>&1
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "core.hooksPath" "$out" "设置正确后不再提示"

sec "G-dcount: 活文档里不许写死 fixture 的断言项数"
echo "== G-dcount: 活文档里不许写死 fixture 的断言项数 =="
P="$TMP/dcount"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src" "$P/tasks/2026-01-22-old"
# 文档里写死项数 → 报（数字每加一条断言就漂一次，钩子里没法核对真实值）
printf '\n先跑 \140bash scripts/fixtures/gate-test.sh\140 —— 187 项。\n' >> "$P/docs/architecture.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
has "写死了 fixture 的断言项数" "$out" "活文档里写死项数要报"
# 只写时长 → 不报
subst "$P/docs/architecture.md" 's/187 项/约 12 分钟/'
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "写死了 fixture 的断言项数" "$out" "只写时长不报"
# 任务目录是快照，不查
printf '\n本次跑了 \140scripts/fixtures/gate-test.sh\140，187 项全过。\n' >> "$P/tasks/2026-01-22-old/journal.md"
out="$( cd "$P" && "$B" scripts/check-gates.sh 2>&1 )"
not "写死了 fixture 的断言项数" "$out" "任务目录是快照，里面的项数不查"

sec "G-prepush: 推送前补跑全量自查"
echo "== G-prepush: 推送前补跑全量自查（cherry-pick / rebase / am 没有钩子入口）=="
P="$TMP/prepush"; new_project "$P" || { echo "建项目失败"; exit 2; }
mkdir -p "$P/src"
# 造一条「绕过 pre-commit」的违规：残留调试标记。真实场景里这种提交由
# cherry-pick / rebase / am 带进来，那三条路径不调用任何钩子。
printf 'const x = 1; // [DEBUG-x]\n' > "$P/src/app.js"
wip_commit "$P"
hook="$P/.githooks/pre-push"
local_sha="$( cd "$P" && git rev-parse HEAD )"
# git 通过 stdin 喂 <local ref> <local sha> <remote ref> <remote sha>
out="$( cd "$P" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "$local_sha" | sh "$hook" 2>&1 )"
has "推送被拦下" "$out" "有违规时拒绝推送"
( cd "$P" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "$local_sha" | sh "$hook" >/dev/null 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && ok "拒绝推送的退出码非零（实际 $rc）" || no "有违规时退出码是 0，推送会成功"
# 删远端分支：local sha 全零，没有内容可查
out="$( cd "$P" && printf 'refs/heads/gone 0000000000000000000000000000000000000000 refs/heads/gone %s\n' "$local_sha" | sh "$hook" 2>&1 )"
( cd "$P" && printf 'refs/heads/gone 0000000000000000000000000000000000000000 refs/heads/gone %s\n' "$local_sha" | sh "$hook" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "删除远端分支时不做检查" || no "删除远端分支被拦下了（退出码 $rc）"
# 清掉违规后放行
printf 'const x = 1;\n' > "$P/src/app.js"
wip_commit "$P"
out="$( cd "$P" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "$local_sha" | sh "$hook" 2>&1 )"
( cd "$P" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "$local_sha" | sh "$hook" >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok "干净时放行推送" || no "干净时仍被拦下（退出码 $rc）"
# 手工运行（没有 stdin）也要检查，否则行为依赖调用方式
printf 'const y = 1; // [DEBUG-y]\n' > "$P/src/app.js"
wip_commit "$P"
out="$( cd "$P" && sh "$hook" < /dev/null 2>&1 )"
has "推送被拦下" "$out" "手工运行（无 stdin）也会查"
# 钩子被 git 调用时才传 ref：这里确认文件本身可执行（Windows 上 git add 记 100644 会让 clone 后静默跳过）
modes="$( cd "$P" && git ls-files -s .githooks/pre-push | cut -d" " -f1 )"
[ "$modes" = "100755" ] && ok "pre-push 在索引里是可执行文件（100755）" || no "pre-push 在索引里的模式是 $modes，clone 后会被静默跳过"

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
