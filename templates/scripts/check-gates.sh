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
#   - journal.md：章节齐全、验证结果有内容且不写「应该可以」、改动清单已填
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
field_filled() {
    local inline
    inline="$(md_field_line "$1" "$2")"
    if [ -n "$(printf '%s' "$inline" | tr -d '[:space:]')" ]; then return 0; fi
    local body
    body="$(md_field_block "$1" "$2" | tail -n +2 \
        | sed 's/<!--.*-->//g' \
        | sed 's/^[[:space:]]*[-*][[:space:]]*//' \
        | tr -d '[:space:]')"
    [ -n "$body" ]
}

# 表格数据行数（跳过表头与分隔行），只算至少一个单元格非空的行。
table_rows() {
    printf '%s\n' "$1" | grep '^|' | tail -n +3 | awk -F'|' '
        { for (i = 2; i < NF; i++) { c = $i; gsub(/[[:space:]]/, "", c)
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

    if [ "$(table_rows "$(md_section "$c" '步骤')")" -eq 0 ]; then
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

    for sec in '目标' '改动文件清单' '验证结果' '遇到的问题' '下次注意什么' '涉及的 ADR' '下一步'; do
        if ! grep -q "^## ${sec}" "$c"; then
            fail "$f: 缺「## ${sec}」一节"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -gt 0 ] && return

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
        [ "$any" -eq 1 ] || printf '%s\n' "跳过 $d（还没有 plan.md / journal.md）"
    done

    if [ "$violations" -eq 0 ]; then
        printf '闸门检查通过。\n'
        return 0
    fi
    printf '闸门检查失败：%d 项。\n' "$violations"
    return 1
}

main "$@"
