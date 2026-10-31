#!/usr/bin/env bash
#
# >>> usage
# 闸门检查器 —— 把「能机器判定的闸门」变成可执行检查。
#
#   scripts/check-gates.sh                 检查全仓库：tasks/ 下所有任务 + 全仓库的闸门 B
#   scripts/check-gates.sh --staged        检查索引内容（= 这次提交后的仓库状态；
#                                          任务目录只挑这次改动涉及的，pre-commit 钩子用）
#   scripts/check-gates.sh tasks/2026-08-04-add-login [...]
#
# 覆盖：
#   - 闸门 B：非 .md 文件里没有 [DEBUG- 残留（大小写不敏感；.md 是文档，会引用这个约定）
#   - plan.md：档位与类型已声明、关键字段非空、确认清单全勾、
#              bug 任务的闸门 A 字段、bug-不可复现 必须声明 T3
#   - prd.md：验收标准非空；档位行填了就必须合法（不强制存在）
#   - journal.md：章节齐全（含雾区变化 / 一致性走查）、结束状态合法、验证结果有内容且不写「应该可以」、改动清单已填、
#                 结束状态是 DONE / DONE_WITH_CONCERNS 时「主要提交」必须回填
#   - NN-*.md（切片）：类型与状态取值合法、档位与优先级取值合法、演示与完成标准非空、
#                      文件范围与被谁挡已填、状态 completed 时必须回填主要提交
#   - review.md（裁决单）：任务档位是 T2 / T3 时必须存在（看 plan.md 与切片的声明，
#                          不依赖 plan.md 是否存在）；章节齐全、固定点已填、
#                          逐条处理表非空、「审查者明确未判断的」不许留空
#   - 架构：docs/architecture.md 的模块表 vs 实际模块目录（双向，模块根默认 src）
#          表里全是宽声明（模块根本身或它的祖先）时，全量自查会提示一句：新增子目录不会被检查
#
# 不覆盖（判断性内容，留在 skills/ 里由人确认）：
#   双轴不合并、一次性脚本是否真删干净、命令是否真跑过、
#   **任务是否真的收尾了**（journal.md 在提交之后才写，机器判断不了「这个任务结束了没有」）。
#
# 退出码：0 = 通过，1 = 有违规，2 = 用法错误。
# <<< usage

set -u

violations=0

fail() { printf '  [x] %s\n' "$*"; violations=$((violations + 1)); }

# 提示，不是失败：计入输出，不影响退出码。用于「检查器当前覆盖不到」这类
# 需要人知道、但项目现状本身没错的情况。
note() { printf '  [!] %s\n' "$*"; }

