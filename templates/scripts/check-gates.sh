#!/usr/bin/env bash
#
# >>> usage
# 闸门检查器 —— 把「能机器判定的闸门」变成可执行检查。
#
#   scripts/check-gates.sh                 检查全仓库：tasks/ 下所有任务 + 全仓库的闸门 B
#   scripts/check-gates.sh --staged        只检查已暂存的内容（pre-commit 钩子用）
#   scripts/check-gates.sh tasks/2026-08-04-add-login [...]
#
# 覆盖：
#   - 闸门 B：非 .md 文件里没有 [DEBUG- 残留（大小写不敏感；.md 是文档，会引用这个约定）
#   - plan.md：档位与类型已声明、关键字段非空、确认清单全勾、
#              bug 任务的闸门 A 字段、bug-不可复现 必须声明 T3
#   - journal.md：章节齐全、主要提交已回填、验证结果有内容且不写「应该可以」、改动清单已填
#   - NN-*.md（切片）：类型与状态取值合法、演示与完成标准非空、被谁挡已填、
#                      状态 completed 时必须回填主要提交
#   - 架构：docs/architecture.md 的模块表 vs 实际模块目录（双向，模块根默认 src）
#
# 不覆盖（判断性内容，留在 skills/ 里由人确认）：
#   双轴不合并、一次性脚本是否真删干净、命令是否真跑过。
#
# 退出码：0 = 通过，1 = 有违规，2 = 用法错误。
# <<< usage

set -u

violations=0

fail() { printf '  [x] %s\n' "$*"; violations=$((violations + 1)); }

# 用法说明就是文件头那段，用哨兵行圈出来 —— 写死行号会在加注释时漂移。
usage() {
    sed -n '/^# >>> usage$/,/^# <<< usage$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//'
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
md_field_line() {
    awk -v lbl="$2" '
        /^[[:space:]]*- \*\*/ && index($0, lbl) > 0 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
    ' "$1"
}

# 取该字段行及其后续块（到下一个 `- **` 标签或标题为止）。
md_field_block() {
    awk -v lbl="$2" '
        /^[[:space:]]*- \*\*/ { if (found) exit; if (index($0, lbl) > 0) { found = 1; print; next } }
        /^[[:space:]]*#/ { if (found) exit }
        found { print }
    ' "$1"
}

# 取字段行里第一个反引号内的内容。
md_token() {
    md_field_line "$1" "$2" | sed -n 's/^`\([^`]*\)`.*/\1/p' | head -n 1
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

# 闸门 B：[DEBUG- 残留。cwd 就是检查范围（暂存模式下是索引物化出来的临时树）。
# 大小写不敏感：写 [debug-x] 同样是没清干净的调试埋点。
check_gate_b() {
    local hits
    hits="$(find . -type f \
        ! -path './.git/*' ! -path '*/node_modules/*' \
        ! -name '*.md' ! -name 'check-gates.sh' \
        -exec grep -Hin '\[DEBUG-' {} + 2>/dev/null | sed 's|^\./||' || true)"
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" | while IFS= read -r line; do
            printf '  [x] 闸门 B: %s —— 调试标记残留\n' "$line"
        done
        violations=$((violations + $(printf '%s\n' "$hits" | wc -l)))
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
        unchecked="$(md_section "$c" '确认' | grep -cE '^[[:space:]]*[-*+] \[ \]' || true)"
        if [ "${unchecked:-0}" -ne 0 ]; then
            fail "$f: 「## 确认」还有 $unchecked 项没勾"
        fi
    fi

    # 模板提示文字残留
    if grep -q '（从 prd.md 提取）' "$c"; then
        fail "$f: 残留模板提示文字「（从 prd.md 提取）」"
    fi

    # 测试 Seam：要么整节不填，要么三行都填
    local seam_filled=0 lbl
    for lbl in '要测的 seam' '公开接口是什么' '为什么选这个 seam'; do
        field_filled "$c" "$lbl" && seam_filled=$((seam_filled + 1))
    done
    if [ "$seam_filled" -gt 0 ] && [ "$seam_filled" -lt 3 ]; then
        fail "$f: 「## 测试 Seam」只填了 $seam_filled/3 行"
    fi

    # 类型轴 = bug：闸门 A 必填。只卡下界——写超过 5 条假设不是缺陷。
    case "$type" in
        bug-*)
            field_filled "$c" '能变红的命令' || fail "$f: 闸门 A —— 「能变红的命令」为空"
            field_filled "$c" '已实跑的输出' || fail "$f: 闸门 A —— 「已实跑的输出」为空"
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

    for sec in '目标' '主要提交' '改动文件清单' '验证结果' '遇到的问题' '下次注意什么' '涉及的 ADR' '下一步' '结束状态'; do
        if ! grep -q "^## ${sec}" "$c"; then
            fail "$f: 缺「## ${sec}」一节"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -gt 0 ] && return

    if ! field_filled "$c" '主要提交'; then
        fail "$f: 「主要提交」没回填（写工作提交的 SHA，见 tasks/README.md）"
    fi

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

    # 结束状态必须四选一（跨会话接手时靠它决定继续做还是先解决问题）
    if ! md_section "$c" '结束状态' | grep -qE '\b(DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT)\b'; then
        fail "$f: 「## 结束状态」必须是 DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT 之一"
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
        unchecked="$(md_section "$c" '确认' | grep -cE '^[[:space:]]*[-*+] \[ \]' || true)"
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
        # 暂存模式下 cwd 是索引物化出的临时树，只含这次改动的文件；
        # 表不在这次改动里时，单独从索引取出来。
        doc="$check_tree_tmp/docs/architecture.md"
        if [ ! -f "$doc" ]; then
            mkdir -p "$check_tree_tmp/docs"
            # 索引里有就用索引版本（这样「暂存了坏表」会被拦住）；
            # 索引里没有（例如还没 commit 过、又没 add 这个文件）就退回工作区版本。
            git -C "$root" show ':docs/architecture.md' > "$doc" 2>/dev/null \
                || cp "$root/docs/architecture.md" "$doc" 2>/dev/null \
                || rm -f "$doc"
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
        # 临时目录用全局变量：EXIT trap 在 main 返回之后才执行，那时 local 已经出作用域，
        # set -u 会把 "$check_tree_tmp" 当成未绑定变量，trap 失败 → 脚本整体非 0。
        check_tree_tmp="$(mktemp -d)"
        trap 'rm -rf "$check_tree_tmp"' EXIT
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            mkdir -p "$check_tree_tmp/$(dirname "$p")"
            git -C "$root" show ":$p" > "$check_tree_tmp/$p" 2>/dev/null || true
        done < <(git -C "$root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
        cd "$check_tree_tmp" || exit 2
    else
        cd "$root" || exit 2
    fi

    # 闸门 B：cwd 就是检查范围
    check_gate_b

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
        done < <(git -C "$root" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
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
