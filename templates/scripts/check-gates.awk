# 闸门检查的判定逻辑。规则与消息的说明见 check-gates.sh 里的 check_*。
#
# 为什么判定在 awk 里而不是 bash：本机起一个外部进程约 27ms，而判定本身要做的
# 字符串扫描（一个任务目录 40 来次、每次上百行）在 bash 里约 13.7ms/120 行。
# 两者叠加让全量自查变成分钟级。搬进 awk 之后每个文件一次进程，循环在 C 里跑。
#
# 用法：
#   awk -v kind=plan|prd|journal|slice|review -v fpath=<路径> -f check-gates.awk <文件>
#       输出 `  [x] <路径>: <消息>` 行（没有违规就什么都不输出）
#
# 被闸门判定的字段只有一个写法：文件第一行的 `<!-- gate` 头块，块内一行一键
# `键: 值`。键固定 ASCII、值域封闭，写歪就是违规并报出正确写法——不静默兼容。
# 人读的散文区照旧自由写，闸门不再从散文里猜这些字段。
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

    # gate 头块：每类文件只认自己被查的那几个键。键名与值域都是封闭集合。
    # review.md 没有任何机器字段，所以一个键都不认（写了就是违规）。
    GATE_ALLOWED["plan"]    = " tier type "
    GATE_ALLOWED["prd"]     = " tier "
    GATE_ALLOWED["slice"]   = " tier type status commit "
    GATE_ALLOWED["journal"] = " status commit rejections "
    GATE_ALLOWED["review"]  = " "

    # 断链检查只认这些扩展名。见 emit_link 里的说明。
    _n = split("md sh awk bash ps1 cmd py pyi js mjs cjs ts tsx jsx json jsonc yaml yml toml ini cfg conf css scss sass less html htm vue svelte astro go rs java kt kts c h cc cpp hpp cs fs rb php pl lua sql txt csv tsv lock xml svg png jpg ico", _e, " ")
    for (_i = 1; _i <= _n; _i++) LINK_EXT[_e[_i]] = 1
}

# ---------------------------------------------------------------- 读入

{
    line = $0
    # 去掉行尾的 CR。MSYS 的 awk 跑在文本模式会自动吞掉，Linux / macOS 不会——
    # 不显式处理，同一份 CRLF 的 plan.md 在两个平台上会得到不同的闸门结果
    # （头块被判「起始行写法不对」，字段全读不到）。仓库锁 LF，但工作区文件
    # 可能是别处拷来的；判定必须与平台无关。
    sub(/\r$/, "", line)

    # kind=adr / kind=links 要一次扫多个文件（互链要跨文件判、断链要一次跑完），
    # 记下每个文件的起止：L[] 是跨文件累积的，不留边界就会把 A 的行算到 B 头上。
    if ((kind == "adr" || kind == "links") && FNR == 1) {
        FIDX++; FSTART[FIDX] = NL + 1; FNAME[FIDX] = FILENAME
    }

    # gate 头块必须在第一行，且是 HTML 注释——先按原文抓下来（键值判定不能靠剥完
    # 之后的残渣），抓到之后把这行清空：头块不参与正文解析。
    if (FNR == 1) {
        # 上一个文件留下的未闭合注释：多文件模式（adr / links）下不能算到
        # 这个文件头上，先按上一个文件的名字报掉。单文件模式只有 END 那条路。
        if (incom) { report_unclosed(prev_file); incom = 0 }
        prev_file = FILENAME
        GATE_N = 0; split("", GV)
        GATE_BAD_START = 0; GATE_MISPLACED = 0
        split("", NEAR_MISS)
        GATE_OPEN = (line == "<!-- gate")
        if (line != "<!-- gate" && line ~ /^[ \t]*<!--[ \t]*gate/) GATE_BAD_START = 1
        if (GATE_OPEN) line = ""
    } else if (GATE_OPEN) {
        if (line == "-->") GATE_OPEN = 0
        else GL[++GATE_N] = line
        line = ""
    } else if (line == "<!-- gate") {
        GATE_MISPLACED = 1
    }

    # 剥掉 markdown 注释（含跨行）。模板注释里会出现「应该可以」
    # 「（从 prd.md 提取）」这类字样，不剥掉的话会误报。
    #
    # 只有**行首**（允许前置空白）的 `<!--` 是注释起点。行内的 `<!--` 不是：
    # markdown 里它通常出现在行内代码里（`` `<!-- gate` ``），而正文谈论闸门机制时
    # 最自然的写法就是这个。以前只要行内出现 `<!--` 又没同行闭合，就进入跨行状态，
    # 把后面整篇吞掉——用户看到的是「缺 N 节」，一个字都不提真正的原因。
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
            if (q == 0) {
                if (head ~ /^[ \t]*$/) { line = head; incom = 1 }   # 行首：注释起点
                break                                                # 行内：当字面量，不动这行
            }
            line = head substr(rest, q + 3)
        }
    }
    gsub(/\t/, " ", line)

    L[++NL] = line
}

END {
    # 注释没闭合：正文从这里往后全被吞掉了，「缺 N 节」全是它的副作用。
    # 只报真因，然后停止这个文件的后续检查——否则真因淹没在十条假象里。
    if (incom) {
        report_unclosed(FILENAME)
        if (kind != "adr" && kind != "links" && kind != "modules" && kind != "related") exit
    }
    if (kind == "links")   { links_dump(); exit }
    if (kind == "adr")     { adr_check(); exit }
    if (kind == "modules") { modules_dump(); exit }
    if (kind == "related") { related_dump(); exit }
    if      (kind == "plan")    plan_check()
    else if (kind == "prd")     prd_check()
    else if (kind == "journal") journal_check()
    else if (kind == "slice")   slice_check()
    else if (kind == "review")  review_check()
}

# ---------------------------------------------------------------- 输出

function V(msg) { print "  [x] " fpath ": " msg }

# 未闭合注释按**文件名**报（多文件模式下 fpath 只有一个标签，看不出是哪个文件）。
function report_unclosed(name) {
    printf "  [x] %s: 有未闭合的 markdown 注释（`<!--` 之后没有 `-->`）——从这一行往后整篇都被当成注释了；先补上 `-->\n", name
}

# ---------------------------------------------------------------- 查询

# 标题级别（`## x` → 2，`### x` → 3）；不是标题返回 0。
# 只认 2 级及以上：`# 大标题` 在任务文件里当文档标题用，不当节。
function heading_level(s,   n) {
    if (substr(s, 1, 1) != "#") return 0
    n = 0
    while (substr(s, n + 1, 1) == "#") n++
    if (n < 2) return 0
    if (substr(s, n + 1, 1) !~ /[[:space:]]/) return 0
    return n
}

# 一个标题开一节（`### <标题>` 也算——模板不一定只用两级），
# 到下一个**同级或更高级**的标题为止。取第一个标题匹配 want 的（见 title_matches）。
# 这样 `### 步骤` 能被当成节，而节里更深的 `###` 子标题不会把它切断。
# 标题是否就是 want（或 want 后面紧跟括号/冒号/空格，如 `## 确认（可选）`）。
# 用「前缀 + 分隔符」而不是「含 want」：后者会让 `## 待确认事项` 顶替 `## 确认`，
# 一个已勾项的干扰节就能把真正的确认节挡在外面。
function title_matches(title, want,   rest) {
    if (title == want) return 1
    # 全程按**字节**比：`index` 是字节比较，`length(want)+1` 在两种 locale 下也都
    # 落在 want 之后（字节数一致）。用 substr(title, 1, length(want)) 那种字符切片
    # 在非 UTF-8 locale 下会把「确」字切一半，`## 确认（可选）` 就匹配不上了
    # （登录 shell 里 locale 正常，`env -u LANG` 才露馅）。
    if (index(title, want) != 1) return 0
    rest = substr(title, length(want) + 1)
    return (index(rest, " ") == 1 || index(rest, "（") == 1 || index(rest, "(") == 1 \
            || index(rest, ":") == 1 || index(rest, "：") == 1)
}