# 用法说明就是文件头那段，用哨兵行圈出来 —— 写死行号会在加注释时漂移。
usage() {
    sed -n '/^# >>> usage$/,/^# <<< usage$/p' "${BASH_SOURCE[0]}" | sed '1d;$d' | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------- markdown 解析

# 去掉 markdown 注释（含跨行）。模板注释里会出现「应该可以」「（从 prd.md 提取）」
# 这类字样，不剥掉的话会误报。
strip_comments() {
    awk '
        { line = $0
          while (1) {
              if (incom) {
                  p = index(line, "-->")
                  if (p == 0) { line = ""; break }
                  line = substr(line, p + 3); incom = 0
              } else {
                  p = index(line, "<!--")
                  if (p == 0) break
                  head = substr(line, 1, p - 1)
                  rest = substr(line, p + 4)
                  q = index(rest, "-->")
                  if (q == 0) { line = head; incom = 1; break }
                  line = head substr(rest, q + 3)
              }
          }
          print line
        }'
}

# 取 `## 标题` 一节的内容（到下一个 ## 标题为止）。$2 是标题的子串。
md_section() {
    awk -v want="$2" '
        /^##[[:space:]]/ { if (insec) exit; if (index($0, want) > 0) { insec = 1; next } }
        insec { print }
    ' "$1"
}

# 取 `- **标签**: 值` 这一行冒号后的内容。$2 是标签子串（避开 en dash 之类的字符）。
# 允许前置缩进——缩进过的字段行不该被判成「未声明」。
# 项目符号接受 `-` 和 `*`，冒号接受半角 `:` 和全角 `：`——**全角必须认**：
# 认不出的话 `sub` 不生效，整行被当成值返回，所有 field_filled 检查会一律判「已填」（fail-open）。
md_field_line() {
    awk -v lbl="$2" '
        /^[[:space:]]*[-*][[:space:]]+\*\*/ && index($0, lbl) > 0 {
            gsub(/：/, ":")                       # 全角冒号先归一化再切
            sub(/^[^:]*:[[:space:]]*/, ""); print; exit
        }
    ' "$1"
}

# 取该字段行及其后续块（到下一个 `- **` 标签或标题为止）。
md_field_block() {
    awk -v lbl="$2" '
        /^[[:space:]]*[-*][[:space:]]+\*\*/ { if (found) exit; if (index($0, lbl) > 0) { found = 1; print; next } }
        /^[[:space:]]*#/ { if (found) exit }
        found { print }
    ' "$1"
}

# 取字段的值：优先第一个反引号里的内容；没写反引号就取冒号后第一个词。
# 不回退的话，`- **档位**: T2`（忘了反引号）会被报成「档位未声明（找不到那一行）」——
# 行明明在，报错文本误导，而且 T2/T3 的任务会因此躲过 review.md 的强制检查。
md_token() {
    local line tok
    line="$(md_field_line "$1" "$2")"
    tok="$(printf '%s' "$line" | sed -n 's/^`\([^`]*\)`.*/\1/p' | head -n 1)"
    if [ -z "$tok" ]; then
        tok="$(printf '%s' "$line" | awk '{print $1}')"
    fi
    printf '%s' "$tok"
}

# 字段是否有实质内容：同行冒号后非空，或后续块里去掉注释/空行/纯符号后还有东西。
# 两种「看着有内容其实没有」的值也算空：
#   - 空反引号：模板里的 `- **X**: \`\``
#   - 只剩模板提示：`- **X**: （一句可演示的话……）`
field_filled() {
    local inline v
    inline="$(md_field_line "$1" "$2")"
    v="$(printf '%s' "$inline" | tr -d '[:space:]`')"
    case "$v" in
        "") : ;;
        '（'*'）') : ;;
        *) return 0 ;;
    esac
    local body
    body="$(md_field_block "$1" "$2" | tail -n +2 \
        | sed 's/<!--.*-->//g' \
        | sed 's/^[[:space:]]*[-*][[:space:]]*//' \
        | tr -d '[:space:]')"
    [ -n "$body" ]
}

# 表格数据行数（跳过表头与分隔行），只算至少一个单元格非空的行。
# $2 = 跳过前几个单元格再判断（默认 0）。步骤表的 `#` 列是自动编号，
# 不跳过的话「模板原封不动」也会被算成有内容。
table_rows() {
    local skip="${2:-0}"
    printf '%s\n' "$1" | grep '^|' | tail -n +3 | awk -F'|' -v skip="$skip" '
        { for (i = 2 + skip; i < NF; i++) { c = $i; gsub(/[[:space:]]/, "", c)
            if (c != "") { n++; break } } }
        END { print n + 0 }'
}

# ---------------------------------------------------------------- 各项检查

