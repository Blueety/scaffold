# 闸门检查的判定逻辑。规则与消息的说明见 check-gates.sh 里的 check_*。
#
# 为什么判定在 awk 里而不是 bash：本机起一个外部进程约 27ms，而判定本身要做的
# 字符串扫描（一个任务目录 40 来次、每次上百行）在 bash 里约 13.7ms/120 行。
# 两者叠加让全量自查变成分钟级。搬进 awk 之后每个文件一次进程，循环在 C 里跑。
#
# 用法：
#   awk -v kind=plan|prd|journal|slice|review -v fpath=<路径> -f check-gates.awk <文件>
#       输出 `  [x] <路径>: <消息>` 行（没有违规就什么都不输出）
#   awk -v kind=tier -f check-gates.awk <plan.md> <切片...>
#       输出 yes / no —— 任务档位是否落在 T2/T3
#
# 注意：所有函数的局部变量都必须写在参数表里（awk 没有别的局部变量语法），
# 漏写会变成全局变量，在多次调用之间串味。

BEGIN {
    FS = "\n"

    JOURNAL_SECS[1]  = "目标"
    JOURNAL_SECS[2]  = "主要提交"
    JOURNAL_SECS[3]  = "改动文件清单"
    JOURNAL_SECS[4]  = "验证结果"
    JOURNAL_SECS[5]  = "遇到的问题"
    JOURNAL_SECS[6]  = "下次注意什么"
    JOURNAL_SECS[7]  = "涉及的 ADR"
    JOURNAL_SECS[8]  = "下一步"
    JOURNAL_SECS[9]  = "雾区变化"
    JOURNAL_SECS[10] = "一致性走查"
    JOURNAL_SECS[11] = "结束状态"

    REVIEW_SECS[1] = "审查范围"
    REVIEW_SECS[2] = "审查者原文"
    REVIEW_SECS[3] = "逐条处理"
    REVIEW_SECS[4] = "审查者明确未判断的"
    REVIEW_SECS[5] = "结论"
}

# ---------------------------------------------------------------- 读入

{
    line = $0

    # 剥掉 markdown 注释（含跨行）。模板注释里会出现「应该可以」
    # 「（从 prd.md 提取）」这类字样，不剥掉的话会误报。
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
    gsub(/\t/, " ", line)

    # 档位：plan.md 与切片里任何一处声明了 T2/T3 就算。
    # 不能只看 plan.md —— T1 的 plan 可省，而切片文件自己带档位。
    if (kind == "tier") {
        if (!tier_found && line ~ /^[[:space:]]*[-*][[:space:]]+\*\*/ && index(line, "档位") > 0) {
            tier_found = 1
            if (token_of(field_value_of(line)) ~ /^T[23]/) high = 1
        }
        next
    }

    L[++NL] = line
}

END {
    if (kind == "tier")    { print (high ? "yes" : "no"); exit }
    if (kind == "modules") { modules_dump(); exit }
    if      (kind == "plan")    plan_check()
    else if (kind == "prd")     prd_check()
    else if (kind == "journal") journal_check()
    else if (kind == "slice")   slice_check()
    else if (kind == "review")  review_check()
}

# ---------------------------------------------------------------- 输出

function V(msg) { print "  [x] " fpath ": " msg }

# ---------------------------------------------------------------- 查询

# `## <标题>` 开一节，到下一个 `## ` 标题为止。取第一个标题里含 want 的。
# 返回正文行数，正文存进 S[]。
function md_section(want,   i, insec, n) {
    n = 0; insec = 0
    for (i = 1; i <= NL; i++) {
        if (L[i] ~ /^##[[:space:]]/) {
            if (insec) break
            if (index(L[i], want) > 0) insec = 1
            continue
        }
        if (insec) S[++n] = L[i]
    }
    return n
}

# 小节正文拼成一个字符串，尾部换行去掉（等价于 shell 里 `$( )` 的剥尾换行）。
function section_text(want,   n, i, out) {
    n = md_section(want)
    out = ""
    for (i = 1; i <= n; i++) out = out (i > 1 ? "\n" : "") S[i]
    sub(/\n+$/, "", out)
    return out
}

# 是否存在以 `## <标题>` 开头的行（等价于原来的 grep -q "^## <标题>"）。
# 注意与 md_section 的区别：这里要求标题**以 want 开头**，那里只要求**含 want**。
function has_section(want,   i) {
    for (i = 1; i <= NL; i++)
        if (substr(L[i], 1, 3 + length(want)) == "## " want) return 1
    return 0
}

# 整份文件（剥掉注释后）里是否出现过这段字面文本。
function has_text(want,   i) {
    for (i = 1; i <= NL; i++) if (index(L[i], want) > 0) return 1
    return 0
}