function md_section(want,   i, insec, lvl, hl, n, t) {
    n = 0; insec = 0; lvl = 0
    for (i = 1; i <= NL; i++) {
        hl = heading_level(L[i])
        if (hl > 0) {
            if (insec && hl <= lvl) break
            if (!insec) {
                t = L[i]
                sub(/^#+[[:space:]]+/, "", t)
                sub(/[[:space:]]+$/, "", t)
                if (title_matches(t, want)) { insec = 1; lvl = hl }
            }
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

# 是否存在匹配 want 的标题行（任意级别，`## 步骤` 和 `### 步骤` 都算）。
# 和 md_section 用同一个 title_matches——两边口径不一致时，
# 「有没有这个节」和「这个节里写了什么」会各看各的。
function has_section(want,   i, hl, t) {
    for (i = 1; i <= NL; i++) {
        hl = heading_level(L[i])
        if (hl == 0) continue
        t = L[i]
        sub(/^#+[[:space:]]+/, "", t)
        sub(/[[:space:]]+$/, "", t)
        if (title_matches(t, want)) return 1
    }
    return 0
}

# `- **标签**: 值` 行的原文（第一次出现）。没找到返回空串。
# 只认**一种**写法：`-` + 空格 + `**标签**` + 半角冒号。`*` / `+` 列表符和全角冒号
# 都不再兼容——写歪就是没写，闸门按「这个字段没填」报出来，不再猜作者的意思。
# 标签必须**精确**匹配 `**标签**`：用子串匹配会让 `- **非目标**: 这次什么都不做`
# 顶替空的 `- **目标**:`——判定「目标已填」，而目标根本没写。
function field_line_pat(lbl) { return "^[ \\t]*- \\*\\*" lbl "\\*\\*:" }

# 差一点的写法：同一行里有 `**标签**`，但不是唯一的写法（全角冒号、`*` / `+`
# 列表符、冒号前多了空格）。判据不因此放宽——**写歪就是没写**；但只报「字段为空」
# 的话，人会盯着一行看起来已经填好的字，找不到原因。所以每个标签额外提示一次。
function near_miss(lbl,   i, l, t, tag) {
    if (lbl in NEAR_MISS) return
    tag = "**" lbl "**"
    for (i = 1; i <= NL; i++) {
        l = L[i]
        if (index(l, tag) == 0) continue
        # 只认「去掉列表符之后就以标签开头」的行：正文里引用这个写法
        # （`例：- **目标**: 值`）不该被当成写歪的字段行。
        t = l
        sub(/^[ \t]*([-*+][ \t]+)?/, "", t)
        if (substr(t, 1, length(tag)) != tag) continue
        if (l ~ field_line_pat(lbl)) return          # 有正确写法，不需要提示
        NEAR_MISS[lbl] = 1
        V("`" lbl "` 这一行写法不对: `" l "` —— 只认 `- **" lbl "**: 值`（半角冒号，`-` 后面一个空格）；全角冒号、`*` / `+` 列表符都会被当成没填")
        return
    }
}
function field_value_of(r,   v) {
    v = r
    sub(/^[^:]*:[ \t]*/, "", v)
    return v
}
function field_value(lbl,   i, v) {
    near_miss(lbl)
    for (i = 1; i <= NL; i++) {
        if (L[i] !~ field_line_pat(lbl)) continue
        v = field_value_of(L[i])
        if (v != "") return v
        # 同行是空的：值可能换行写在下一行。遇到下一个字段行或标题行就停。
        while (++i <= NL) {
            if (L[i] ~ field_line_pat(lbl)) return ""
            if (L[i] ~ /^[ \t]*- \*\*/) return ""
            if (L[i] ~ /^[[:space:]]*#/) return ""
            if (L[i] !~ /^[[:space:]]*$/) return L[i]
        }
        return ""
    }
    return ""
}

# ---------------------------------------------------------------- gate 头块
#
# 头块是**唯一**的机器字段入口：本次任务被闸门判定的档位 / 类型 / 状态 /
# 主要提交 / 被打回次数都只从这里读。散文区里写同样的字不再被解析。

# 头块的取值（已经在 gate_check 里验过值域）。没写这一键返回空串。
function gate_value(k) { return (k in GV) ? GV[k] : "" }

# 报错里要给出能直接抄的那一行。
function gate_hint(kind, k) {
    if (k == "tier")   return "T2"
    if (k == "type")   return (kind == "slice") ? "slice" : "feat"
    if (k == "status") return (kind == "slice") ? "pending" : "DONE"
    if (k == "commit") return "3f9a1c2"
    return "0"
}

# 值域是封闭集合，逐键不同。slice 的类型轴是「切片 / 决策条目」、状态轴是
# pending / in_progress / completed；plan 的类型轴是 feat / refactor /
# bug-repro / bug-norepro；journal 的状态轴是四种结束状态。
function gate_value_ok(kind, k, v) {
    if (k == "tier") return v ~ /^T[0-3]$/
    if (k == "type") {
        if (kind == "slice") return v == "slice" || v == "decision"
        return v == "feat" || v == "refactor" || v == "bug-repro" || v == "bug-norepro"
    }
    if (k == "status") {
        if (kind == "slice") return v == "pending" || v == "in_progress" || v == "completed"
        return v == "DONE" || v == "DONE_WITH_CONCERNS" || v == "BLOCKED" || v == "NEEDS_CONTEXT"
    }
    if (k == "commit")     return v ~ /^[^ \t]+$/
    if (k == "rejections") return v ~ /^[0-9]+$/
    return 0
}

# 头块的语法与取值：
#   - 头块整个不在 → 不报「缺头块」，各字段按「未填」交给各自的检查（沿用旧语义：
#     plan 的档位/类型必填、prd 的可选、journal 的没填就是还没收尾）。
#   - 头块在但某一行写歪（全角冒号、大小写变体、多余文字、不认识的键、写两遍）
#     → 违规，消息里给出正确写法。
#   - `键:` 后面留空 = 这个键还没填（模板里就是留位用的）。
function gate_check(kind,   i, l, k, v, p, allowed, keys) {
    if (GATE_BAD_START) { V("gate 头块起始行写法不对：第一行必须正好是 `<!-- gate`（行首、无多余空格）"); GATE_BAD_START = 0 }
    if (GATE_MISPLACED) { V("gate 头块必须在文件第一行——`<!-- gate` 前面不能有空行、标题或别的注释"); GATE_MISPLACED = 0 }
    # 没闭合时 GL[] 里装的是整篇正文，剥注释也把正文一并吞了——各节检查会
    # 全部报「缺这一节」，把真正的原因埋掉。只报这一条，然后结束这个文件的检查。
    if (GATE_OPEN)      { V("gate 头块没有闭合：`<!-- gate` 之后要有一行正好是 `-->`"); exit }
    if (GATE_N == 0) return

    allowed = GATE_ALLOWED[kind]
    keys = allowed
    gsub(/^ +| +$/, "", keys)
    for (i = 1; i <= GATE_N; i++) {
        l = GL[i]
        if (l ~ /^[a-z]+:$/) { k = substr(l, 1, length(l) - 1); v = "" }
        else if (l ~ /^[a-z]+: /) {
            p = index(l, ": ")
            k = substr(l, 1, p - 1)
            v = substr(l, p + 2)
            if (v ~ /^[ \t]*$/) v = ""
        } else {
            V("gate 头块第 " i " 行写法不对: `" l "` —— 只认 `键: 值`（半角冒号 + 一个空格，行首行尾不许多余字符）；" kind ".md 认的键是 " keys)
            continue
        }
        if (index(allowed, " " k " ") == 0) {
            if (keys == "") V("gate 头块里不认键 `" k "`: " kind ".md 没有任何机器字段，头块里不该有键（删掉这一行）")
            else            V("gate 头块里不认键 `" k "`: " kind ".md 只认 " keys "（删掉这一行，或改成正确的键）")
            continue
        }
        if (k in GV) { V("gate 头块里 `" k "` 写了两遍：一个文件只有一个 " k " 值"); continue }
        if (v == "") continue            # 留空 = 还没填，交给各自的检查
        if (!gate_value_ok(kind, k, v)) {
            V("gate 头块 `" k ": " v "` 取值不对 —— 正确写法 `" k ": " gate_hint(kind, k) "`")
            continue
        }
        GV[k] = v
    }
}

# 字段行及其后续块（到下一个 `- **` 标签行或标题行为止）。返回行数，存进 B[]。
# 这里是**找块**不是**判写法**：列表符三种、冒号全半角都认。写法是否合规由
# field_value / near_miss 判——但「相关文件」的路径提取走这里，写歪的字段行
# 也要能把路径读出来，否则审查归属会静默漏掉这个任务（漏判比多判危险）。
function field_block(lbl,   i, n, found) {
    n = 0; found = 0
    for (i = 1; i <= NL; i++) {
        if (L[i] ~ /^[ \t]*[-*+][ \t]+\*\*/) {
            if (found) break
            if (index(L[i], "**" lbl "**") > 0) { found = 1; B[++n] = L[i]; continue }
        } else if (L[i] ~ /^[[:space:]]*#/) {
            if (found) break
        }
        if (found) B[++n] = L[i]
    }
    return n
}
# 字段块的宽松版：标签按**子串**找。只给「排序假设」用——模板里的标签是
# `**3–5 个排序假设**`（数量范围是标签的一部分），而判定器关心的是「下面列了几条」。
# 用整标签匹配的话，照模板写永远数出 0 条。别处一律走精确匹配（field_block）。
function field_block_loose(lbl,   i, n, found) {
    n = 0; found = 0
    for (i = 1; i <= NL; i++) {
        if (L[i] ~ /^[ \t]*[-*+][ \t]+\*\*/) {
            if (found) break
            if (index(L[i], lbl) > 0) { found = 1; B[++n] = L[i]; continue }
        } else if (L[i] ~ /^[[:space:]]*#/) {
            if (found) break
        }
        if (found) B[++n] = L[i]
    }
    return n
}
# 字段块**去掉字段行本身**之后的部分。要数条目时用这个：字段行自己也是
# `- **…**`，混进去会被当成一条。
function field_block_body(lbl,   n, i, out) {
    n = field_block(lbl)
    out = ""
    for (i = 2; i <= n; i++) out = out (i > 2 ? "\n" : "") B[i]
    sub(/\n+$/, "", out)
    return out
}
function field_block_body_loose(lbl,   n, i, out) {
    n = field_block_loose(lbl)
    out = ""
    for (i = 2; i <= n; i++) out = out (i > 2 ? "\n" : "") B[i]
    sub(/\n+$/, "", out)
    return out
}

# 整行只是「还没填」的标记。要精确，不能宽：
# `（npm test）` 这种全角括号里装着真内容是**合法值**，判成占位符会卡住用户；
# 反过来 `TODO` / `(待补)` / 单个 `-` 是最常见的偷懒写法，得算没填。
# 括号里的字用 `（` `）` 当字面量而不是塞进方括号——方括号是按字节比的，
# 多字节字符放进去会匹配到半个字。
function is_placeholder(s,   inner) {
    if (s == "（）" || s == "()") return 1
    # 括号里只有「占位符类」的字才算没填。**必须锚定整段**：
    # 用子串匹配的话 `（占位符长度计算）`、`（placeholder 属性生效）` 这种真内容
    # 会被判成空；反过来 `（TODO）` `（待办）` `（未填）` 这种偷懒写法又得算空。
    # 多字节字符用**分支**（`（|(`）而不是方括号——方括号是按字节比的，
    # 多字节字符放进去只能匹配到它的第一个字节。
    if (s ~ /^（.*）$/ || s ~ /^\(.*\)$/) {
        inner = s
        # 多字节字符只能用**字面量**匹配，不能进方括号：方括号是按字节比的，
        # `[（(]` 只会吃掉「（」的第一个字节，剩下的两个字节留在 inner 里，
        # 后面那条锚定的正则就永远匹配不上（C locale 下才露馅）。
        sub(/^（/, "", inner)
        sub(/^\(/, "", inner)
        sub(/）$/, "", inner)
        sub(/\)$/, "", inner)
        gsub(/[[:space:]]/, "", inner)
        inner = tolower(inner)
        return (inner ~ /^(占位|占位符|待补|待填|待定|待办|未填|未完成|placeholder|todo|tbd|xxx|na|n\/a|…|-+|这里写.*|填写.*)$/)
    }
    if (tolower(s) == "todo" || tolower(s) == "tbd" || s == "N/A" || tolower(s) == "na" || tolower(s) == "xxx") return 1
    if (s == "待办" || s == "未填" || s == "待补") return 1
    # 「无」「没有」「暂无」在一个**必填**字段里等于没写：目标写「无」就没有这次任务，
    # 验证命令写「无」就是没验证。逐字段放宽的地方（比如「涉及的 ADR: 无」）不走这里。
    if (s == "无" || s == "无。" || s == "没有" || s == "暂无" || s == "None" || s == "none") return 1
    if (s == "-" || s == "--" || s == "—" || s == "…" || s == "...") return 1
    return 0
}

# 字段是否有实质内容：同行冒号后非空（或换行写在下一行），
# 或后续块里去掉注释/空行/纯符号后还有东西。
# 两种「看着有内容其实没有」的值也算空：
#   - 空反引号：模板里的 `- **X**: \`\``
#   - 只剩模板提示：`- **X**: （占位）`
function field_filled(lbl,   s, n, j, l, body) {
    s = field_value(lbl)
    gsub(/[[:space:]]/, "", s)
    gsub(/`/, "", s)
    if (s == "") { }
    else if (is_placeholder(s)) { }
    else return 1

    n = field_block(lbl)
    body = ""
    for (j = 2; j <= n; j++) {          # 跳过字段行本身（同 tail -n +2）
        l = B[j]
        gsub(/<!--.*-->/, "", l)
        sub(/^[[:space:]]*[-*+][[:space:]]*/, "", l)
        gsub(/[[:space:]]/, "", l)
        if (l == "") continue
        if (is_placeholder(l)) continue  # 整行只是模板提示（占位）→ 不算内容
        if (l ~ /^`+$/) continue         # 整行只是空反引号 → 不算内容
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
        # 允许最多 3 个前导空格：CommonMark 里缩进 3 格的表格仍是表格。
        if (ROWS[i] !~ /^[[:space:]]*\|/) continue
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

# 未勾选的 `- [ ]`。跳过代码围栏内的行：把复选框包进 ``` 里就能同时骗过
# 「还有几项没勾」和「一条确认项都没有」——两条都只看行首，看不出那是个代码块。
# want: 0 = 只数没勾的，1 = 勾了没勾都数。
function count_checkboxes(text, want,   n, i, c, fence, marks) {
    n = split(text, ROWS, "\n"); c = 0; fence = 0; marks = 0
    for (i = 1; i <= n; i++)
        if (ROWS[i] ~ /^[[:space:]]*(```|~~~)/) marks++
    # 围栏数量是奇数说明**有一个没闭合**。这时不能把后面的行都当成代码块里的
    # ——那正好是一条「把没勾的项藏进未闭合围栏」的绕过路径。整份文档都不跳。
    if (marks % 2 == 0) {
        for (i = 1; i <= n; i++) {
            if (ROWS[i] ~ /^[[:space:]]*(```|~~~)/) { fence = !fence; continue }
            if (fence) { ROWS[i] = "" }      # 抹掉围栏内的行，下面的判定一视同仁
        }
    }
    # `[-]` 是「待定」写法：既不是勾也不是空框，原先两边都不数 → 一项「还没想好」
    # 能和行为「已确认」共存。判据改成「只要不是 [x]/[X] 就算没勾」。
    for (i = 1; i <= n; i++) {
        if (!(ROWS[i] ~ /^[[:space:]]*[-*+][[:space:]]+\[[[:space:]xX-]*\]/)) continue
        if (want) { if (ROWS[i] ~ /^[[:space:]]*[-*+][[:space:]]+\[[ xX]\]/) c++ }
        else      { if (ROWS[i] !~ /^[[:space:]]*[-*+][[:space:]]+\[[xX]\]/) c++ }
    }
    return c
}

# 项目符号或编号列表项。编号同时认 `1.` 和中文顿号 `1、`——只认半角点的话，
# 用顿号编号的验收标准会被判成「没有条目」。
function count_listitems(text,   n, i, c) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++)
        if (ROWS[i] ~ /^[[:space:]]*([-*+][[:space:]]+|(（|\()?[0-9]+([.]|、|\)|）)[[:space:]]*)[^[:space:]]/) c++
    return c
}

# 结果条目：列表项，但**不是标签行**——`- 未运行的检查及原因:` 这种以冒号结尾的是
# 让人去填的小标题，不是一条结果。只看「有没有列表项」会被模板里这一行骗过去。
function count_result_items(text,   n, i, c, t) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++) {
        if (ROWS[i] !~ /^[[:space:]]*([-*+][[:space:]]+|(（|\()?[0-9]+([.]|、|\)|）)[[:space:]]*)[^[:space:]]/) continue
        if (ROWS[i] ~ /(:|：)[[:space:]]*$/) continue
        # 占位符不算「有结果」：`- TODO`、`- 无`、`- 未运行的检查及原因: 无` 都是
        # 照抄模板就能出现的行，算进来的话「验证结果非空」这条检查等于没有。
        t = ROWS[i]
        sub(/^[[:space:]]*([-*+][[:space:]]+|(（|\()?[0-9]+([.]|、|\)|）)[[:space:]]*)/, "", t)
        sub(/^[[:space:]]*/, "", t)
        if (is_placeholder(t)) continue
        # `- 字段: 无` / `- 字段:` / `- **字段**: 无` 都不算结果：模板里本来就有
        # 「未运行的检查及原因: 无」这种行，照抄就非空的话这条检查形同虚设。
        if (t ~ /^[^:：]*[:：][[:space:]]*$/ || t ~ /^[^:：]*[:：][[:space:]]*(无|没有|N\/A|None|TODO)[[:space:]]*$/) continue
        if (t ~ /^\*\*(未运行的检查|没跑|未运行)[^*]*\*\*[[:space:]]*[:：]?[[:space:]]*(无|没有)?[[:space:]]*$/) continue
        c++
    }
    return c
}

# 列表条目数：编号（`1. xxx`）和项目符号（`- xxx`）都算。
# 排序假设那一栏只关心「写了几条」，不该因为用了项目符号就判成 0 条
# ——prd.md 的「验收标准」两种都收，两处口径要一致。
function count_items(text,   n, i, c) {
    n = split(text, ROWS, "\n"); c = 0
    for (i = 1; i <= n; i++)
        if (ROWS[i] ~ /^[[:space:]]*((（|\()?[0-9]+([.]|、|\)|）)[[:space:]]*|[-*+][[:space:]]+)[^[:space:]]/) c++
    return c
}

# ---------------------------------------------------------------- 模块表

# `## 模块划分` 表第 2 列声明的路径，去掉反引号与尾斜杠。
function modules_dump(   n, i, cells, nf, p, line, npaths, k, seg, prev_dir) {
    n = md_section("模块划分")
    for (i = 1; i <= n; i++) {
        if (S[i] !~ /^[[:space:]]*\|/) continue
        # markdown 表格里 `\|` 是**转义竖线**，不是列分隔。直接 split 会把它劈成两格，
        # 于是「模块名」里出现竖线时路径格整个前移：拿到的路径是个词，且真正的路径
        # 不再被检查。先用哨兵占住，切完再还原。
        line = S[i]
        gsub(/\\\|/, "\002", line)
        nf = split(line, cells, "|")
        if (nf < 3) continue
        p = cells[3]
        gsub(/\002/, "\\|", p)
        gsub(/`/, "", p)
        sub(/^[[:space:]]+/, "", p); sub(/[[:space:]]+$/, "", p)
        sub(/\/+$/, "", p)
        if (p == "" || p == "路径" || p ~ /^-+$/) continue
        # 一格可以写多个路径，用「空格 + 空格」分隔（`c++`、`a+b` 这类名字不能被切）。
        # 靠后的段如果自己不带 `/`，按**上一段所在的目录**解析——
        # `…/settings/lastSession.ts + closeToTray.ts` 的另一半在同一个目录里。
        npaths = split(p, PARTS, /[[:space:]]+\+[[:space:]]+/)
        prev_dir = ""
        for (k = 1; k <= npaths; k++) {
            seg = PARTS[k]
            gsub(/^[[:space:]]+/, "", seg); gsub(/[[:space:]]+$/, "", seg)
            sub(/\/+$/, "", seg)
            if (seg == "") continue
            if (index(seg, "/") == 0 && prev_dir != "") seg = prev_dir "/" seg
            print seg
            prev_dir = seg
            sub(/\/[^\/]*$/, "", prev_dir)
        }
    }
}

# plan.md 的「相关文件」列表：一行一个路径（去掉反引号、行尾说明、标点）。
# 用途只有一处：判断**这次提交的代码**是不是某个 T2/T3 任务计划里的文件。
# 归属本来靠人自觉（一个任务一个提交），但「先改代码、再补审查」时闸门原先
# 完全看不见——代码已经进了主干，审查还没做。
function related_dump(   i, n, l, first) {
    n = field_block("相关文件")
    if (n <= 0) return
    # 第 1 行是字段行本身，从第 2 行起是路径
    for (i = 2; i <= n; i++) {
        l = B[i]
        sub(/^[[:space:]]*[-*+][[:space:]]*/, "", l)
        sub(/<!--.*-->/, "", l)
        gsub(/`/, "", l)
        sub(/[[:space:]]*——.*$/, "", l)
        sub(/[[:space:]]*[（(].*$/, "", l)
        l = trim(l)
        if (l == "") continue
        # 一行写多个路径时，第一个 token 只是其中一个候选（`src/a.py, src/b.py`）。
        # 先剥标点再切空格，否则会留下 `src/a.py,` 这种拼不上文件的串。
        first = l
        sub(/[[:space:]].*$/, "", first)
        sub(/[，。；、,;]+$/, "", first)
        if (first != "") print first
        # 整行也输出一次：文件名里**带空格**时（`src/我的 文件.js`）只有整行才对得上。
        # 调用方按「任何一个候选匹配上就算命中」，多输出一个候选没有副作用。
        gsub(/[，。；、,;]+$/, "", l)
        if (l != "" && l != first) print l
    }
}

# ---------------------------------------------------------------- plan.md

# 「## 预估 diff 范围」里那三行有没有填东西。
# 判据只认 `新增 / 修改 / 删除文件: <值>` 且值非空。
# **「无」是合法值**：纯删除的任务「新增文件: 无」、纯新增的任务「删除文件: 无」，
# 三行全「无」只说明这个任务不改文件（纯文档/纯配置改动）。当占位符处理的话，
# 报错文案「没有数字也要写「无」」反而教人去写一个被判违规的值。
function diff_range_filled(   t, n, A, i, l, v) {
    t = section_text("预估 diff 范围")
    n = split(t, A, "\n")
    for (i = 1; i <= n; i++) {
        l = A[i]
        sub(/^[ \t]*[-*+][ \t]*/, "", l)
        if (l !~ /^(新增|修改|删除)文件[ \t]*[:：]/) continue
        v = l
        sub(/^[^:：]*[:：][ \t]*/, "", v)
        gsub(/[ \t`]/, "", v)
        if (v != "") return 1
    }
    return 0
}

# 「相关文件」里至少有一条**像路径**的条目（含 `/`、`\`，或以已知源码后缀结尾）。
# 只看非空判别的话，`  - 无` 这种列表形态会让整栏「已填」。
function related_has_path(   i, n, out) {
    n = field_block("相关文件")
    if (n <= 0) return 0
    # 第 1 行是字段行本身：`- **相关文件**: src/a.sh` 这种写在同一行的也要算。
    out = field_value("相关文件")
    sub(/<!--.*-->/, "", out)
    gsub(/`/, "", out)
    gsub(/[[:space:]]/, "", out)
    if (out != "" && (index(out, "/") > 0 || index(out, "\\") > 0 || out ~ /\.[A-Za-z0-9]+$/)) return 1
    for (i = 2; i <= n; i++) {
        out = B[i]
        sub(/^[[:space:]]*[-*+][[:space:]]*/, "", out)
        sub(/<!--.*-->/, "", out)
        gsub(/`/, "", out)
        gsub(/[[:space:]]/, "", out)
        if (out == "") continue
        if (index(out, "/") > 0 || index(out, "\\") > 0) return 1
        if (out ~ /\.[A-Za-z0-9]+$/) return 1
    }
    return 0
}

function plan_check(   tier, type, n, filled, hy, t) {
    # 档位与类型只从 gate 头块读（gate_check 已经验过值域）。
    gate_check("plan")
    if (!has_section("任务概要")) { V("缺「## 任务概要」一节"); return }

    tier = gate_value("tier")
    type = gate_value("type")
    if (tier == "") V("档位未声明（gate 头块的 `tier:` 没填；正确写法 `tier: T2`）")
    if (type == "") V("类型未声明（gate 头块的 `type:` 没填；正确写法 `type: feat`）")

    t = field_value("目标")
    gsub(/[[:space:]`]/, "", t)
    if (!field_filled("目标")) V("「目标」为空")
    else if (t == "无" || t == "无。" || t == "没有" || tolower(t) == "none")
        V("「目标」写的是「" t "」——没有目标就没有这次任务，缺目标说明还没想清楚要做什么")
    # 列表形态的「无」（`- **相关文件**:` 下一行 `  - 无`）也要算空：
    # 计划没说要动哪些文件，就没法判断实施有没有跑偏，也没法把提交归属到这个任务。
    if (!field_filled("相关文件")) V("「相关文件」为空")
    else if (!related_has_path())
        V("「相关文件」里没有一个像路径的条目——写目录或文件，别写「无」")
    if (!field_filled("验证命令")) V("「验证命令」为空")

    if (table_rows(section_text("步骤"), 1) == 0) V("「## 步骤」表里没有任何步骤")

    # 规模写进计划才有意义：看不到预估，实施时就无从判断「已经跑偏了」。
    # 这三行在模板里是**不带粗体**的 `- 新增文件: 无`，所以不能用 field_filled
    # （它只认 `- **标签**: 值`）——按节扫描。
    if (!has_section("预估 diff 范围")) V("缺「## 预估 diff 范围」一节")
    else if (!diff_range_filled())
        V("「## 预估 diff 范围」三行都空着——没有数字也要写「无」")

    # 确认清单：这一节必须存在、里面至少有一条确认项、且不能有未勾的
    if (!has_section("确认")) V("缺「## 确认」一节")
    else {
        t = section_text("确认")
        if (count_checkboxes(t, 1) == 0)
            V("「## 确认」里一条确认项都没有。照模板抄下来逐条勾选；确实不适用的条目**保留**并把理由写在条目后面（`- [x] 只改一个文件——本次只动一个函数`），不要删掉整节")
        n = count_checkboxes(t, 0)
        if (n != 0) V("「## 确认」还有 " n " 项没勾")
    }

    # 「（从 prd.md 提取）」这类模板提示现在放在注释里（读入时已被剥掉），
    # 所以「目标」只会因为真的没写才为空——上面那条 field_filled 就是这么来的。

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
        hy = count_items(field_block_body_loose("排序假设"))
        if (hy < 3) V("闸门 A —— 排序假设只有 " hy " 条（至少要 3 条）")
    }

    # 任务分级.md：bug 不可复现强制 T3
    if (type == "bug-norepro" && tier !~ /^T3$/)
        V("类型 bug-norepro 必须声明 T3（现在写的是 '" tier "')")
}

# ---------------------------------------------------------------- prd.md

# Spec 轴的基准。只卡两件机器能判的事：
#   1. 「## 验收标准」非空——AGENTS.md 的 Done Means 和 pre-review 的 Spec 轴
#      都拿它当指涉对象，缺了它 Spec 轴悬空。
#   2. gate 头块里的 tier 写歪了要报。**不要求它必须填**——prd.md 在 Step 3.2 落笔、
#      档位在 3.3 才定，强制存在会在中途提交时误报。
function prd_check(   acc) {
    gate_check("prd")

    acc = section_text("验收标准")
    if (!has_section("验收标准")) V("缺「## 验收标准」一节（Spec 轴和 Done Means 都拿它当基准）")
    else if (count_listitems(acc) == 0 && table_rows(acc, 0) == 0)
        V("「## 验收标准」里没有条目（列表或表格都行；节里只剩注释不算）")
}

# ---------------------------------------------------------------- journal.md

function journal_check(   i, missing, end_state, verify, changed) {
    gate_check("journal")
    missing = 0
    for (i = 1; i <= 11; i++) {
        if (!has_section(JOURNAL_SECS[i])) {
            V("缺「## " JOURNAL_SECS[i] "」一节")
            missing++
        }
    }
    if (missing > 0) return

    # 头块里的 status 没填 = 这个任务还没收尾（journal.md 按设计在 Step 3.11 才写，
    # 而 Step 3.9 的 `git add .` 会先把一份空模板扫进提交）。这时不查收尾字段：
    # 填了才校验，没填不算违规。
    end_state = gate_value("status")
    if (end_state == "") return

    # 「主要提交」与结束状态绑定：BLOCKED / NEEDS_CONTEXT 的任务可能一次提交都没有。
    if (end_state == "DONE" || end_state == "DONE_WITH_CONCERNS") {
        if (gate_value("commit") == "")
            V("结束状态是 " end_state "，但头块的 `commit:` 没填（写工作提交的 SHA，见 tasks/README.md；正确写法 `commit: 3f9a1c2`）")
    }

    verify = section_text("验证结果")
    if (table_rows(verify, 0) == 0 && count_result_items(verify) == 0)
        V("「## 验证结果」里没有一行结果（表格或项目符号列表都行）")
    if (index(verify, "应该可以") > 0) V("「## 验证结果」里出现「应该可以」——要贴实跑的命令与输出")

    changed = section_text("改动文件清单")
    if (table_rows(changed, 0) == 0) V("「## 改动文件清单」表里没有一行")
    # 只认「整个单元格就是一个占位符」的行。之前是「出现任何 <...> 就算」——
    # 那样 `Map<string, number>`、`<script>`、URL 里的尖括号都会被误判成残留占位符。
    if (changed ~ /src\/(\.|．)(\.|．)(\.|．)/ || changed ~ /src\/…/ \
        || changed ~ /\|[[:space:]]*`?<[^>]*>`?[[:space:]]*\|/)
        V("「## 改动文件清单」还留着模板占位符（src/... 或 <...>）")

    check_next_notes()
}

# 「下次注意什么」每条都要有去向。没有去向的提醒随任务归档就死了：`tasks/_archive/`
# 在全量自查里是跳过的，`self-audit` 走查的也是文档一致性、不读历史 journal。
# 这条只判**形式**（有没有写出口），不判内容质量——「写得对不对」机器管不了，
# 判质量只会退化成勾选表演。
#
# 笔迹只有一个：条目里要有一行正好是 `去向: docs` / `去向: adr` /
# `去向: memory` / `去向: journal` 之一。箭头写法（`→ pitfalls`）不再认——
# 四种值的含义写在 tasks/README.md，闸门只认那四个字面量。
# 按**条目**判：一个条目可以写两行（先说记住什么，去向另起一行）。
function check_next_notes(   n, i, l, txt, item, item_line, have_item) {
    if (!has_section("下次注意什么")) return
    txt = section_text("下次注意什么")
    n = split(txt, NN_LINES, "\n")
    have_item = 0
    item = ""; item_line = ""
    for (i = 1; i <= n; i++) {
        l = NN_LINES[i]
        gsub(/\r/, "", l)
        if (l ~ /^[ \t]*$/ || l ~ /^[ \t]*(```|~~~)/) continue

        if (is_bullet(l)) {
            flush_note(item, item_line, have_item)
            item = l; item_line = i; have_item = 1
        } else if (have_item) {
            item = item "\n" l            # 续行：并进上一个条目
        } else {
            item = item "\n" l            # 第一个条目之前就出现的注记
        }
    }
    flush_note(item, item_line, have_item)
}

# 条目符号。和 count_listitems 同口径：`-` `*` `+`、`1.` `1)`，以及中文的 `1、` `1）`。
# 只认半角点的话，用顿号编号的条目不被当成条目起始，整节会被并成一个条目，
# 只要其中任意一行有去向就全部放行——静默免检。
function is_bullet(l) { return l ~ /^[ \t]*([-*+][ \t]+|(（|\()?[0-9]+([.]|、|\)|）)[ \t]*)[^ \t]/ }

# 一个条目里只要**任何一行**是 `去向: <四选一>` 就算数。
function flush_note(item, item_line, have_item,   l, n, i, bare) {
    if (item == "") return
    n = split(item, NOTE_TMP, "\n")
    for (i = 1; i <= n; i++) {
        l = NOTE_TMP[i]
        gsub(/\r/, "", l)
        gsub(/^[ \t]+/, "", l)
        sub(/[ \t]+$/, "", l)
        # 整节只写「无」是合法写法：带条目符号的 `- 无` 也算。
        # 先剥条目符号再**逐字面量比较**，不把多字节字符写进正则的选择分支里：
        # 同一个正则在 Git for Windows 的 gawk 上匹配不到「无」（Windows CI 实测），
        # 而在别处能匹配——判据不能有这种平台分叉。
        bare = l
        sub(/^[ \t]*([-*+]|(（|\()?[0-9]+([.]|、|\)|）))[ \t]*/, "", bare)
        if (bare == "无" || bare == "无。" || bare == "N/A") return
        # 去向整行精确匹配：全角冒号、多一个词、写成箭头都算没写。
        if (l ~ /^去向: (docs|adr|memory|journal)$/) return
    }
    # 报错要能定位。条目可能以换行开头（前面是「第一个项目符号之前的散文」），
    # 直接剥前缀会剥空，消息就变成「没有去向:  —— …」，指不到任何东西。
    l = item
    while (substr(l, 1, 1) == "\n") l = substr(l, 2)
    sub(/^[ \t]*([-*+]|(（|\()?[0-9]+([.]|、|\)|）))[ \t]*/, "", l)
    sub(/\n.*/, "", l)
    V("「下次注意什么」这条没有去向: " l " —— 每条里要有一行 `去向: docs` / `去向: adr` / `去向: memory` / `去向: journal`")
}

# ---------------------------------------------------------------- NN-*.md 切片 / 决策条目

# 类型决定哪一节必填（同 plan.md 的「修 bug 时必填」）。类型、档位、状态与
# 主要提交都在 gate 头块里；优先级没有头块键，只认 `- **优先级**: P0` 这一种写法。
function slice_check(   type, tier, prio, st, n, t) {
    gate_check("slice")
    type = gate_value("type")
    if (type == "") { V("类型未声明（gate 头块的 `type:` 没填；正确写法 `type: slice`）"); return }

    if (type == "decision") {
        if (!field_filled("问题")) V("决策条目 —— 「问题」为空")
        if (!field_filled("结论")) V("决策条目 —— 「结论」为空")
        if (!field_filled("依据")) V("决策条目 —— 「依据」为空")
        return
    }

    tier = gate_value("tier")
    if (tier == "") V("档位未声明（gate 头块里没有 `tier:` 行；正确写法 `tier: T2`）")

    prio = field_value("优先级")
    sub(/[ \t]+$/, "", prio)
    if (prio == "") V("优先级未声明（正文里缺 `- **优先级**: P0` 这一行）")
    else if (prio != "P0" && prio != "P1" && prio != "P2")
        V("优先级 '" prio "' 不在 {P0, P1, P2}（正确写法 `- **优先级**: P0`）")

    if (!field_filled("完成后可以看到什么")) V("「完成后可以看到什么」为空")
    if (!field_filled("完成标准"))           V("「完成标准」为空")
    if (!field_filled("文件范围"))           V("「文件范围」为空")
    # 这一栏允许「无」（没有前置就写无），所以不能走把「无」当占位的 field_filled
    t = field_value("被谁挡")
    gsub(/[[:space:]`]/, "", t)
    if (t == "") V("「被谁挡」为空（没有前置就写「无」）")

    st = gate_value("status")
    if (st == "") V("状态未声明（gate 头块的 `status:` 没填；正确写法 `status: pending`）")

    # 标记完成却回填不了提交，说明这个切片的状态是假的
    if (st == "completed" && gate_value("commit") == "")
        V("状态是 completed，但头块里没有 `commit:` 行（正确写法 `commit: 3f9a1c2`）")

    if (!has_section("确认")) V("缺「## 确认」一节")
    else {
        t = section_text("确认")
        if (count_checkboxes(t, 1) == 0)
            V("「## 确认」里一条确认项都没有。照模板抄下来逐条勾选；确实不适用的条目**保留**并把理由写在条目后面，不要删掉整节")
        n = count_checkboxes(t, 0)
        if (n != 0) V("「## 确认」还有 " n " 项没勾")
    }
}

# ---------------------------------------------------------------- review.md（裁决单）

# 只有 T2 / T3 需要。模板里那几段说明文字如果被当成内容，一个没填的裁决单会通过。
function review_check(   i, undecided) {
    gate_check("review")
    for (i = 1; i <= 5; i++)
        if (!has_section(REVIEW_SECS[i])) V("缺「## " REVIEW_SECS[i] "」一节")

    # 这几项原先没查：整份裁决单只填「固定点」+ 一行处理表就能过，
    # 而文档写的是「是否存在且**填全**」。独立审查是 T2/T3 最贵的机制，
    # 闸门在它上面留白，等于把「审过了」变成一句自我声明。
    if (!field_filled("固定点")) V("「固定点」为空")
    if (!field_filled("审查者")) V("「审查者」为空——写明是谁审的（独立子 agent / 人）")
    if (!field_filled("给了它什么")) V("「给了它什么」为空——独立审查的前提是输入自包含；不记下来，没人能判断它看得全不全")
    if (!field_filled("轮次")) V("「轮次」为空（第一轮写 `1`）")
    t = section_text("结论")
    gsub(/[[:space:]]/, "", t)
    if (t == "") V("「## 结论」留空了——一轮审完要给出可以合 / 不能合的判断")
    if (table_rows(section_text("逐条处理"), 1) == 0) V("「## 逐条处理」表里没有任何条目")

    t = section_text("审查者原文")
    gsub(/[[:space:]]/, "", t)
    if (t == "")
        V("「## 审查者原文」留空了——审查者的报告要逐字贴进来，那是「它真的审过」的唯一证据")

    undecided = section_text("审查者明确未判断的")
    gsub(/[[:space:]]/, "", undecided)
    if (undecided == "")
        V("「## 审查者明确未判断的」留空了（一条都没有就写「无」）——把「没判断」显式化，人才能看出盲区在哪")
}

# ---------------------------------------------------------------- 文档内的相对引用

# 输出 `文件<TAB>引用`，由 bash 逐个 stat。放在 awk 里是为了
# 「一个 markdown 解析器」——围栏代码块、行内代码、注释的剥离规则和别的检查同一套，
# 否则会出现「文档里贴了一段命令，闸门把命令里的路径当真」。
#
# 跳过的东西（都是模板里真实存在的写法）：
#   - 围栏代码块内的内容（示例命令、目录树）
#   - 带占位符的路径：`<日期>` `{x}` `*` `$`
#   - 外部链接、锚点、绝对路径
function links_dump(   i, j, end, l, fence, segs, n, k, s, r) {
    for (i = 1; i <= FIDX; i++) {
        end = (i < FIDX ? FSTART[i + 1] : NL + 1)
        fence = 0
        for (j = FSTART[i]; j < end; j++) {
            l = L[j]
            if (l ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
            if (fence) continue

            # 行内代码：`path`
            n = split(l, segs, "`")
            for (k = 2; k <= n; k += 2) emit_link(FNAME[i], trim(segs[k]))

            # markdown 链接：[文字](path)
            r = l
            while (match(r, /\]\([^)]+\)/)) {
                s = substr(r, RSTART + 2, RLENGTH - 3)
                emit_link(FNAME[i], trim(s))
                r = substr(r, RSTART + RLENGTH)
            }
        }
    }
}

function trim(s) {
    sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
    sub(/^["']/, "", s); sub(/["']$/, "", s)
    return s
}

# 百分号解码：CommonMark 允许 `%XX`。只处理 `%20` 的话，中文文件名
# （`docs/%E6%88%91.md`）会被判成断链。按字节解成对应字符即可——我们只拿它
# 跟文件系统比，不关心它是不是合法 UTF-8 序列。
function pct_decode(s,   out, i, hex, n, b) {
    out = ""
    n = length(s)
    for (i = 1; i <= n; i++) {
        if (substr(s, i, 1) == "%" && i + 2 <= n &&
            substr(s, i + 1, 2) ~ /^[0-9A-Fa-f][0-9A-Fa-f]$/) {
            hex = substr(s, i + 1, 2)
            b = hex_val(hex)
            out = out sprintf("%c", b)
            i += 2
        } else {
            out = out substr(s, i, 1)
        }
    }
    return out
}

function hex_val(h,   i, v, d) {
    v = 0
    for (i = 1; i <= 2; i++) {
        d = index("0123456789abcdef", tolower(substr(h, i, 1)))
        v = v * 16 + (d - 1)
    }
    return v
}

function emit_link(file, s,   last, t, ext, had_pct) {
    if (s == "") return
    # `%20` 是 URL 编码的空格（CommonMark 里合法）。先解码，否则含空格的真路径
    # 会被下面「含空格 = 不是路径」那条误判成断链。
    had_pct = 0
    if (index(s, "%") > 0) { s = pct_decode(s); had_pct = 1 }
    # 不是相对路径：外部 URL、锚点、绝对路径、带占位符/通配符的
    if (s ~ /^[a-zA-Z]+:\/\//) return
    if (s ~ /^#/) return
    if (s ~ /^\//) return
    if (s ~ /[<>{}*$|]/) return
    if (s ~ /\.\.\./) return
    if (s ~ /NNNN/) return
    # 反斜杠写法（Windows `docs\\x.md`）先归一再判。
    gsub(/\\/, "/", s)
    # 锚点 / 查询串 / 链接标题：`docs/x.md#a`、`docs/x.md?raw=1`、`docs/x.md "标题"`。
    # 三种都属于「目标文件就是前面那一段」，剥掉再 stat —— 不剥就等于给断链开后门。
    sub(/#.*$/, "", s)
    sub(/\?.*$/, "", s)
    sub(/[ \t]+"[^"]*"[ \t]*$/, "", s)
    sub(/[ \t]+'[^']*'[ \t]*$/, "", s)
    # 链接提取按 `](` 到最后一个 `)` 截断，行尾那个右引号会被截掉，剩下半个标题：
    # `docs/x.md "标题`。这种半截也剥掉，否则带标题的链接一律漏检。
    sub(/[ \t]+"[^"]*$/, "", s)
    sub(/[ \t]+'[^']*$/, "", s)
    # `..` 逃出仓库根的不是「项目内引用」，不归闸门管（也可能指到别处去）。
    if (s ~ /^\.\.\// || index(s, "/../") > 0) return
    if (s == "") return
    # 日期占位符：`reports/YYYY-MM-DD.md`、`history_YYYY-MM.json`。
    # 命名约定不是路径，但它们的扩展名看着像文件，只能靠 YYYY 认出来。
    if (index(s, "YYYY") > 0) return
    # 以点开头的是类名/选择器列表（`.card/.kpi-card/.topbar`）。真正的相对路径
    # 只有 `./x` 一种写法，单独放行。
    if (substr(s, 1, 1) == "." && substr(s, 1, 2) != "./") return
    if (s ~ /[ \t]/ && !had_pct) return
    # env 赋值 / shell 片段：`KEY=/path`、`--out=docs/x.md`。
    # 用「前缀 + =」而不是「整串含 =」：后者会漏掉 `src/a=b.py` 这种真文件名。
    if (s ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || s ~ /^--[A-Za-z0-9-]+=/) return
    # 后缀不属于路径：pytest node id `path::test_x`、行号 `path:120`、
    # 模块属性 `web/app.py:_ASSET_FILES`。剥掉之后**只判文件那一段**。
    # 先剥 `::` 再剥 `:120` / `:IDENT`，复合写法 `x.md:12::foo` 需要这个顺序。
    sub(/::.*$/, "", s)
    sub(/:[0-9]+$/, "", s)
    sub(/:[A-Za-z_][A-Za-z0-9_]*$/, "", s)
    if (s == "") return
    # 不带 `/` 的引用不查。曾经想查（`` `NOTHERE.md` ``），结果模板里的示例名
    # （`0001-slug.md`、`NN-描述.md`）全部被判断链——每个新项目一生成就红 4 条。
    # 文档里不带 `/` 的名字绝大多数是**示例或简称**，机器分不清它和真断链；
    # 这条留给 self-audit 用眼睛看。
    if (index(s, "/") == 0) return

    # **只查认得扩展名的引用。** 这一条同时挡掉模块属性（`env_util.require_env`）、
    # 常量引用（`x.KINDS`）、npm 包名（`@scope/pkg@1.2.0`）、点号表达式（`.is_readonly(`）
    # ——它们的「扩展名」是标识符片段，不是文件类型。
    # 代价：项目用了列表外的后缀时查不到；加后缀比加特例便宜。
    last = s
    sub(/[\/]+$/, "", last)
    # 裸域名（`youtu.be/`）：去掉尾斜杠后没有内部 `/`，不是相对路径
    if (index(last, "/") == 0) return
    sub(/.*\//, "", last)
    ext = tolower(last)
    if (ext !~ /\./) return
    sub(/.*\./, "", ext)
    if (!(ext in LINK_EXT)) return
    # 去掉行尾的标点（中文句读紧跟在反引号外的情形）
    sub(/[，。；：、）)]+$/, "", s)
    if (s == "" || index(s, "/") == 0) return
    print file "\t" s
}

# ---------------------------------------------------------------- ADR

# 一次扫 docs/adr/*.md。检查两件事：
#   1. 任何 `ADR-<4 位数字>` 引用都要有对应的文件
#   2. 被取代必须互链：A 写 Superseded-By: ADR-0007，0007 就得写 Supersedes: ADR-0001
#
# 为什么必须互链：只说「这被取代了」而不说「被谁取代」，半年后读的人走到断头路；
# 只在新的那篇里写「我取代了旧的」，旧的那篇就会继续被人当成现行决定引用。
function adr_check(   i, j, end, l, ll, id, ids, n, k, r, t, have, fence) {
    for (i = 1; i <= FIDX; i++) {
        end = (i < FIDX ? FSTART[i + 1] : NL + 1)
        id = adr_id(FNAME[i])
        if (id == "") continue
        ADR_FILE[id] = FNAME[i]

        fence = 0
        for (j = FSTART[i]; j < end; j++) {
            l = L[j]
            # 围栏代码块里的是**示例**（「长这样」），不是引用。
            # 当成引用会把每一篇写着格式示例的 ADR 判成悬空链接。
            if (l ~ /^[ \t]*(```|~~~)/) { fence = !fence; continue }
            if (fence) continue
            # 键名大小写不敏感：`superseded-by:` / `Supersedes:` 都是同一个字段。
            # 只认一种写法等于给「写歪一格」开后门——互指检查会静默不触发。
            ll = tolower(l)
            # 加粗写法 `- **Status**: accepted` 也要认：去掉行首列表符号与 `**`，
            # 否则三条 ADR 检查（存在性 / 互指 / 状态）会一起静默跳过。
            sub(/^[ \t]*[-*+][ \t]+/, "", ll)
            gsub(/\*\*/, "", ll)
            ll = trim(ll)

            if (match(ll, /superseded-by:[ \t]*adr-[0-9][0-9][0-9][0-9]/)) {
                # 从小写那份里取编号：原行可能是 `adr-0002`，用 /ADR-/ 剥会剥不掉，
                # 整段匹配就成了「引用了 ADR-Superseded-By:」这种伪造违规。
                t = substr(ll, RSTART, RLENGTH); sub(/.*adr-/, "", t)
                SUPER_BY[id] = SUPER_BY[id] " " t
            }
            if (match(ll, /supersedes:[ \t]*adr-[0-9][0-9][0-9][0-9]/)) {
                t = substr(ll, RSTART, RLENGTH); sub(/.*adr-/, "", t)
                SUPERSEDES[id] = SUPERSEDES[id] " " t
            }
            # 冒号前允许空格：`Status : accepted` 是合法的 YAML 风格写法
            if (match(ll, /^status[ \t]*:[ \t]*[a-z-]+/)) {
                t = substr(ll, RSTART, RLENGTH); sub(/^status[ \t]*:[ \t]*/, "", t)
                STATUS[id] = tolower(t)
            }

            # 正文/小节里出现的所有引用
            r = l
            # 编号必须是 4 位。只匹配 4 位等于把 `ADR-00012` 静默忽略（既不查存在、
            # 也不报格式），实测能过；所以这里认「任意位数」，非 4 位的单独报出来。
            while (match(r, /ADR-[0-9]+/)) {
                t = substr(r, RSTART + 4, RLENGTH - 4)
                if (length(t) == 4) ALSO[id] = ALSO[id] " " t
                else BADADR[id] = BADADR[id] " " t
                r = substr(r, RSTART + RLENGTH)
            }
        }
    }

    # 0. 编号格式（4 位）——格式错了就没有「对应文件」可查，必须单独报
    for (i = 1; i <= FIDX; i++) {
        id = adr_id(FNAME[i])
        if (id == "") continue
        n = split(BADADR[id], BAD, " ")
        for (k = 1; k <= n; k++) {
            if (BAD[k] == "") continue
            print "  [x] " FNAME[i] ": 引用了 ADR-" BAD[k] "，编号必须是 4 位（ADR-NNNN）"
        }
    }

    # 1. 引用存在性
    for (i = 1; i <= FIDX; i++) {
        id = adr_id(FNAME[i])
        if (id == "") continue
        n = split(ALSO[id] " " SUPER_BY[id] " " SUPERSEDES[id], REFS, " ")
        for (k = 1; k <= n; k++) {
            t = REFS[k]
            if (t == "" || t == id) continue
            if (!(t in ADR_FILE)) {
                if (index(SEEN[id ">" t], "x") == 0) {
                    SEEN[id ">" t] = "x"
                    print "  [x] " FNAME[i] ": 引用了 ADR-" t "，但 docs/adr/ 里没有这个文件"
                }
            }
        }
    }

    # 2. 互链
    for (i = 1; i <= FIDX; i++) {
        id = adr_id(FNAME[i])
        if (id == "") continue

        n = split(SUPER_BY[id], REFS, " ")
        for (k = 1; k <= n; k++) {
            t = REFS[k]
            if (t == "" || !(t in ADR_FILE)) continue
            if (index(" " SUPERSEDES[t] " ", " " id " ") == 0)
                print "  [x] " FNAME[i] ": 写了 Superseded-By: ADR-" t "，但 ADR-" t " 里没有 `Supersedes: ADR-" id "`"
        }

        n = split(SUPERSEDES[id], REFS, " ")
        for (k = 1; k <= n; k++) {
            t = REFS[k]
            if (t == "" || !(t in ADR_FILE)) continue
            if (index(" " SUPER_BY[t] " ", " " id " ") == 0)
                print "  [x] " FNAME[i] ": 写了 Supersedes: ADR-" t "，但 ADR-" t " 里没有 `Superseded-By: ADR-" id "`"
        }
    }

    # 3. 归档/取代过的 ADR 不该还写着 accepted
    for (i = 1; i <= FIDX; i++) {
        id = adr_id(FNAME[i])
        if (id == "" || SUPER_BY[id] == "") continue
        if (STATUS[id] != "" && STATUS[id] != "superseded")
            print "  [x] " FNAME[i] ": 已经写了 Superseded-By，但 Status 是 '" STATUS[id] "'（应为 superseded）"
    }
}

function adr_id(f,   b, id) {
    b = f; sub(/.*\//, "", b)
    if (b !~ /^[0-9][0-9][0-9][0-9]-/) return ""
    id = substr(b, 1, 4)
    return id
}