# 闸门 B：[DEBUG- 残留。
#   --staged：直接查索引（git grep --cached）。范围 = 这次提交后的仓库，和全量自查对齐；
#             不扫物化出来的临时树——那要先 checkout-index 把整棵树写到磁盘、再全扫一遍，
#             3000 文件 / 20MB 的仓库上 19s vs 0.67s。
#   全量：扫工作区（含未跟踪文件，那才是「全量」的意义）。
# -I 跳过二进制：grep 对二进制只会回一句「Binary file X matches」，没有行号也没有内容，
# 当成「调试标记残留」是误报（图片、fixture、快照都可能恰好含这几个字节）。
# 大小写不敏感：写 [debug-x] 同样是没清干净的调试埋点。
check_gate_b() {
    local staged="$1" root="$2" hits
    if [ "$staged" -eq 1 ]; then
        hits="$(git -C "$root" grep -I -i -n --cached -e '\[DEBUG-' -- \
            ':(exclude)*.md' ':(exclude)*check-gates.sh' \
            ':(exclude)node_modules/*' ':(exclude)*/node_modules/*' 2>/dev/null || true)"
    else
        hits="$(find . -type f \
            ! -path './.git/*' ! -path '*/node_modules/*' \
            ! -name '*.md' ! -name 'check-gates.sh' \
            -exec grep -H -I -i -n '\[DEBUG-' {} + 2>/dev/null | sed 's|^\./||' || true)"
    fi
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" | while IFS= read -r line; do
            printf '  [x] 闸门 B: %s —— 调试标记残留\n' "$line"
        done
        violations=$((violations + $(printf '%s\n' "$hits" | wc -l)))
    fi
}

# review.md（裁决单）：只有 T2 / T3 需要。先剥注释（理由同 check_plan）——
# 模板里那几段说明文字如果被当成内容，一个没填的裁决单会通过。
# 任务档位是否落在 T2/T3：plan.md 与切片里任何一处声明了 T2/T3 就算。
# 不能只看 plan.md——T1 的 plan 可省，而切片文件自己带档位。
task_is_high_tier() {
    local d="$1" f clean t
    for f in "$d/plan.md" "$d"/[0-9][0-9]-*.md; do
        [ -f "$f" ] || continue
        clean="$(mktemp)"
        strip_comments < "$f" > "$clean"
        t="$(md_token "$clean" '档位')"
        rm -f "$clean"
        case "$t" in T2*|T3*) return 0 ;; esac
    done
    return 1
}

# prd.md：Spec 轴的基准。只卡两件机器能判的事——
#   1. 「## 验收标准」非空：AGENTS.md 的 Done Means 和 pre-review 的 Spec 轴都拿它当指涉对象，
#      缺了它 Spec 轴悬空。
#   2. 档位行：填了就必须是 T0–T3。**不要求它必须填**——prd.md 在 Step 3.2 落笔、
#      档位在 3.3 才定，强制存在会在中途提交时误报。这里只抓「模板占位符没删」和写错值。
prd_checks() {
    local f="$1" c="$2" tier acc
    tier="$(md_token "$c" '档位')"
    case "$tier" in
        "") : ;;
        *'T?'*) fail "$f: 档位仍是模板占位符 T?" ;;
        T0*|T1*|T2*|T3*) : ;;
        *) fail "$f: 档位 '$tier' 不是 T0–T3" ;;
    esac

    acc="$(md_section "$c" '验收标准')"
    if [ -z "$acc" ]; then
        fail "$f: 缺「## 验收标准」一节（Spec 轴和 Done Means 都拿它当基准）"
    elif ! printf '%s' "$acc" | grep -qE '^[[:space:]]*([-*][[:space:]]+|[0-9]+\.[[:space:]]+)[^[:space:]]'; then
        fail "$f: 「## 验收标准」里没有条目（项目符号或编号列表都行）"
    fi
}

check_prd() {
    local f="$1" clean
    clean="$(mktemp)"
    strip_comments < "$f" > "$clean"
    prd_checks "$f" "$clean"
    rm -f "$clean"
}

check_review() {
    local d="$1" f="$d/review.md" clean
    if [ ! -f "$f" ]; then
        fail "$d/review.md: 这个任务的档位是 T2/T3，但缺 review.md（这两档的审查必须由独立子 agent 做，见 docs/agents/任务分级.md）"
        return
    fi
    clean="$(mktemp)"
    strip_comments < "$f" > "$clean"
    review_checks "$f" "$clean"
    rm -f "$clean"
}