# `- **标签**: 值` 行的原文（第一次出现）。没找到返回空串。
function field_raw(lbl,   i) {
    for (i = 1; i <= NL; i++)
        if (L[i] ~ /^[[:space:]]*[-*][[:space:]]+\*\*/ && index(L[i], lbl) > 0) return L[i]
    return ""
}

# 字段行冒号后的值。全角冒号先归一化——**必须认**：认不出的话 `sub` 不生效，
# 整行被当成值返回，所有 field_filled 检查会一律判「已填」（fail-open）。
function field_value_of(r,   v) {
    v = r
    gsub(/：/, ":", v)
    sub(/^[^:]*:[[:space:]]*/, "", v)
    return v
}
function field_value(lbl) { return field_value_of(field_raw(lbl)) }

# 取值的 token：优先第一个反引号里的内容；没写反引号就取第一个词。
# 不回退的话 `- **档位**: T2`（忘了反引号）会被报成「档位未声明」，
# 而且 T2/T3 的任务会因此躲过 review.md 的强制检查。
# 第一个词用 [ \t] 而不是 [[:space:]]：本机 locale 下 0xA0 也算空白，
# 而中文（UTF-8 里含 0xA0 字节的字）会被从中间切坏。
function token_of(v,   s, p) {
    if (substr(v, 1, 1) == "`" && index(substr(v, 2), "`") > 0) {
        s = substr(v, 2)
        return substr(s, 1, index(s, "`") - 1)
    }
    s = v
    sub(/^[ \t]+/, "", s)
    p = match(s, /[ \t]/)
    return p ? substr(s, 1, p - 1) : s
}
function md_token(lbl) { return token_of(field_value(lbl)) }

# 字段行及其后续块（到下一个 `- **` 标签行或标题行为止）。返回行数，存进 B[]。
function field_block(lbl,   i, n, found) {
    n = 0; found = 0
    for (i = 1; i <= NL; i++) {
        if (L[i] ~ /^[[:space:]]*[-*][[:space:]]+\*\*/) {
            if (found) break
            if (index(L[i], lbl) > 0) { found = 1; B[++n] = L[i]; continue }
        } else if (L[i] ~ /^[[:space:]]*#/) {
            if (found) break
        }
        if (found) B[++n] = L[i]
    }
    return n
}
function field_block_text(lbl,   n, i, out) {
    n = field_block(lbl)
    out = ""
    for (i = 1; i <= n; i++) out = out (i > 1 ? "\n" : "") B[i]
    sub(/\n+$/, "", out)
    return out
}

# 字段是否有实质内容：同行冒号后非空，或后续块里去掉注释/空行/纯符号后还有东西。
# 两种「看着有内容其实没有」的值也算空：
#   - 空反引号：模板里的 `- **X**: \`\``
#   - 只剩模板提示：`- **X**: （一句可演示的话……）`
function field_filled(lbl,   s, n, j, l, body) {
    s = field_value(lbl)
    gsub(/[[:space:]]/, "", s)
    gsub(/`/, "", s)
    if (s == "") { }
    else if (s ~ /^（.*）$/) { }
    else return 1

    n = field_block(lbl)
    body = ""
    for (j = 2; j <= n; j++) {          # 跳过字段行本身（同 tail -n +2）
        l = B[j]
        gsub(/<!--.*-->/, "", l)
        sub(/^[[:space:]]*[-*][[:space:]]*/, "", l)
        gsub(/[[:space:]]/, "", l)
        body = body l
    }
    return (body != "")
}

# 表格数据行数（跳过表头与分隔行）。skip = 跳过前几个单元格再判断：
# 步骤表的 `#` 列是自动编号，不跳过的话「模板原封不动」也会被算成有内容。
function table_rows(text, skip,   n, i, seen, cells, nf, j, c, cnt) {
    n = split(text, ROWS, "\n")
    cnt = 0; seen = 0
    for (i = 1; i <= n; i++) {
        if (substr(ROWS[i], 1, 1) != "|") continue
        seen++
        if (seen <= 2) continue
        nf = split(ROWS[i], cells, "|")
        for (j = 2 + skip; j < nf; j++) {
            c = cells[j]; gsub(/[[:space:]]/, "", c)
            if (c != "") { cnt++; break }
        }
    }
    return cnt
}

# 未勾选的 `- [ ]`
function count_checkboxes(text,   n, i, c) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++) if (ROWS[i] ~ /^[[:space:]]*[-*+][[:space:]]+\[[[:space:]]?\]/) c++
    return c
}

# 项目符号或编号列表项
function count_listitems(text,   n, i, c) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++)
        if (ROWS[i] ~ /^[[:space:]]*([-*][[:space:]]+|[0-9]+\.[[:space:]]+)[^[:space:]]/) c++
    return c
}

# `1. xxx`（排序假设用）
function count_numbered(text,   n, i, c) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++)
        if (ROWS[i] ~ /^[[:space:]]*[0-9]+\.[[:space:]]*[^[:space:]]/) c++
    return c
}