review_checks() {
    local f="$1" c="$2"

    for sec in '审查范围' '审查者原文' '逐条处理' '审查者明确未判断的' '结论'; do
        if ! grep -q "^## ${sec}" "$c"; then
            fail "$f: 缺「## ${sec}」一节"
        fi
    done

    field_filled "$c" '固定点' || fail "$f: 「固定点」为空"
    if [ "$(table_rows "$(md_section "$c" '逐条处理')" 1)" -eq 0 ]; then
        fail "$f: 「## 逐条处理」表里没有任何条目"
    fi
    if [ -z "$(md_section "$c" '审查者明确未判断的' | tr -d '[:space:]')" ]; then
        fail "$f: 「## 审查者明确未判断的」留空了（一条都没有就写「无」）——把「没判断」显式化，人才能看出盲区在哪"
    fi
}

# plan.md：先剥掉注释再查，否则注释里出现的模板字样与注释掉的 `- [ ]` 会误报。
check_plan() {
    local f="$1" clean
    clean="$(mktemp)"
    strip_comments < "$f" > "$clean"
    plan_checks "$f" "$clean"
    rm -f "$clean"
}

plan_checks() {
    local f="$1" c="$2" tier type

    if ! grep -q '^## 任务概要' "$c"; then
        fail "$f: 缺「## 任务概要」一节"
        return
    fi

    tier="$(md_token "$c" '档位')"
    case "$tier" in
        "") fail "$f: 档位未声明（找不到 \`- **档位**:\` 行）" ;;
        *'T?'*) fail "$f: 档位仍是模板占位符 T?" ;;
        T0*|T1*|T2*|T3*) : ;;
        *) fail "$f: 档位 '$tier' 不是 T0–T3" ;;
    esac

    type="$(md_token "$c" '类型')"
    case "$type" in
        加功能|重构|bug-可复现|bug-不可复现) : ;;
        "") fail "$f: 类型未声明（找不到 \`- **类型**:\` 行）" ;;
        *) fail "$f: 类型 '$type' 不在 {加功能, 重构, bug-可复现, bug-不可复现}" ;;
    esac

    field_filled "$c" '相关文件'   || fail "$f: 「相关文件」为空"
    field_filled "$c" '验证命令'   || fail "$f: 「验证命令」为空"

    if [ "$(table_rows "$(md_section "$c" '步骤')" 1)" -eq 0 ]; then
        fail "$f: 「## 步骤」表里没有任何步骤"
    fi

    # 确认清单：这一节必须存在，且里面不能有未勾的项
    if ! grep -q '^## 确认' "$c"; then
        fail "$f: 缺「## 确认」一节"
    else
        local unchecked
        unchecked="$(md_section "$c" '确认' | grep -cE '^[[:space:]]*[-*+][[:space:]]+\[[[:space:]]?\]' || true)"
        if [ "${unchecked:-0}" -ne 0 ]; then
            fail "$f: 「## 确认」还有 $unchecked 项没勾"
        fi
    fi

    # 模板提示文字残留
    if grep -q '（从 prd.md 提取）' "$c"; then
        fail "$f: 残留模板提示文字「（从 prd.md 提取）」"
    fi

    # 测试 Seam：要么整节不填，要么四行都填
    local seam_filled=0 lbl
    for lbl in '要测的 seam' '公开接口是什么' '错误与边界' '为什么选这个 seam'; do
        field_filled "$c" "$lbl" && seam_filled=$((seam_filled + 1))
    done
    if [ "$seam_filled" -gt 0 ] && [ "$seam_filled" -lt 4 ]; then
        fail "$f: 「## 测试 Seam」只填了 $seam_filled/4 行"
    fi

    # 类型轴 = bug：闸门 A 必填。只卡下界——写超过 5 条假设不是缺陷。
    case "$type" in
        bug-*)
            field_filled "$c" '能变红的命令' || fail "$f: 闸门 A —— 「能变红的命令」为空"
            field_filled "$c" '已实跑的输出' || fail "$f: 闸门 A —— 「已实跑的输出」为空"
            field_filled "$c" '是否已最小化' || fail "$f: 闸门 A —— 「是否已最小化」为空"
            local hy
            hy="$(md_field_block "$c" '排序假设' | grep -cE '^[[:space:]]*[0-9]+\.[[:space:]]*[^[:space:]]' || true)"
            if [ "${hy:-0}" -lt 3 ]; then
                fail "$f: 闸门 A —— 排序假设只有 ${hy:-0} 条（至少要 3 条）"
            fi
            ;;
    esac

    # 任务分级.md：bug 不可复现强制 T3
    if [ "$type" = 'bug-不可复现' ]; then
        case "$tier" in
            T3*) : ;;
            *) fail "$f: 类型 bug-不可复现 必须声明 T3（现在写的是 '$tier'）" ;;
        esac
    fi
}

# journal.md：先剥掉注释再查（理由同 check_plan）
check_journal() {
    local f="$1" clean
    clean="$(mktemp)"
    strip_comments < "$f" > "$clean"
    journal_checks "$f" "$clean"
    rm -f "$clean"
}

journal_checks() {
    local f="$1" c="$2" sec missing=0

    for sec in '目标' '主要提交' '改动文件清单' '验证结果' '遇到的问题' '下次注意什么' '涉及的 ADR' '下一步' '雾区变化' '一致性走查' '结束状态'; do
        if ! grep -q "^## ${sec}" "$c"; then
            fail "$f: 缺「## ${sec}」一节"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -gt 0 ] && return

    # 「结束状态」没填 = 这个任务还没收尾（journal.md 按设计在 Step 3.11 才写，
    # 而 Step 3.9 的 `git add .` 会先把一份空模板扫进提交）。这时不查收尾字段——
    # 和 prd.md 的档位同理：填了才校验，没填不算违规。
    if ! field_filled "$c" '结束状态'; then
        return
    fi

    # 「主要提交」与「结束状态」绑定：BLOCKED / NEEDS_CONTEXT 的任务可能一次提交都没有
    local end_state
    end_state="$(md_token "$c" '结束状态')"
    case "$end_state" in
        DONE|DONE_WITH_CONCERNS)
            field_filled "$c" '主要提交' || fail "$f: 结束状态是 $end_state，但「主要提交」没回填（写工作提交的 SHA，见 tasks/README.md）" ;;
        BLOCKED|NEEDS_CONTEXT)
            : ;;   # 卡住 / 缺信息的任务允许零提交
        *) fail "$f: 「结束状态」是 '$end_state'，不在 {DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT}" ;;
    esac

    local verify
    verify="$(md_section "$c" '验证结果')"
    if [ "$(table_rows "$verify")" -eq 0 ]; then
        fail "$f: 「## 验证结果」表里没有一行结果"
    fi
    if printf '%s' "$verify" | grep -q '应该可以'; then
        fail "$f: 「## 验证结果」里出现「应该可以」——要贴实跑的命令与输出"
    fi

    local changed
    changed="$(md_section "$c" '改动文件清单')"
    if [ "$(table_rows "$changed")" -eq 0 ]; then
        fail "$f: 「## 改动文件清单」表里没有一行"
    fi
    if printf '%s' "$changed" | grep -q 'src/\.\.\.'; then
        fail "$f: 「## 改动文件清单」还留着模板占位符 src/..."
    fi
}

# NN-*.md 切片 / 决策条目。类型决定哪一节必填（同 plan.md 的「修 bug 时必填」）。
check_slice() {
    local f="$1" clean
    clean="$(mktemp)"
    strip_comments < "$f" > "$clean"
    slice_checks "$f" "$clean"
    rm -f "$clean"
}