# ---------------------------------------------------------------- 模块表

# `## 模块划分` 表第 2 列声明的路径，去掉反引号与尾斜杠。
function modules_dump(   n, i, cells, nf, p) {
    n = md_section("模块划分")
    for (i = 1; i <= n; i++) {
        if (S[i] !~ /^[[:space:]]*\|/) continue
        nf = split(S[i], cells, "|")
        if (nf < 3) continue
        p = cells[3]
        gsub(/`/, "", p)
        sub(/^[[:space:]]+/, "", p); sub(/[[:space:]]+$/, "", p)
        sub(/\/+$/, "", p)
        if (p == "" || p == "路径" || p ~ /^-+$/) continue
        print p
    }
}

# ---------------------------------------------------------------- plan.md

function plan_check(   tier, type, n, filled, hy) {
    if (!has_section("任务概要")) { V("缺「## 任务概要」一节"); return }

    tier = md_token("档位")
    if (tier == "")                    V("档位未声明（找不到 `- **档位**:` 行）")
    else if (index(tier, "T?") > 0)    V("档位仍是模板占位符 T?")
    else if (tier !~ /^T[0-3]/)        V("档位 '" tier "' 不是 T0–T3")

    type = md_token("类型")
    if (type == "") V("类型未声明（找不到 `- **类型**:` 行）")
    else if (type != "加功能" && type != "重构" && type != "bug-可复现" && type != "bug-不可复现")
        V("类型 '" type "' 不在 {加功能, 重构, bug-可复现, bug-不可复现}")

    if (!field_filled("相关文件")) V("「相关文件」为空")
    if (!field_filled("验证命令")) V("「验证命令」为空")

    if (table_rows(section_text("步骤"), 1) == 0) V("「## 步骤」表里没有任何步骤")

    # 确认清单：这一节必须存在，且里面不能有未勾的项
    if (!has_section("确认")) V("缺「## 确认」一节")
    else {
        n = count_checkboxes(section_text("确认"))
        if (n != 0) V("「## 确认」还有 " n " 项没勾")
    }

    if (has_text("（从 prd.md 提取）")) V("残留模板提示文字「（从 prd.md 提取）」")

    # 测试 Seam：要么整节不填，要么四行都填
    filled = 0
    if (field_filled("要测的 seam"))        filled++
    if (field_filled("公开接口是什么"))      filled++
    if (field_filled("错误与边界"))          filled++
    if (field_filled("为什么选这个 seam"))   filled++
    if (filled > 0 && filled < 4) V("「## 测试 Seam」只填了 " filled "/4 行")

    # 类型轴 = bug：闸门 A 必填。只卡下界——写超过 5 条假设不是缺陷。
    if (type ~ /^bug-/) {
        if (!field_filled("能变红的命令")) V("闸门 A —— 「能变红的命令」为空")
        if (!field_filled("已实跑的输出")) V("闸门 A —— 「已实跑的输出」为空")
        if (!field_filled("是否已最小化")) V("闸门 A —— 「是否已最小化」为空")
        hy = count_numbered(field_block_text("排序假设"))
        if (hy < 3) V("闸门 A —— 排序假设只有 " hy " 条（至少要 3 条）")
    }

    # 任务分级.md：bug 不可复现强制 T3
    if (type == "bug-不可复现" && tier !~ /^T3/)
        V("类型 bug-不可复现 必须声明 T3（现在写的是 '" tier "')")
}

# ---------------------------------------------------------------- prd.md

# Spec 轴的基准。只卡两件机器能判的事：
#   1. 「## 验收标准」非空——AGENTS.md 的 Done Means 和 pre-review 的 Spec 轴
#      都拿它当指涉对象，缺了它 Spec 轴悬空。
#   2. 档位行填了就必须是 T0–T3。**不要求它必须填**——prd.md 在 Step 3.2 落笔、
#      档位在 3.3 才定，强制存在会在中途提交时误报。这里只抓「模板占位符没删」和写错值。
function prd_check(   tier, acc) {
    tier = md_token("档位")
    if (tier == "")                 { }
    else if (index(tier, "T?") > 0) V("档位仍是模板占位符 T?")
    else if (tier !~ /^T[0-3]/)     V("档位 '" tier "' 不是 T0–T3")

    acc = section_text("验收标准")
    if (acc == "") V("缺「## 验收标准」一节（Spec 轴和 Done Means 都拿它当基准）")
    else if (count_listitems(acc) == 0) V("「## 验收标准」里没有条目（项目符号或编号列表都行）")
}

# ---------------------------------------------------------------- journal.md

function journal_check(   i, missing, end_state, verify, changed) {
    missing = 0
    for (i = 1; i <= 11; i++) {
        if (!has_section(JOURNAL_SECS[i])) {
            V("缺「## " JOURNAL_SECS[i] "」一节")
            missing++
        }
    }
    if (missing > 0) return

    # 「结束状态」没填 = 这个任务还没收尾（journal.md 按设计在 Step 3.11 才写，
    # 而 Step 3.9 的 `git add .` 会先把一份空模板扫进提交）。这时不查收尾字段——
    # 和 prd.md 的档位同理：填了才校验，没填不算违规。
    if (!field_filled("结束状态")) return

    # 「主要提交」与「结束状态」绑定：BLOCKED / NEEDS_CONTEXT 的任务可能一次提交都没有
    end_state = md_token("结束状态")
    if (end_state == "DONE" || end_state == "DONE_WITH_CONCERNS") {
        if (!field_filled("主要提交"))
            V("结束状态是 " end_state "，但「主要提交」没回填（写工作提交的 SHA，见 tasks/README.md）")
    } else if (end_state == "BLOCKED" || end_state == "NEEDS_CONTEXT") {
        # 卡住 / 缺信息的任务允许零提交
    } else {
        V("「结束状态」是 '" end_state "'，不在 {DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT}")
    }

    verify = section_text("验证结果")
    if (table_rows(verify, 0) == 0) V("「## 验证结果」表里没有一行结果")
    if (index(verify, "应该可以") > 0) V("「## 验证结果」里出现「应该可以」——要贴实跑的命令与输出")

    changed = section_text("改动文件清单")
    if (table_rows(changed, 0) == 0) V("「## 改动文件清单」表里没有一行")
    if (index(changed, "src/...") > 0) V("「## 改动文件清单」还留着模板占位符 src/...")
}

# ---------------------------------------------------------------- NN-*.md 切片 / 决策条目

# 类型决定哪一节必填（同 plan.md 的「修 bug 时必填」）。
function slice_check(   type, tier, prio, st, n) {
    type = md_token("类型")
    if (type == "") { V("类型未声明（找不到 `- **类型**:` 行，值应为 切片 或 决策条目）"); return }
    if (type != "切片" && type != "决策条目") { V("类型 '" type "' 不在 {切片, 决策条目}"); return }

    if (type == "决策条目") {
        if (!field_filled("问题")) V("决策条目 —— 「问题」为空")
        if (!field_filled("结论")) V("决策条目 —— 「结论」为空")
        if (!field_filled("依据")) V("决策条目 —— 「依据」为空")
        return
    }

    tier = md_token("档位")
    if (tier == "")                 V("档位未声明（找不到 `- **档位**:` 行）")
    else if (index(tier, "T?") > 0) V("档位仍是模板占位符 T?")
    else if (tier !~ /^T[0-3]/)     V("档位 '" tier "' 不是 T0–T3")

    prio = md_token("优先级")
    if (prio == "") V("优先级未声明（找不到 `- **优先级**:` 行）")
    else if (prio != "P0" && prio != "P1" && prio != "P2")
        V("优先级 '" prio "' 不在 {P0, P1, P2}")

    if (!field_filled("完成后可以看到什么")) V("「完成后可以看到什么」为空")
    if (!field_filled("完成标准"))           V("「完成标准」为空")
    if (!field_filled("文件范围"))           V("「文件范围」为空")
    if (!field_filled("被谁挡"))             V("「被谁挡」为空（没有前置就写「无」）")

    st = md_token("状态")
    if (st == "") V("状态未声明（找不到 `- **状态**:` 行）")
    else if (st != "pending" && st != "in_progress" && st != "completed")
        V("状态 '" st "' 不在 {pending, in_progress, completed}")

    # 标记完成却回填不了提交，说明这个切片的状态是假的
    if (st == "completed" && !field_filled("主要提交")) V("状态是 completed，但「主要提交」没回填")

    if (!has_section("确认")) V("缺「## 确认」一节")
    else {
        n = count_checkboxes(section_text("确认"))
        if (n != 0) V("「## 确认」还有 " n " 项没勾")
    }
}

# ---------------------------------------------------------------- review.md（裁决单）

# 只有 T2 / T3 需要。模板里那几段说明文字如果被当成内容，一个没填的裁决单会通过。
function review_check(   i, undecided) {
    for (i = 1; i <= 5; i++)
        if (!has_section(REVIEW_SECS[i])) V("缺「## " REVIEW_SECS[i] "」一节")

    if (!field_filled("固定点")) V("「固定点」为空")
    if (table_rows(section_text("逐条处理"), 1) == 0) V("「## 逐条处理」表里没有任何条目")

    undecided = section_text("审查者明确未判断的")
    gsub(/[[:space:]]/, "", undecided)
    if (undecided == "")
        V("「## 审查者明确未判断的」留空了（一条都没有就写「无」）——把「没判断」显式化，人才能看出盲区在哪")
}