slice_checks() {
    local f="$1" c="$2" type

    type="$(md_token "$c" '类型')"
    case "$type" in
        切片|决策条目) : ;;
        "") fail "$f: 类型未声明（找不到 \`- **类型**:\` 行，值应为 切片 或 决策条目）"; return ;;
        *) fail "$f: 类型 '$type' 不在 {切片, 决策条目}"; return ;;
    esac

    if [ "$type" = '决策条目' ]; then
        field_filled "$c" '问题'   || fail "$f: 决策条目 —— 「问题」为空"
        field_filled "$c" '结论'   || fail "$f: 决策条目 —— 「结论」为空"
        field_filled "$c" '依据'   || fail "$f: 决策条目 —— 「依据」为空"
        return
    fi

    local tier
    tier="$(md_token "$c" '档位')"
    case "$tier" in
        "") fail "$f: 档位未声明（找不到 \`- **档位**:\` 行）" ;;
        *'T?'*) fail "$f: 档位仍是模板占位符 T?" ;;
        T0*|T1*|T2*|T3*) : ;;
        *) fail "$f: 档位 '$tier' 不是 T0–T3" ;;
    esac

    local prio
    prio="$(md_token "$c" '优先级')"
    case "$prio" in
        P0|P1|P2) : ;;
        "") fail "$f: 优先级未声明（找不到 \`- **优先级**:\` 行）" ;;
        *) fail "$f: 优先级 '$prio' 不在 {P0, P1, P2}" ;;
    esac

    field_filled "$c" '完成后可以看到什么' || fail "$f: 「完成后可以看到什么」为空"
    field_filled "$c" '完成标准'           || fail "$f: 「完成标准」为空"
    field_filled "$c" '文件范围'           || fail "$f: 「文件范围」为空"
    field_filled "$c" '被谁挡'             || fail "$f: 「被谁挡」为空（没有前置就写「无」）"

    local st
    st="$(md_token "$c" '状态')"
    case "$st" in
        pending|in_progress|completed) : ;;
        "") fail "$f: 状态未声明（找不到 \`- **状态**:\` 行）" ;;
        *) fail "$f: 状态 '$st' 不在 {pending, in_progress, completed}" ;;
    esac

    # 标记完成却回填不了提交，说明这个切片的状态是假的
    if [ "$st" = 'completed' ] && ! field_filled "$c" '主要提交'; then
        fail "$f: 状态是 completed，但「主要提交」没回填"
    fi

    if ! grep -q '^## 确认' "$c"; then
        fail "$f: 缺「## 确认」一节"
    else
        local unchecked
        unchecked="$(md_section "$c" '确认' | grep -cE '^[[:space:]]*[-*+][[:space:]]+\[[[:space:]]?\]' || true)"
        if [ "${unchecked:-0}" -ne 0 ]; then
            fail "$f: 「## 确认」还有 $unchecked 项没勾"
        fi
    fi
}

# ---------------------------------------------------------------- 架构

# 模块根：这个目录的直接子目录就是模块。项目布局不同时改这里，
# 或用环境变量覆盖：MODULE_ROOT=app bash scripts/check-gates.sh
MODULE_ROOT="${MODULE_ROOT:-src}"

# `## 模块划分` 表第 2 列声明的路径，去掉反引号与尾斜杠。
declared_module_paths() {
    md_section "$1" '模块划分' | awk -F'|' '
        /^[[:space:]]*\|/ {
            p = $3
            gsub(/`/, "", p)
            sub(/^[[:space:]]+/, "", p); sub(/[[:space:]]+$/, "", p)
            sub(/\/+$/, "", p)
            if (p == "" || p == "路径" || p ~ /^-+$/) next
            print p
        }' | sort -u
}

# 目录与路径一律以**工作区**为准，不取索引：索引里没有「空目录」这个概念，
# 而 src/ 恰恰是空的 —— 只看索引会在首次提交时误报「src 不存在」。
# 表的内容则取索引版本（见 check_architecture）。
arch_module_dirs() {
    ( cd "$1" 2>/dev/null || exit 0
      [ -d "$MODULE_ROOT" ] || exit 0
      find "$MODULE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -u )
}

arch_path_exists() { [ -e "$1/$2" ]; }

# 模块表 vs 实际目录，双向比对。防两件事：模块被改名 / 移动 / 删除而表没跟着改，
# 以及新加了模块目录却没进表。
#
# 覆盖语义：声明的路径覆盖它自己、它的祖先和它的后代。所以表里写 `src` 等于
# 「整个 src 当一个模块」，子目录不再逐个要求；写具体子目录，则新加的子目录必须进表。
check_architecture() {
    local staged="$1" root="$2"
    local doc="docs/architecture.md"

    if [ "$staged" -eq 1 ]; then
        # 暂存模式下 cwd 是索引物化出的整棵树，表进了索引就是索引版本
        # （所以「暂存了坏表」会被拦住）。没进索引（还没 commit 过、又没 add 过它）
        # 才退回工作区版本——否则会把「文件明明在仓库里」报成不存在。
        doc="$check_tree_tmp/docs/architecture.md"
        if [ ! -f "$doc" ]; then
            mkdir -p "$check_tree_tmp/docs"
            cp "$root/docs/architecture.md" "$doc" 2>/dev/null || rm -f "$doc"
        fi
    fi

    if [ ! -f "$doc" ]; then
        fail "docs/architecture.md 不存在"
        return
    fi

    local declared
    declared="$(declared_module_paths "$doc")"
    if [ -z "$declared" ]; then
        fail "docs/architecture.md 的「## 模块划分」表里没有声明任何模块"
        return
    fi

    # 规则 1：声明的路径必须真实存在
    local p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        arch_path_exists "$root" "$p" \
            || fail "docs/architecture.md 声明了模块「$p」，但它不存在"
    done <<< "$declared"

    # 规则 2：$MODULE_ROOT 下的直接子目录必须被某个声明覆盖
    local d covered q
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        covered=0
        while IFS= read -r q; do
            [ -n "$q" ] || continue
            case "$q/" in "$d/"*) covered=1; break ;; esac
            case "$d/" in "$q/"*) covered=1; break ;; esac
        done <<< "$declared"
        [ "$covered" -eq 1 ] \
            || fail "「$d」是 $MODULE_ROOT 下的模块目录，但 docs/architecture.md 的模块表里没有它"
    done < <(arch_module_dirs "$root")

    # 提示（不是失败）：表里全是宽声明时，规则 2 永远不触发——新增模块目录不会被检查。
    # 只在全量自查时报；--staged 每次提交都跑，不适合反复提示。
    if [ "$staged" -eq 0 ]; then
        local specific=0
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            p="${p%/}"          # `src/` 与 `src` 是同一种声明，先去掉尾斜杠
            case "$p" in
                "$MODULE_ROOT"/*) specific=1; break ;;
            esac
        done <<< "$declared"
        if [ "$specific" -eq 0 ]; then
            note "模块表只声明了宽路径（$MODULE_ROOT 本身或它的祖先），所以「$MODULE_ROOT 下新增子目录」这条检查当前不会触发。"
            note "项目长大之后，把表拆成具体子模块（如 $MODULE_ROOT/auth、$MODULE_ROOT/billing），让这条检查生效。"
        fi
    fi
}

# ---------------------------------------------------------------- 主流程

main() {
    local staged=0
    local task_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --staged) staged=1 ;;
            -h|--help) usage; exit 0 ;;
            --) shift; break ;;
            -*) printf '未知选项: %s\n' "$1" >&2; exit 2 ;;
            *) task_args+=("$1") ;;
        esac
        shift
    done
    while [ "$#" -gt 0 ]; do task_args+=("$1"); shift; done

    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$root" ] || root="$(cd "$(dirname "$0")/.." && pwd)"

    if [ "$staged" -eq 1 ]; then
        # 内容必须取自索引。只拿 git diff --cached 的文件名、却读工作区，会在
        # 「已暂存的是坏内容、工作区已修好」时放行，反方向则误拦一次合法提交。
        #
        # 物化的是**整个索引**，不是这次改动的那几个文件：检查会问「某个这次没动的
        # 文件在不在」（T2/T3 的 review.md、plan.md 里的档位都是这种），只物化 diff
        # 会让这类问题一律得到「文件不存在」——该拦的漏掉，不该拦的拦住。
        #
        # 凡是**列文件名**的 git 调用都带 -c core.quotepath=false：这个设置存在
        # .git/config 里，不随 clone 走。少了它，clone 回来的仓库里中文名路径会被
        # 引号+八进制转义，case 匹配失配 —— 那些文件会静默逃过全部检查。
        #
        # 临时目录用全局变量：EXIT trap 在 main 返回之后才执行，那时 local 已经出作用域，
        # set -u 会把 "$check_tree_tmp" 当成未绑定变量，trap 失败 → 脚本整体非 0。
        check_tree_tmp="$(mktemp -d)"
        trap 'rm -rf "$check_tree_tmp"' EXIT
        git -C "$root" checkout-index -a --prefix="$check_tree_tmp/" 2>/dev/null || true
        cd "$check_tree_tmp" || exit 2
    else
        cd "$root" || exit 2
    fi

    # 闸门 B：残留扫描。--staged 查索引，全量查工作区
    check_gate_b "$staged" "$root"

    # 架构：模块表 vs 实际目录。仓库状态不变量，两种模式都跑
    check_architecture "$staged" "$root"

    # 要检查哪些任务目录
    local dirs=()
    local d p rest
    if [ "${#task_args[@]}" -gt 0 ]; then
        for d in "${task_args[@]}"; do
            case "$d" in
                tasks/_template|tasks/_template/)
                    printf '%s\n' "跳过 $d（模板，不是任务）"
                    continue ;;
            esac
            if [ -d "$d" ]; then dirs+=("$d"); else fail "找不到任务目录: $d"; fi
        done
    elif [ "$staged" -eq 1 ]; then
        while IFS= read -r p; do
            case "$p" in
                tasks/*/*)
                    rest="${p#tasks/}"
                    d="tasks/${rest%%/*}"
                    case "$d" in tasks/_template) continue ;; esac
                    dirs+=("$d") ;;
            esac
        done < <(git -c core.quotepath=false -C "$root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
    else
        for d in tasks/*/; do
            [ -d "$d" ] || continue
            case "$d" in tasks/_template/) continue ;; esac
            dirs+=("${d%/}")
        done
    fi

    # 去重后逐个检查
    local seen="|"
    for d in ${dirs[@]+"${dirs[@]}"}; do
        case "$seen" in *"|$d|"*) continue ;; esac
        seen="$seen$d|"
        local any=0
        if [ -f "$d/plan.md" ]; then
            printf '%s\n' "检查 $d/plan.md"
            check_plan "$d/plan.md"
            any=1
        fi
        if [ -f "$d/prd.md" ]; then
            printf '%s\n' "检查 $d/prd.md"
            check_prd "$d/prd.md"
            any=1
        fi
        # T2 / T3 的审查必须换人做，产出裁决单（见 docs/agents/任务分级.md）。
        # 独立于 plan.md 是否存在——档位也可能只写在切片里。
        if task_is_high_tier "$d"; then
            check_review "$d"
            any=1
        fi
        if [ -f "$d/journal.md" ]; then
            printf '%s\n' "检查 $d/journal.md"
            check_journal "$d/journal.md"
            any=1
        fi
        # 切片 / 决策条目：NN-*.md（见 tasks/README.md）
        local s
        for s in "$d"/[0-9][0-9]-*.md; do
            [ -f "$s" ] || continue
            printf '%s\n' "检查 $s"
            check_slice "$s"
            any=1
        done
        [ "$any" -eq 1 ] || printf '%s\n' "跳过 $d（还没有 plan.md / journal.md / NN-*.md）"
    done

    if [ "$violations" -eq 0 ]; then
        printf '闸门检查通过。\n'
        return 0
    fi
    printf '闸门检查失败：%d 项。\n' "$violations"
    return 1
}

main "$@"
