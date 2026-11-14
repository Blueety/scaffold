#!/usr/bin/env bash
#
# >>> usage
# 闸门检查器 —— 把「能机器判定的闸门」变成可执行检查。
#
#   scripts/check-gates.sh                 检查全仓库：tasks/ 下在飞的任务 + 全仓库的闸门 B
#                                          （tasks/_archive/ 跳过——见 tasks/README.md 的「归档」）
#   scripts/check-gates.sh --staged        检查索引内容（= 这次提交后的仓库状态；
#                                          任务目录只挑这次改动涉及的，pre-commit 钩子用）
#   scripts/check-gates.sh tasks/2026-08-04-add-login [...]
#
# 覆盖：
#   - 闸门 B：非 .md 文件里没有 [DEBUG- 残留（大小写不敏感；.md 是文档，会引用这个约定）。
#              排除 scripts/check-gates.sh 自身、node_modules/、二进制文件；
#              全量模式还排除 .gitignore 命中的本地文件（那是数据不是代码）。
#              唯一豁免（文件级）：第一行精确等于 `# gate-b: mentions-marker`
#              的文件整体不报——由文件自己声明「本文在谈论这个标记」；
#              首行是 shebang 的可执行脚本看第二行。
#   机器字段只有一个写法：文件第一行的 `<!-- gate` 头块，块内一行一键 `键: 值`
#   （半角冒号 + 一个空格，键固定 ASCII）。块内写歪（全角冒号、大小写变体、多余文字、
#   不认识的键）一律报违规并给出正确写法；`键:` 后面留空 = 还没填。散文区里写这些
#   字段不再被读取。每类文件只认自己那几个键：
#     plan.md    tier ∈ T0–T3、type ∈ feat / refactor / bug-repro / bug-norepro
#     prd.md     tier（可选）
#     journal.md status ∈ DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT、
#                commit（一个 SHA）、rejections（十进制整数）
#     NN-*.md    type ∈ slice / decision、tier、status ∈ pending / in_progress / completed、commit
#   判注释只认**行首**的 `<!--`：正文/行内代码里出现的 `<!--` 当字面量（文档谈论闸门
#   机制时最自然的写法就是这个形）。行首的注释没闭合时只报这一条真因并跳过该文件的
#   其余检查——以前会把后文整篇吞掉，然后报十条「缺 N 节」。
#   - plan.md：头块里的档位与类型已声明、目标 / 相关文件 / 验证命令非空、步骤表非空、
#              确认清单至少一条且全勾、
#              目标不能写「无」、预估 diff 范围三行不能全空、
#              测试 Seam 四行要么全填要么全空、
#              bug 任务的闸门 A 字段（含 ≥3 条排序假设，数的是 `- **3–5 个排序假设**:`
#              下面列了几条，标签里带不带 `3–5 个` 都认）、bug-norepro 必须声明 T3
#   - prd.md：验收标准非空且有条目；头块里的 tier 填了就必须合法（不强制存在）
#   - journal.md：章节齐全（含雾区变化 / 一致性走查）、头块的 status 合法、验证结果有内容且不写「应该可以」、
#                 改动清单已填且没留模板占位符（src/... 或 <...>）、
#                 status 是 DONE / DONE_WITH_CONCERNS 时头块的 commit 必须回填、
#                 「下次注意什么」每一条都有一行 `去向: docs` / `去向: adr` /
#                 `去向: memory` / `去向: journal`——只判有没有出口，不判内容质量。
#                 「验证结果」的判据是**有证据**：`- TODO`、`- 无`、`- 字段: 无` 一律不算
#                 结果（全过就写表格或带证据的条目，例如 `- npm test: 12 passed`）
#   - NN-*.md（切片）：头块的 type / tier / status 合法、优先级（正文 `- **优先级**: P0`）合法、
#                      演示与完成标准非空、文件范围与被谁挡已填、确认清单至少一条且全勾、
#                      status 是 completed 时头块的 commit 必须回填；
#                      决策条目则要求问题 / 结论 / 依据三字段非空
#   - review.md（裁决单）：任务档位是 T2 / T3、且任务**已经开工**时必须存在——plan.md /
#                          prd.md / 切片里**任何一处**的头块写了 `tier: T2` / `tier: T3` 就算，
#                          不依赖 plan.md 是否存在；三个版本（索引 / HEAD / 工作区）取并集。
#                          （只提交了 prd.md 的计划阶段还不要求，那时候还没东西可审）
#                          章节齐全、固定点 / 审查者 / 给了它什么 / 轮次 / 结论都已填、
#                          审查者原文非空、逐条处理表非空、「审查者明确未判断的」不许留空
#   - 文档内相对引用：根目录 md、docs/、skills/、tasks/README.md 里用反引号或
#                      markdown 链接写下的相对路径必须存在（围栏代码块、带占位符的
#                      示例不算）。**不带 `/` 的引用不查**（`NOTHERE.md`、`0001-slug.md`）
#                      ——文档里这种名字绝大多数是示例或简称，模板自己的示例名会被
#                      误判，新项目一生成就红。其他位置的 md 不查——第三方目录里的
#                      README 是别人的文档，扫进来只会误报；tasks/ 其余部分是快照。
#                      --staged 时文档内容取索引，但引用目标的存在性回工作区判
#                      （产物在 .gitignore 里，索引物化树里没有）。
#   - docs/adr/*.md：文件里出现的任何 `ADR-NNNN` 引用都要有对应文件（其它文档里的
#                引用不查）；`Superseded-By` 与 `Supersedes` 必须互指；写了
#                Superseded-By 就不能还是 `Status: accepted`
#   - 活文档里不许写死 fixture 的断言项数（会漂）：同一行既有 `fixtures/*.sh` 又有
#                `N 项` 就报。真实项数只有跑完 fixture 才知道，所以规矩是「文档里
#                只写时长与覆盖范围」。
#   - 决策锚点（只提示，不影响退出码）：代码里的 `# 决策: ADR-NNNN` 注释，
#                指向不存在的 ADR 或没写目标时打一条 [!]。
#   - 架构：docs/architecture.md 的模块表 vs 实际模块目录（双向，模块根默认 src）。
#          表里全是宽声明（模块根本身或它的祖先）时，全量自查会提示一句：新增子目录不会被检查。
#          模块目录 = 模块根下**非空**的直接子目录（全量模式含还没 git add 的；--staged
#          取索引物化树，未跟踪目录不可见），点目录和被
#          .gitignore 命中的除外；空目录不算——git 不跟踪空目录，声明它反而会卡住提交。
#          模块根本身不查存在性（空目录进不了 git，clone 之后它会消失）
#
#   - 只改代码的提交（--staged）：如果这次动的文件出现在某个 T2/T3 任务 plan.md 的
#          「相关文件」里，而那个任务还没有非空的 review.md，拦下——这是「先提交代码、
#          后补审查」的入口。计划、prd、切片与裁决单都取 HEAD ∪ 索引 ∪ 工作区 的并集。
#   - 任务目录里的文件名：只认 plan / prd / journal / review 与 NN-*.md（NN 1–2 位）；
#          三位以上数字开头的按笔记算（只提示），其余报错——否则整份文件静默免检。
#   - 索引物化可信性（仅 --staged）：物化后核对「每个索引文件都在、内容哈希等于 blob」。
#          checkout-index 会跳过 skip-worktree、也会套 smudge 过滤器——两种情况下检查器
#          看到的都不是要提交的东西（任务整个消失 / 被洗白的 plan），一律中止（exit 2）。
#   - 规模底线（仅 --staged）：任务在模块根下**累计**改动的文件数 ≥ 4 时，必须有任务目录
#          声明 T2/T3。累计从 plan.md 进入历史的那次提交之前算起——按单次提交算的话，
#          把 T2 的活拆成两次提交就能溜过去。只查低报：T0 / T1 的档位声明不再等人确认，
#          这条是它的机械底线。只数模块根下的文件（文档、tasks/ 不计），阈值对齐 6 条信号。
#
# 不覆盖（判断性内容，留在 skills/ 里由人确认）：
#   双轴不合并、一次性脚本是否真删干净、命令是否真跑过、
#   档位**高报**（声明得比实际大），以及 6 条信号里的跨模块 / 动公开接口 /
#   行为变化 / 不可逆性四条——只有文件数一条两侧都查：≥ 4 必须在 T2/T3。
#   **任务是否真的收尾了**（journal.md 在提交之后才写，机器判断不了「这个任务结束了没有」）。
#
# 退出码：0 = 通过，1 = 有违规，2 = 用法错误。
#
# 兼容性：**bash 3.2 起**。数组是本文件的基础设施，所以 dash 一类的 POSIX sh 跑不了；
# macOS 的 /bin/sh 是 bash 3.2 的 POSIX 模式，可以跑，但那种模式**没有进程替换**
# （`< <(cmd)` 会让整个文件解析失败，一条检查都跑不到）——按行读命令输出一律走
# 文件顶部定义的 `feed`。
# <<< usage

set -u

# 忽略 SIGPIPE。钩子是被 git 直接执行的：`git commit 2>&1 | head -1` 这类写法会让
# 读端提前退出，脚本写到第二行就吃 SIGPIPE，死在半路——实测 git 会**照常提交**
# （exit 0，闸门等于没跑）。把 SIGPIPE 改成写失败，脚本就能跑完并正常返回 1。
trap '' PIPE

violations=0

# 闸门 B 的文件级豁免声明。只有这一种写法（ASCII、行尾不许多余空白）：
# 声明在允许写注释的位置的第一行——首行是 shebang 的脚本看第二行。
GATE_B_DECL='# gate-b: mentions-marker'
# 行尾 CR。判定必须与平台无关：MSYS 的工具在文本模式下替我们吞掉 CR，
# Linux / macOS 不吞。
CR=$'\r'

fail() { printf '  [x] %s\n' "$*"; violations=$((violations + 1)); }

# POSIX 的 sh 没有进程替换。macOS 的 /bin/sh 是 bash 3.2 的 POSIX 模式，脚本里写
# `done < <(cmd)` 会让**整个文件解析失败**（syntax error near unexpected token `<`），
# 一条检查都跑不到。所以「按行读某个命令的输出」一律改成先落盘再重定向：
#
#     while IFS= read -r x; do ...; done < "$(cmd | feed)"
#
# feed 把 stdin 写进临时文件并打印路径；循环体仍跑在当前 shell（变量不丢），
# 与进程替换语义相同。
#
# 临时目录在**顶层**建好、顶层注册 EXIT trap：feed 自己跑在 `$(...)` 子 shell 里，
# 在那里 mktemp -d 或注册 trap 都只作用于子 shell —— 目录会漏，trap 永远不执行。
# 命令替换的子 shell 不会触发 EXIT trap（实测），所以这一份在脚本结束时才删。
GATES_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gates.XXXXXX")" || {
    printf '  [x] 无法创建临时目录（mktemp -d 失败）\n' >&2
    exit 2
}
trap 'rm -rf "$GATES_TMP"' EXIT

feed() {
    _feed_file="$(mktemp "$GATES_TMP/feed.XXXXXX")" || exit 2
    cat > "$_feed_file"
    printf '%s\n' "$_feed_file"
}

# 提示，不是失败：计入输出，不影响退出码。用于「检查器当前覆盖不到」这类
# 需要人知道、但项目现状本身没错的情况。
note() { printf '  [!] %s\n' "$*"; }

# 「活文档」的位置定义——两处检查共用一份。排除清单会随时间变长，而「文档该放
# 哪儿」本来就是定好的：仓库根、`docs/`、`skills/`、`tasks/README.md` 三处之外
# 的 md 是快照（`tasks/<任务>/`）或别人的文档（`vendor/`、依赖包）。
is_doc_path() {
    case "$1" in
        tasks/README.md) return 0 ;;
        docs/*|skills/*) return 0 ;;
        */*) return 1 ;;
        *) return 0 ;;
    esac
}

# 用法说明就是文件头那段，用哨兵行圈出来 —— 写死行号会在加注释时漂移。
usage() {
    sed -n '/^# >>> usage$/,/^# <<< usage$/p' "${BASH_SOURCE[0]}" | sed '1d;$d' | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------- 各项检查
#
# 逐文件的判定逻辑整体在 check-gates.awk 里。为什么搬过去：本机起一个外部进程
# 约 27ms，而判定要做的字符串扫描（一个任务目录 40 来次、每次上百行）在 bash 里
# 约 13.7ms/120 行。两者叠加让全量自查变成分钟级；搬进 awk 后每个文件一次进程，
# 循环在 C 里跑。这里只负责挑文件、起进程、把违规行打出来并计数。

# 闸门 B：[DEBUG- 残留。
#   --staged 查索引（git grep --cached，范围 = 这次提交后的仓库，不物化临时树）；
#   全量扫工作区（含未跟踪，不含 .gitignore 命中的本地数据）；不在 git 仓库时退回 find。
# 不用 -I：按「二进制」跳过的判定含 NUL 字节、含 `.gitattributes` 的 `-diff`——
#   一行 `*.py -diff` 就能让所有 .py 免疫。改成用 -a 强制文本扫 + 按后缀排除（bins）。
# 判据只管 ASCII 写法和「夹了不可见字符」的写法：归一化删所有非 ASCII 字节，
#   `[DEBU<ZWSP>G-` 会拼回 `[DEBUG-`，预筛与归一化同一份序列、两边不漏。
#   刻意伪装的形态（全角字母、花式 / 软连字符、U+2212）不查——按码点写映射表
#   堵不完十五万个码点，真要绕过的人 `--no-verify` 更省事；判据只有 `[DEBUG-`
#   一种写法，`[DEBUG中文-]` 判成残留是安全方向的误报。
# 豁免（**唯一的机制，文件级**）：文件第一行精确等于 `# gate-b: mentions-marker`
#   （ASCII、单一写法、行尾不许有多余空白）→ 该文件整体不报——机器不再猜
#   「这行是不是搜索命令」（旧的逐行状态机正是打补丁的主产区），由文件自己
#   声明「本文在谈论这个标记」。首行是 `#!` 的脚本看第二行：可执行脚本的
#   shebang 必须占第一行，不给这条路，这种脚本就只能把模式拼成伪装形态。
#   staged 模式从 `git show :<路径>` 读头两行（看的是索引内容），
#   工作区 / find 模式直接读文件；二进制后缀与 .md 早已不在扫描范围。
check_gate_b() {
    local staged="$1" root="$2" hits f first second
    # 预筛模式带间隙且不限长（12 字节间隙也要进候选）；判据在归一化之后，宽没有代价。
    local -a pat=(-i -E -e '\[.{0,}D.{0,}E.{0,}B.{0,}U.{0,}G')
    # 后缀只写一份：git pathspec 和 find 回退都从 bins 生成，两处各写必漂。
    local -a bins=(md png jpg jpeg gif ico webp pdf zip gz tar tgz bz2 xz zst 7z rar
                   whl iso jar war class pyc so dll exe bin o a lib obj wasm pdb
                   apk ipa nupkg deb rpm msi dmg xlsx docx pptx mp3 mp4 mov wav db sqlite)
    local -a skip=(
        ':(exclude,icase)*.md'
        ':(exclude)scripts/check-gates.sh' ':(exclude)scripts/check-gates.awk' ':(exclude)node_modules/*' ':(exclude)*/node_modules/*'
    )
    local e files excl
    for e in "${bins[@]}"; do skip+=(":(exclude,icase)*.$e"); done
    if [ "$staged" -eq 1 ]; then
        hits="$(git -C "$root" grep -a -i -n --cached "${pat[@]}" -- "${skip[@]}" 2>/dev/null || true)"
    elif git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        hits="$(git -C "$root" grep --untracked --exclude-standard -a -i -n "${pat[@]}" -- "${skip[@]}" 2>/dev/null || true)"
    else
        local -a fex=()
        for e in "${bins[@]}"; do fex+=(! -iname "*.$e"); done
        hits="$(find . -type f \
            ! -path './.git/*' ! -path '*/node_modules/*' \
            ! -path './scripts/check-gates.sh' ! -path './scripts/check-gates.awk' \
            "${fex[@]}" \
            -exec grep -H -a -i -n "${pat[@]}" {} + 2>/dev/null | sed 's|^\./||' || true)"
    fi
    [ -n "$hits" ] || return 0
    # 归一化三步：tab→空格、删控制字符、删所有非 ASCII 字节。输出**原始行**——
    # 整行归一化会把 `src/中文.js` 删成 `src/.js`。前缀取**第一个** `:数字:`
    # （非贪婪）：贪婪会把带时间戳的行连同前半行一起吞进「前缀」；tolower 对齐 -i。
    hits="$(printf '%s\n' "$hits" | LC_ALL=C awk '
        function norm(t) {
            gsub(/\011/, " ", t)
            gsub(/[\001-\037\177]/, "", t)
            gsub(/[\200-\377]/, "", t)
            return t
        }
        {
            if (!match($0, /:[0-9]+:/)) { print; next }
            s = norm(substr($0, RSTART + RLENGTH))
            if (tolower(s) ~ /\[debug[ \t]*-/) print
        }' 2>/dev/null || true)"
    [ -n "$hits" ] || return 0
    # 文件级豁免：违规行按文件去重，每个文件读头两行比对声明。
    files="$(printf '%s\n' "$hits" | LC_ALL=C awk '
        { if (match($0, /:[0-9]+:/)) print substr($0, 1, RSTART - 1) }' | sort -u)"
    excl="|"
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        first=""; second=""
        if [ "$staged" -eq 1 ]; then
            { IFS= read -r first; IFS= read -r second; } \
                < "$(git -C "$root" show ":$f" 2>/dev/null | feed)" || :
        elif [ -r "$root/$f" ]; then
            { IFS= read -r first; IFS= read -r second; } < "$root/$f" 2>/dev/null || :
        elif [ -r "$f" ]; then
            { IFS= read -r first; IFS= read -r second; } < "$f" 2>/dev/null || :
        fi
        # 行尾 CR 不算「多余空白」：MSYS 会替我们吞掉，Linux / macOS 不会，
        # 不剥的话同一份 CRLF 文件在两个平台上得到相反的结论。判定与平台无关。
        first="${first%$CR}"; second="${second%$CR}"
        # 声明在**第一行**；可执行脚本的 shebang 必须占第一行，所以首行是
        # `#!` 时看第二行——否则这种脚本没有任何诚实的出口（只能删掉，或者
        # 把模式拼成 `'[DEBU'"G-"` 那种伪装，这正是要消灭的写法）。
        if [ "$first" = "$GATE_B_DECL" ]; then
            excl="$excl$f|"
        else
            case "$first" in
                '#!'*) [ "$second" = "$GATE_B_DECL" ] && excl="$excl$f|" ;;
            esac
        fi
    done <<EOF
$files
EOF
    if [ "$excl" != "|" ]; then
        # 两端加 `|` 整段比对：`|a|` 不会误配 `|x/a|`。
        hits="$(printf '%s\n' "$hits" | EXEMPT="$excl" LC_ALL=C awk '
            { if (match($0, /:[0-9]+:/) && index(ENVIRON["EXEMPT"], "|" substr($0, 1, RSTART - 1) "|")) next
              print }')"
    fi
    if [ -n "$hits" ]; then
        printf '%s\n' "$hits" | while IFS= read -r line; do
            printf '  [x] 闸门 B: %s —— 调试标记残留\n' "$line"
        done
        violations=$((violations + $(printf '%s\n' "$hits" | wc -l)))
    fi
}

# 把 awk 的输出原样打印，并把行数计进 violations。
# 不用 wc：$() 会吃掉尾换行，「行数 = 换行数 + 1」容易写错；违规行本来就少，
# 循环数一遍最省事，也不起进程。
emit_violations() {
    [ -n "$1" ] || return 0
    printf '%s\n' "$1"
    # 数**非空行**。调用方攒出来的字符串常常以换行结尾（`out="$out$line\n"`），
    # `<<<` 又会补一个换行，于是末尾多出一条空行被算成 1 项违规——
    # 屏幕上显示 4 条，收尾却写「闸门检查失败：5 项」。
    local n=0 l
    while IFS= read -r l; do [ -n "$l" ] && n=$((n + 1)); done <<< "$1"
    violations=$((violations + n))
}

# $1 = 判定种类（plan / prd / journal / slice / review），$2 = 文件
run_check() { emit_violations "$(awk -v kind="$1" -v fpath="$2" -f "$AWK_PROG" "$2")"; }

check_plan()    { run_check plan    "$1"; }
check_prd()     { run_check prd     "$1"; }
check_journal() { run_check journal "$1"; }
check_slice()   { run_check slice   "$1"; }

# 文档里的相对引用必须指向真实存在的文件。
#
# 为什么要有这条：`templates/AGENTS.md` 曾经指向 `WORKFLOW.md`（那个文件不随模板
# 分发，生成出来的项目里根本没有），三个角色提示词指向 `architecture.md` 里不存在
# 的小节。这类断链只能靠人读到才发现，而这套规则的价值恰恰在于「换个人/AI 接手时
# 顺着指针能找到东西」。
#
# 只查**活文档**：根目录的 md、`docs/`、`skills/`、`tasks/README.md`。
# `tasks/<任务>/` 是快照（任务结束后可能改名、删文件，那里的断链是历史不是缺陷），
# `tasks/_template/` 是**填空模板**（里面的示例路径本来就指向还不存在的东西）——
# 这两类跳过。注意 `tasks/README.md` 是活文档，不跳过：
# 约定、归档流程、闸门说明都写在那里，它的断链和 `docs/` 里的一样有害。
#
# 只查**像文件**的引用（最后一段带扩展名）。纯目录引用（`src/`、`docs/adr/`）不查：
# 空目录进不了 git，模板里也用它们做示意。
check_links() {
    local staged_mode="${1:-0}"
    local f ref line n=0 out="" total=0 cand b
    local -a files=() all=()

    # 只查**活文档**：仓库根的 md、`docs/`、`skills/`、`tasks/README.md`。
    #
    # 为什么按位置划而不是「扫所有 md」：第三方代码目录（`vendor/`、依赖包里
    # 带的 README）是**别人的文档**，它们的相对链接在这个仓库里必然对不上。把
    # 它们算进来，唯一出路是加一份项目级忽略清单——那会变成永久豁免通道，
    # 而「文档放在哪儿」本来就是明确的，按位置划不需要任何例外。
    # 文件清单用 git 拿，**不用 `find`**：`find` 会扫进 `.gitignore` 里的东西
    # （venv/、node_modules/、构建产物、编辑器缓存），那些目录里成千上万个
    # 第三方 README 全是别人的相对链接，跟这个项目没关系。实测一个 Python 项目
    # 因此多出 313 条假违规。不在 git 仓库里时才退回 find。
    #
    # --staged 时 **cwd 已经是索引物化出来的临时树**，所以文件取自那里（要查的是
    # 「即将提交的内容」），而不是工作区。
    if [ "$staged_mode" -eq 1 ]; then
        while IFS= read -r f; do
            f="${f#./}"
            is_doc_path "$f" || continue
            files+=("$f")
        done < "$(find . -name '*.md' -type f 2>/dev/null | sort | feed)"
    elif git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        # `core.quotepath=false`：默认会把非 ASCII 文件名转义成 `"\344\273..."`，
        # 那样 awk 打不开这些文件、直接报错退出，后面的文件一个都不会被扫到
        # （表现为「明明是断链却全绿」）。
        while IFS= read -r f; do
            is_doc_path "$f" || continue
            files+=("$f")
        done < "$(git -C "$root" -c core.quotepath=false ls-files -co --exclude-standard -- '*.md' 2>/dev/null | sort | feed)"
    else
        while IFS= read -r f; do
            f="${f#./}"
            is_doc_path "$f" || continue
            files+=("$f")
        done < "$(find . -name '*.md' -type f 2>/dev/null | sort | feed)"
    fi
    total="${#files[@]}"
    [ "$total" -gt 0 ] || return 0

    # 后缀索引用的文件清单也是「存在的文件」，--staged 时取两边的并集：
    # 只取物化树会漏掉被引用的产物，只取工作区会漏掉「已暂存、工作区还没建」的新文件。
    if [ "$staged_mode" -eq 1 ]; then
        # 只认**索引物化树**里的文件。并进工作区的未跟踪文件会让「已经从索引里删掉、
        # 工作区还留着」的目标被判存在——提交进去的树里它已经没了，链接是死的。
        # 产物（被 .gitignore 命中的）另有精确存在性豁免，不靠这份清单。
        while IFS= read -r f; do [ -n "$f" ] && all+=("${f#./}"); done \
            < "$(find . -type f 2>/dev/null | sort | feed)"
    elif git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        while IFS= read -r f; do all+=("$f"); done \
            < "$(git -C "$root" -c core.quotepath=false ls-files -co --exclude-standard 2>/dev/null | feed)"
    else
        while IFS= read -r f; do all+=("${f#./}"); done \
            < "$(find . -type f -not -path './.git/*' 2>/dev/null | sort | feed)"
    fi

    # 后缀索引：文档里常写简称（`static/app.js` 而真实路径是 `web/static/app.js`）。
    # 未命中的引用再看有没有哪个已跟踪文件以 `/<ref>` 结尾。
    # 只用于**放行**，不用于报错——报错仍然要求精确匹配。
    #
    # 这段放在 awk 里而不是 bash：bash 的关联数组（`local -A`）是 4.0 才有的，
    # 而 macOS 自带的 `/bin/sh` 是 bash 3.2（Ubuntu 上是 dash），生成出来的项目要能在这两种
    # 环境里跑起来——用关联数组会让它在 macOS 上直接报错退出、在 dash 上根本解析不过。
    # awk 的数组在 3.2 与 5.x 上都一样，而且一次进程就够（按 ref 逐个起 grep 会慢一个量级）。
    local idx_tmp refs_tmp
    idx_tmp="$(mktemp "${TMPDIR:-/tmp}/gates-idx.XXXXXX")"
    refs_tmp="$(mktemp "${TMPDIR:-/tmp}/gates-refs.XXXXXX")"
    printf '%s\n' ${all[@]+"${all[@]}"} > "$idx_tmp" 2>/dev/null || true

    # 第一遍：只挑出「精确路径和产物回退都不成立」的引用，交给 awk 判后缀。
    # 大多数引用在 `[ -e ]` 这一步就放行了，所以这一步通常写出零行。
    while IFS=$'\t' read -r f ref; do
        [ -n "$ref" ] || continue
        [ -e "$ref" ] && continue
        # 存在性回**工作区**再判一次。文档引用的常常是**产物**（`reports/*.md`、
        # 截图、生成的 json），它们落在 .gitignore 里、索引物化树里永远没有。
        # 只看物化树的话，同一个文档全量自查通过、钩子报 4 条——每次提交都被拦。
        # 只有**被 .gitignore 命中的产物**才允许回工作区放行。否则「索引里已删、
        # 工作区还在」的目标会被判存在——提交进去的树里它已经没了，链接是死的。
        if [ -n "${root_pwd:-}" ] && [ -e "$root_pwd/$ref" ] \
           && git -C "$root" check-ignore -q -- "$ref" 2>/dev/null; then
            continue
        fi
        printf '%s\t%s\n' "$f" "$ref"
    # LC_ALL=C：百分号解码用 `sprintf("%c", 0xE6)` 生成**字节**，在 UTF-8 locale 下
    # gawk 会把它编码成 U+00E6（`æ`），中文路径就再也对不上了。C locale 下按字节输出。
    done < "$(LC_ALL=C awk -v kind=links -f "$AWK_PROG" "${files[@]}" 2>/dev/null | sort -u | feed)" > "$refs_tmp"

    out="$(awk -F'\t' -v idx="$idx_tmp" '
        BEGIN {
            while ((getline l < idx) > 0) {
                if (l == "") continue
                b = l; sub(/.*\//, "", b)
                map[b] = (b in map) ? map[b] "\n" l : l
            }
        }
        {
            f = $1; ref = $2
            b = ref; sub(/.*\//, "", b)
            if (b in map) {
                nn = split(map[b], cand, "\n")
                for (i = 1; i <= nn; i++) {
                    c = cand[i]
                    if (c == ref) next
                    if (length(c) > length(ref) && substr(c, length(c) - length(ref)) == "/" ref) next
                }
            }
            printf "  [x] %s: 引用的 %s 不存在\n", f, ref
        }' "$refs_tmp")"
    if [ -n "$out" ]; then
        while IFS= read -r line; do [ -n "$line" ] && n=$((n + 1)); done <<< "$out"
    fi
    rm -f "$idx_tmp" "$refs_tmp"

    [ "$n" -gt 0 ] && printf '检查文档内的相对引用（%d 个文件）\n' "$total"
    emit_violations "$out"
}

# ADR 的引用与取代关系。见 check-gates.awk 的 adr_check。
check_adr() {
    local -a adrs=()
    local p
    for p in docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$p" ] && adrs+=("$p")
    done
    [ "${#adrs[@]}" -gt 0 ] || return 0
    emit_violations "$(awk -v kind=adr -f "$AWK_PROG" "${adrs[@]}" 2>/dev/null)"
}

# 代码里的决策锚点：`# 决策: ADR-0003`（`//` 同理）。
#
# 只做**提示**（note，不影响退出码），因为它三条判据的价值不对称：
# 「悬空锚点」该修；「这条 ADR 没有代码引用」不该报（「用 SQLite」这类决定本来
# 就不落在某一行代码上）；「锚点格式不对」也可能只是注释里的自然行文。
# 加进失败会让全量自查常年红，而常年红的结果就是没人再看它。
#
# 为什么值得有：`docs/architecture.md` 讲的是模块级，「这行为什么这么写」在代码里
# 没有出口。注释指向 ADR 是唯一的低成本路径，而注释最容易在重构中变成死链。
check_doc_counts() {
    local staged_mode="${1:-0}" f ln
    local -a files=()

    # 判据：**同一行**里既有 `fixtures/<名字>.sh` 又有 `N 项`。这是「把会漂的
    # 数字写进文档」的唯一常见形态（`bash scripts/fixtures/gate-test.sh  # 187 项`）。
    #
    # 为什么不拿真实项数比对：真实项数只有跑完 fixture 才知道（十几分钟），钩子
    # 里不可能跑。也不需要——**唯一不需要维护的形态是文档里不出现这个数字**。
    # 所以这条守的是「别写回去」，不是「写得对不对」。
    if [ "$staged_mode" -eq 1 ]; then
        # cwd 已是索引物化树
        while IFS= read -r f; do
            f="${f#./}"
            is_doc_path "$f" && files+=("$f")
        done < "$(find . -name '*.md' -type f 2>/dev/null | sort | feed)"
    elif git -C . rev-parse --git-dir >/dev/null 2>&1; then
        while IFS= read -r f; do
            is_doc_path "$f" && files+=("$f")
        done < "$(git -c core.quotepath=false ls-files -co --exclude-standard -- '*.md' 2>/dev/null | sort | feed)"
    else
        while IFS= read -r f; do
            f="${f#./}"
            is_doc_path "$f" && files+=("$f")
        done < "$(find . -name '*.md' -type f 2>/dev/null | sort | feed)"
    fi
    [ "${#files[@]}" -gt 0 ] || return 0

    # awk 一次扫完：文档是 UTF-8，但只匹配 ASCII 模式，C locale 下也是字节安全。
    while IFS= read -r ln; do
        [ -n "$ln" ] || continue
        fail "活文档里写死了 fixture 的断言项数（每加一条断言就漂一次）：$ln —— 改成时长或覆盖范围，真实数字看 fixture 收尾输出"
    done < "$(LC_ALL=C awk '
        /fixtures\/[A-Za-z0-9_.-]+\.sh/ && /[0-9]+[ \t]*项/ { print FILENAME ":" FNR ": " $0 }
    ' "${files[@]}" 2>/dev/null | feed || true)"
}

check_anchors() {
    local staged="$1" root="$2" hits=""
    local -a adrs=()
    local p id line rest num found
    for p in "$root"/docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$p" ] || continue
        id="${p##*/}"; adrs+=("${id:0:4}")
    done

    if [ "$staged" -eq 1 ]; then
        hits="$(git -C "$root" grep -I -n --cached -e '决策:' -- \
            ':(exclude)*.md' ':(exclude)*check-gates.sh' \
            ':(exclude)node_modules/*' ':(exclude)*/node_modules/*' 2>/dev/null || true)"
    elif git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
        hits="$(git -C "$root" grep --untracked --exclude-standard -I -n -e '决策:' -- \
            ':(exclude)*.md' ':(exclude)*check-gates.sh' \
            ':(exclude)node_modules/*' ':(exclude)*/node_modules/*' 2>/dev/null || true)"
    else
        hits="$( cd "$root" && find . -type f \
            ! -path './.git/*' ! -path '*/node_modules/*' \
            ! -name '*.md' ! -name 'check-gates.sh' \
            -exec grep -H -I -n '决策:' {} + 2>/dev/null | sed 's|^\./||' || true)"
    fi
    [ -n "$hits" ] || return 0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            *ADR-*) ;;
            *) note "锚点没写目标（应写成「决策: ADR-0001」）：$line"; continue ;;
        esac
        # 取 ADR- 之后的**前导数字**。不用 `substr`/`${v:0:4}`：
        # C locale 下那是按字节切，中文会被切坏（见 check-gates.awk 里同一类坑）。
        rest="${line#*ADR-}"
        num="${rest%%[!0-9]*}"
        case "$num" in
            [0-9][0-9][0-9][0-9]) ;;
            *) note "锚点的 ADR 编号不是 4 位数字：$line"; continue ;;
        esac
        if [ "${#adrs[@]}" -eq 0 ]; then
            note "锚点指向 ADR-$num，但 docs/adr/ 里还没有任何 ADR：$line"
            continue
        fi
        found=0
        for id in "${adrs[@]}"; do
            [ "$id" = "$num" ] && { found=1; break; }
        done
        [ "$found" -eq 1 ] || note "锚点指向 ADR-$num，但 docs/adr/ 里没有这个文件：$line"
    done <<< "$hits"
    return 0
}

# 任务是否已经「开工」——决定 T2/T3 的裁决单要不要。
# 判据是「任务目录里除了 prd.md / journal.md / review.md 还有没有别的文件」，
# 而不是「有没有 plan.md 或 NN-*.md」：后者能被改名绕过去（切片叫 `01_a.md`、
# 或把档位只写在 prd 里再补一份 DONE 的 journal，就整条免检了）。
# journal 宣告 DONE 也算开工——任务都收尾了，不能再拿「还没写计划」当挡箭牌。
task_has_started() {
    local d="$1" p st
    # 目录里除了这三份「任何任务都可能有的」文件之外还有别的东西 → 已经开工。
    # 文件、目录、非 .md 都算：`handoff.md` 和 `research/` 同样说明这个任务在推进。
    for p in "$d"/*; do
        [ -e "$p" ] || continue
        # plan.md 也算「规划产物」：计划落盘（3.5）之后才派执行者（3.5b）、
        # 才有代码，审查（3.8）在代码之后。把 plan.md 当成「已开工」会让
        # 「先提交计划、再提交代码」这条正常路径直接卡死——而卡死的结果不是补审查，
        # 是有人不提交计划，检查反而更弱。
        case "${p##*/}" in prd.md|plan.md|journal.md|review.md) ;; *) return 0 ;; esac
    done
    # 裁决单本身在（哪怕还空着）也算开工：它出现就说明任务已经走到 3.8 了。
    # 少了这一条，`prd + journal(状态空) + 空 review.md` 会因为「没开工」跳过
    # 整份裁决单检查——空裁决单直接放行。
    [ -f "$d/review.md" ] && return 0
    # journal 记了结束状态 → 任务至少跑到收尾了。任何非空状态都算，
    # 不能只认 DONE：`DONE_WITH_CONCERNS` / `BLOCKED` 同样是「跑过了」。
    [ -f "$d/journal.md" ] || return 1
    # 状态只认 gate 头块里的一行（整行精确匹配；四种结束状态是封闭集合），
    # 所以先把范围收在「第一行到第一个 `-->`」之间：正文里写 `status: DONE`
    # 不算开工依据。头块没闭合时 sed 读到 EOF —— 那种文件本来就判红。
    st="$(tr -d '\r' < "$d/journal.md" 2>/dev/null |
          sed -n '1,/^-->$/p' |
          grep -E '^status: (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT)$')"
    [ -n "$st" ]
}

# review.md（裁决单）：只有 T2 / T3 需要。
# 「文件在不在」的判断留在 bash —— 文件都不在的时候，awk 没机会开口。
check_review() {
    local d="$1" f="$d/review.md"
    # 还没开工的任务（3.2 落 prd、3.3 定档位与计划、3.8 出裁决单）不要求裁决单，
    # 否则 T2/T3 任务连「先把 prd 提交一次」都做不到。
    # 裁决单**被删掉**同样要拦：task_has_started 看的是「目录里还有什么」，
    # 一个只剩 plan.md 的 T2 目录会被判成「还没开工」，于是整份 review 检查被跳过。
    # 实测 `git rm review.md` 后提交代码能过。
    if git -C "$root" cat-file -e "HEAD:$f" 2>/dev/null &&
       ! git -C "$root" cat-file -e ":$f" 2>/dev/null; then
        fail "$f: 这份裁决单在 HEAD 里有、这次提交里没了 —— T2/T3 的审查记录不能删（要作废请写进 journal.md 并说明原因）"
        return
    fi
    task_has_started "$d" || return 0
    if [ ! -f "$f" ]; then
        fail "$f: 这个任务的档位是 T2/T3，但缺 review.md（这两档的审查必须由独立子 agent 做，见 docs/agents/任务分级.md）"
        return
    fi
    run_check review "$f"
}

# 本次提交的代码文件，是否属于某个「声明了 T2/T3 但还没裁决单」的在飞任务。
# 只认 plan.md 的「相关文件」——那是唯一把文件和任务连起来的机器可读字段。
check_review_by_scope() {
    local root="$1" d f rel hit t high review_ok
    local -a changed=() dirs=()

    # 不限于 MODULE_ROOT：计划里写 `scripts/deploy.sh`、`app/main.py` 的任务同样要有
    # 裁决单。任务目录自己的改动排除在外（那是计划/日志，不是被审的代码）。
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in tasks/*) continue ;; esac
        changed+=("$f")
    done < "$(git -C "$root" -c core.quotepath=false diff --cached --name-only --diff-filter=ACMRD 2>/dev/null | feed)"
    [ "${#changed[@]}" -gt 0 ] || return 0

    # 候选任务取 **HEAD ∪ 索引 ∪ 工作区** 的并集。
    # 只看索引物化树的话：计划不暂存、被 `git rm --cached`、被 skip-worktree、
    # 或者本次提交里顺手归档，任务就从视野里消失，它范围内的代码可以免审进主干
    # （四条都实跑过）。任务一旦声明过 T2/T3，就别想靠「这次没带上它」躲开审查。
    # 注意 `find "$root/tasks"`：这时 cwd 已经是索引物化树，写 `find tasks` 扫的是
    # 临时树而不是工作区——「计划写在磁盘上但忘了 git add」正是这条检查要抓的情形。
    # 三处来源会有重复，下面按已见过的目录名去重（否则同一条违规打印两三次）。
    local seen=" "
    while IFS= read -r f; do
        f="${f#./}"
        case "$f" in tasks/*/plan.md) ;; *) continue ;; esac
        d="${f%/plan.md}"
        case "$seen" in *" $d "*) continue ;; esac
        seen="$seen$d "
        dirs+=("$d")
    done < "$({ git -C "$root" -c core.quotepath=false ls-tree -r --name-only HEAD 2>/dev/null;
             git -C "$root" -c core.quotepath=false ls-files 2>/dev/null;
             find "$root/tasks" -mindepth 2 -maxdepth 2 -name plan.md 2>/dev/null | sed "s|^${root%/}/||"; } | feed)"

    for d in ${dirs[@]+"${dirs[@]}"}; do
        case "$d" in tasks/_template|tasks/_archive/*|tasks/_template/*) continue ;; esac

        # tier 与「相关文件」对**三个版本各判一次，再取并集**。
        # 「先选一个版本」是不行的：HEAD 里是 T2、索引里改成 T1（或把文件列表删空），
        # 单版本判定就只看索引那份，等于把高档声明洗掉。实测两条都能过。
        local -a versions=()
        local v
        for v in ":""$d/plan.md" "HEAD:""$d/plan.md" ; do
            t="$(git -C "$root" cat-file blob "$v" 2>/dev/null)"
            [ -n "$t" ] && versions+=("$t")
        done
        [ -f "$root/$d/plan.md" ] && versions+=("$(cat "$root/$d/plan.md" 2>/dev/null)")
        [ "${#versions[@]}" -gt 0 ] || continue

        # 档位来源要与 task_is_high_tier 一致：plan、prd、切片里**任何一处**声明了
        # T2/T3 就算高档。只看 plan 的话，「prd 写 T2、plan 写 T1」能绕过归属检查。
        high=0
        for v in "${versions[@]}"; do
            if printf '%s\n' "$v" | gate_tier_high; then
                high=1; break
            fi
        done
        if [ "$high" -eq 0 ]; then
            # 档位来源只有三类：plan.md、prd.md、切片（NN-*.md）——与 task_is_high_tier 同一张
            # 名单。把目录里所有 .md 都读会让 journal 里的一行 `tier: T2` 触发审查，
            # 而文档从没把 journal 当档位来源。
            # 每个文件同样读三版本：只读工作区的话，HEAD 里的 T2 被改成 T1 或直接删掉
            # 就能绕开归属检查（实测两条都能过）。
            local tf
            while IFS= read -r tf; do
                [ -n "$tf" ] || continue
                case "$tf" in
                    "$d/plan.md") continue ;;
                    "$d/prd.md"|"$d"/[0-9][0-9][-_]*.md|"$d"/[0-9][-_]*.md) ;;
                    *) continue ;;
                esac
                if [ "$(plan_versions_tier "$root" "$tf")" = "yes" ]; then
                    high=1; break
                fi
            done < "$({ git -C "$root" -c core.quotepath=false ls-files -- "$d" 2>/dev/null;
                     git -C "$root" -c core.quotepath=false ls-tree -r --name-only HEAD -- "$d" 2>/dev/null;
                     find "$root/$d" -maxdepth 1 -name '*.md' 2>/dev/null | sed "s|^${root%/}/||"; } | feed)"
        fi
        [ "$high" -eq 1 ] || continue

        # 非空裁决单：三个版本任一处有内容就算有（0 字节不算）
        review_ok=0
        for f in "$d/review.md"; do
            # 「非空」= 有非空白内容。只有空格/换行的裁决单顶不了一次审查。
            # 只认**索引或 HEAD**：一份未跟踪的本地 review.md 不算——那样代码进主干，
            # 审查记录却留在某人的工作区里，主干上永远没有这次审查。
            if git -C "$root" cat-file blob ":$f" 2>/dev/null | grep -q '[^[:space:]]'; then review_ok=1; fi
            if git -C "$root" cat-file blob "HEAD:$f" 2>/dev/null | grep -q '[^[:space:]]'; then review_ok=1; fi
        done
        [ "$review_ok" -eq 1 ] && continue

        # 相关文件同样取三版并集
        local -a rels=()
        for v in "${versions[@]}"; do
            while IFS= read -r rel; do
                [ -n "$rel" ] && rels+=("$rel")
            done < "$(printf '%s\n' "$v" | awk -v kind=related -f "$AWK_PROG" - 2>/dev/null | feed)"
        done
        [ "${#rels[@]}" -gt 0 ] || continue
        hit=""
        for f in "${changed[@]}"; do
            for rel in "${rels[@]}"; do
                rel="${rel%/}"
                case "$rel" in
                    # glob 当通配符展开等于让人用 `src/*` 声明一切——但它也没法用作
                    # 归属判据（`case` 里会被当模式）。直接跳过。
                    *'*'*|*'?'*|*'['*) continue ;;
                esac
                case "$f" in
                    "$rel"|"$rel"/*) hit="$f"; break ;;
                esac
            done
            [ -n "$hit" ] && break
        done
        [ -n "$hit" ] || continue
        fail "$d: 本次提交的 $hit 写在这个任务的「相关文件」里，而它是 T2/T3 且还没有非空的 review.md —— 独立审查要在代码进主干之前做完（3.8）。如果这些改动不属于这个任务，把它们拆到自己的提交里（先出裁决单再提交代码，或把计划里的文件范围写准）"
    done
}

# gate 头块里的档位是否是 T2/T3。头块必须在文件第一行、键只有一种写法，
# 所以一条整行精确匹配就够——散文里写「档位: T3」不会再被当成声明。
# 行尾 CR 先删掉：MSYS 的 grep 在文本模式下会吞，Linux / macOS 不会。
# 参数：文件名（可多个）；不带参数时读 stdin。
gate_tier_high() {
    if [ "$#" -gt 0 ]; then
        cat "$@" 2>/dev/null | tr -d '\r' | grep -qx 'tier: T[23]'
    else
        tr -d '\r' | grep -qx 'tier: T[23]'
    fi
}

# 一个文件（相对仓库根）在「索引 / HEAD / 工作区」三个版本里，任一版本的头块声明了
# T2/T3 就返回 yes。用于 prd.md 与切片——它们和 plan.md 一样是档位来源，
# 单版本判定会给「HEAD 写 T2、工作区改 T1」留下后门。
plan_versions_tier() {
    local root="$1" f="$2" v
    for v in ":$f" "HEAD:$f"; do
        if git -C "$root" cat-file blob "$v" 2>/dev/null | gate_tier_high; then
            printf 'yes'; return 0
        fi
    done
    if [ -f "$root/$f" ] && gate_tier_high "$root/$f"; then
        printf 'yes'; return 0
    fi
    printf 'no'
}

# 任务档位是否落在 T2/T3：plan.md / prd.md / 切片里任何一处头块声明了 T2/T3 就算。
# 不能只看 plan.md——档位也可能只写在 prd.md 或切片里；
# prd.md 的 tier 也是同一个键，只写在那里时同样得认。
task_is_high_tier() {
    local d="$1" f
    local files=()
    for f in "$d/plan.md" "$d/prd.md" "$d"/[0-9][-_]*.md "$d"/[0-9][0-9][-_]*.md; do
        [ -f "$f" ] && files+=("$f")
    done
    [ "${#files[@]}" -gt 0 ] || return 1
    gate_tier_high "${files[@]}"
}

# 规模底线：声明的档位不能低于**数得出来**的改动量。
#
# 只查低报，不查高报：高报只是多一次审查，低报是拿「小改动」换免打扰——而 T0 / T1
# 的档位声明不再等人确认之后，低报就是「没人看」的唯一入口。
#
# 6 条信号里能机械化的只有文件数这一条：跨模块 / 动公开接口 / 行为变化 / 不可逆性
# 没有判据，仍然靠人看 diff。只数 $MODULE_ROOT 下的文件——量的是「改了多少代码」，
# 文档、tasks/ 不算。阈值对齐 docs/agents/任务分级.md 的 6 条信号表：文件数 ≥ 4 → T2 起。
#
# 只在 --staged 跑：全量自查没有「这次提交」这个基准。$3… = 本次改动涉及的任务目录。

# 数 $MODULE_ROOT 下从 $1（可为空 = 只看索引）到索引的改动文件数。
# -M：重命名算一次（和 `git diff --stat` 的文件数口径一致）；不认的话一次
# src/a → src/b 会被数成 2 个文件，小改动被误判成 T2。
count_code_changes() {
    local from="$1" root="$2" n=0 p range=()
    [ -n "$from" ] && range=("$from")
    while IFS= read -r p; do
        case "$p" in "${MODULE_ROOT%/}"/*) ;; *) continue ;; esac
        # 只数**代码**。模块根下也可能放文档、图片、快照；把它们算进「改了 4 个文件
        # 就是 T2」，会让「补 4 篇文档」被当成大改动。用法注释写的就是「文档不计」。
        case "${p##*.}" in
            md|markdown|txt|rst|png|jpg|jpeg|gif|svg|webp|ico|pdf|csv|json|yml|yaml) continue ;;
        esac
        n=$((n + 1))
    done < "$(git -c core.quotepath=false -C "$root" diff --cached --name-only -M \
             --diff-filter=ACMRD ${range[@]+"${range[@]}"} -- "${MODULE_ROOT%/}" 2>/dev/null | feed)"
    printf '%s' "$n"
}

check_scale() {
    local staged="$1" root="$2"; shift 2
    [ "$staged" -eq 1 ] || return 0
    # 索引里没有代码改动 ⇒ 没有「这次提交」可判。
    # 不短路的话，下面按任务累计的分支算的是 base→索引；索引等于 HEAD 时
    # 那就是「该任务开始以来的全部改动」，历史 T0/T1 任务一律 ≥4 ⇒ 空跑必红。
    git -C "$root" diff --cached --quiet -- "${MODULE_ROOT%/}" 2>/dev/null && return 0
    local d base n max=0 max_dir="" who
    # 空树的 SHA：任务起点那个提交本身就是根提交时，`base^` 不存在，
    # 从空树算起才等同于「这个任务从零开始」。
    local empty_tree=4b825dc642cb6eb9a060e54bf8d69288fbee4904
    local cands=("$@")
    # 声明了 T2/T3 就免检——但**只有真写了计划的任务**才算数。
    # 否则 prd 里写一行 `T2`、再放一份空 journal，同一次提交 6 个 src 文件就全绿：
    # 没有 plan.md 就没有 3.4 的批准，也没有可审的对象，这个豁免没有任何依据。
    for d in ${cands[@]+"${cands[@]}"}; do
        if task_is_high_tier "$d"; then
            if [ -f "$d/plan.md" ]; then
                return 0
            fi
            fail "$d: 声明了 T2/T3，但没有 plan.md —— 没有计划就没有批准，也没有可审的对象。把计划落盘（3.3 / 3.5），或者这些改动不属于这个任务"
            return 0   # 已经报过，别再叠一条规模违规
        fi
    done
    if [ "${#cands[@]}" -eq 0 ]; then
        # 这次提交没碰任何任务目录——最常见的是「计划先提交、代码后提交」。
        # 这时不能只看本次索引：把 T2 的活拆成两次提交就能溜过去。
        # 但也不能退回「所有在飞任务」然后见到 T2 就让位——那样仓库里躺着一个
        # 没归档的 T2 任务，规模底线就永久失效。只累计**声明为 T0/T1** 的任务。
        #
        # 起点是「本次索引自己的改动数」：仓库里只有 T2/T3 在飞时（T0 不建目录，
        # 所以这是常态），没有任何 T0/T1 任务可以归属，这几处改动仍然要有人认领。
        max="$(count_code_changes "" "$root")"
        for d in "$root"/tasks/*/; do
            d="${d%/}"; d="${d#"$root"/}"
            # 模板目录不是任务：它的 plan.md 头块里 `tier:` 是空的，不算 T2/T3，
            # 而它的起点是脚手架落地那次提交——于是「累计」把项目至今的全部
            # src 改动都算进一个假任务里，任何只改代码的提交都被拦。
            case "$d" in tasks/_template) continue ;; esac
            [ -f "$root/$d/plan.md" ] || continue
            task_is_high_tier "$d" && continue
            base="$(git -C "$root" log --diff-filter=A --format=%H -1 -- "$d/plan.md" 2>/dev/null)"
            [ -n "$base" ] || continue
            base="$(git -C "$root" rev-parse -q --verify "$base^" 2>/dev/null || printf '%s' "$empty_tree")"
            n="$(count_code_changes "$base" "$root")"
            if [ "$n" -gt "$max" ]; then max="$n"; max_dir="$d"; fi
        done
        n="$max"
    else
        # 按**任务**累计，不按单次提交：从 plan.md 进入历史的那次提交之前算起。
        # 只量本次 diff 的话，把 T2 的活拆成两次提交就能溜过去——而「一个任务
        # 对应一个主要提交」本来就是 tasks/README.md 的约定。
        for d in ${cands[@]+"${cands[@]}"}; do
            base="$(git -C "$root" log --diff-filter=A --format=%H -1 -- "$d/plan.md" 2>/dev/null)"
            if [ -n "$base" ]; then
                base="$(git -C "$root" rev-parse -q --verify "$base^" 2>/dev/null || printf '%s' "$empty_tree")"
            fi
            n="$(count_code_changes "$base" "$root")"
            if [ "$n" -gt "$max" ]; then max="$n"; max_dir="$d"; fi
        done
        n="$max"
    fi
    [ "$n" -ge 4 ] || return 0
    # 报出是哪个任务超的：仓库里几十个 T0/T1 任务时，只说「这个任务」等于让人手算。
    # 没有可归属的任务（改动全在本次索引里）时主语换成「本次改动」，别再拼出
    # 「任务 （本次改动） 的…」这种半句话。
    if [ -n "$max_dir" ]; then
        who="任务 $max_dir"
    else
        who="本次改动"
    fi
    fail "$who 的代码改动累计 $n 个 $MODULE_ROOT 下的文件，但没有声明 T2/T3 —— 按 docs/agents/任务分级.md 的 6 条信号，文件数 ≥ 4 就是 T2。把 plan.md 头块的 tier 改成 \`tier: T2\` 并补 review.md（3.4 批准 + 3.8 独立审查）；如果这些文件分属别的任务，说明这个提交混了多个任务，按「一个任务一个提交」拆开"
}

# ---------------------------------------------------------------- 架构

# 模块根：这个目录的直接子目录就是模块。项目布局不同时改这里，
# 或用环境变量覆盖：MODULE_ROOT=app bash scripts/check-gates.sh
MODULE_ROOT="${MODULE_ROOT:-src}"

# `## 模块划分` 表第 2 列声明的路径，去掉反引号与尾斜杠。
# 表本身的解析在 check-gates.awk 的 kind=modules 里——和逐文件检查共用同一套
# 注释剥离，省得两处对「注释算不算内容」有不同看法。
declared_module_paths() {
    awk -v kind=modules -f "$AWK_PROG" "$1" | sort -u
}

# 目录与路径的**存在性**以工作区为准，不取索引：索引里没有「空目录」这个概念，
# 而 src/ 恰恰是空的 —— 只看索引会在首次提交时误报「src 不存在」。
# 表的内容取索引版本（见 check_architecture）。
# 模块根下的子目录。在**哪棵树**里找，由调用方决定：全量模式 cd 在仓库里，
# 暂存模式 cd 在索引物化出的临时树里 —— 各自看各自该看的那份内容。
# 只算**非空**目录：
#   - 空目录 git 根本不跟踪，声明它会被规则 1 判「声明了却不存在」，
#     不声明又违反规则 2 —— 两头堵死。它本来也不是模块。
# 点目录和被 .gitignore 命中的不算：src/.cache 既进不了提交，也不该进模块表。
arch_module_dirs() {
    local staged="$1" root="$2" d files
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        case "${d##*/}" in .*) continue ;; esac        # 点目录不是模块
        # 只算「clone 之后还会在」的目录：里面有 git 跟踪的、或者会被跟踪的
        # （未跟踪且没被 .gitignore 命中）文件。三类目录不算，它们声明不了：
        #   - 空目录：git 不跟踪空目录
        #   - 只装着被 ignore 的文件的目录（`src/logs/` 下只有 *.log）
        #   - 只含空子目录的目录
        # 声明它们会在 clone 里变成「声明了却不存在」，不声明又违反规则 2，两头堵死。
        # 目录列表来自 cwd（暂存模式是索引物化出的临时树），但「有没有内容」必须问
        # 真正的仓库：临时树不是 git 仓库，在那儿跑 git 会失败并静默返回空。
        if [ "$staged" -eq 1 ]; then
            files="$(git -C "$root" -c core.quotepath=false ls-files -c -- "$d" 2>/dev/null | head -n 1)"
        else
            files="$(git -C "$root" -c core.quotepath=false ls-files -co --exclude-standard -- "$d" 2>/dev/null | head -n 1)"
        fi
        [ -n "$files" ] && printf '%s\n' "$d"
    done < "$({
        [ -d "$MODULE_ROOT" ] || exit 0
        find "$MODULE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -u
    } | feed)"
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
        # 暂存模式下 cwd 是索引物化出的整棵树。
        # 只看**这次提交里**的架构表。以前在「索引和 HEAD 都没有」时会拷一份工作区版本
        # 进物化树，那会造成双向失真：提交里其实没有这个文件，闸门却按工作区那份放行
        # （`git rm --cached` 后提交能过、断链进主干）；而同一个文件又会让 check_links
        # 把「提交里不存在」的路径当成存在。索引里没有就是没有，直接报「不存在」。
        doc="$check_tree_tmp/docs/architecture.md"
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

    # 模块根不存在 ⇒ 架构比对和规模底线都在空转，「闸门通过」是假的。
    # 不能 fail：`src/` 是空目录，git 不跟踪空目录，刚 clone 的仓库里它就不在。
    # 但必须说出来 —— 代码不在 src/ 的项目（`uv init`、`create-next-app` 的 app/）
    # 会得到一个全绿的闸门，而什么都没查。
    if [ ! -d "$root/$MODULE_ROOT" ]; then
        note "模块根 \`$MODULE_ROOT\` 不存在：模块表比对与规模底线都不生效。代码不在这个目录时，用 \`MODULE_ROOT=<真实目录> bash scripts/check-gates.sh\`，或改脚本里 MODULE_ROOT 的默认值。"
    fi

    # 路径归一化：`./src/a`、`.\src\a`、`src//a`、`src/a/` 都是同一个目录。
    # 不归一的话，表里换一种合法写法就会被判成「表里没有它」——规则 1 用 -e 认它，
    # 规则 2 用字符串比却不认，同一份表出现两种结论。
    # Windows（MSYS/Cygwin）的文件系统大小写不敏感，`src/Auth` 与 `src/auth` 是同一
    # 个目录，比较时折成小写；Linux/macOS 上大小写不同就是两个目录，不能折。
    local fold=0
    case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) fold=1 ;; esac
    norm_path() {
        local v="$1"
        v="${v//\\//}"                       # 反斜杠 → 斜杠
        while [ "${v#./}" != "$v" ]; do v="${v#./}"; done
        # 连续斜杠压成一个。注意是压成 `/`，不是删掉——删掉会把 `src//a` 变成
        # `srca`，成了另一个路径（这条曾经是真实 bug）。
        v="$(printf '%s' "$v" | sed 's|//*|/|g')"
        # 中间的 `./` 段（`src/./a`）
        v="$(printf '%s' "$v" | sed 's|/\./|/|g')"
        v="${v%/}"
        [ "$fold" -eq 1 ] && v="$(printf '%s' "$v" | tr 'A-Z' 'a-z')"
        printf '%s' "$v"
    }
    local -a decl_norm=()
    local pn
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        pn="$(norm_path "$p")"
        [ -n "$pn" ] || continue
        decl_norm+=("$pn")
    done <<< "$declared"

    # 规则 1：声明的路径必须真实存在。
    # 例外：模块根本身（及它的祖先）不查 —— `src/` 是空目录，git 不跟踪空目录，
    # clone 之后它就不在了，而 Phase 2 的模块表正要求写宽路径 `src`。
    # 这条要是报错，新 clone 的仓库会卡到「所有提交都过不去」。
    local mr_norm
    mr_norm="$(norm_path "$MODULE_ROOT")"
    for p in ${decl_norm[@]+"${decl_norm[@]}"}; do
        [ -n "$p" ] || continue
        case "$mr_norm/" in "$p/"*) continue ;; esac
        arch_path_exists "$root" "$p" \
            || fail "docs/architecture.md 声明了模块「$p」，但它不存在"
    done

    # 规则 2：$MODULE_ROOT 下的直接子目录必须被某个声明覆盖
    local d covered q dn
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        covered=0
        dn="$(norm_path "$d")"
        for q in ${decl_norm[@]+"${decl_norm[@]}"}; do
            case "$q/" in "$dn/"*) covered=1; break ;; esac
            case "$dn/" in "$q/"*) covered=1; break ;; esac
        done
        [ "$covered" -eq 1 ] \
            || fail "「$d」是 $MODULE_ROOT 下的模块目录，但 docs/architecture.md 的模块表里没有它"
    done < "$(arch_module_dirs "$staged" "$root" | feed)"

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

# 校验「临时树里的内容 == 索引 blob」。不一致就返回 1（调用方中止）。
# 用 `git hash-object --path=…` 而不是直接比字节：它走 clean 过滤器，与 git 建
# 索引时的口径一致（core.autocrlf=true 的仓库里，物化出来的 CRLF 文件哈希仍等于
# LF blob）。这既能容忍换行归一，又能抓出 smudge 造假。
verify_materialized() {
    local root="$1" tree="$2" mode sha path gitdir
    local -a paths=() shas=()
    local -a missing=() present=() present_sha=()
    local line

    # 用 `-z` 读：没有它，含空格/引号/换行的路径会被 C-quote 成 `"a b"` 这类字符串，
    # 在物化树里当然找不到，于是每次 --staged 都 exit 2（POSIX 上合法文件名）。
    while IFS= read -r -d '' line; do
        [ -n "$line" ] || continue
        # 格式是 `<mode> <sha> <stage>\t<path>`：**三段空格 + 一个制表符**。
        mode="${line%% *}"
        line="${line#* }"; sha="${line%% *}"
        path="${line#*$'\t'}"
        [ "$path" != "$line" ] || continue            # 没有制表符：不是标准 ls-files -s 行
        case "$mode" in
            160000) continue ;;                        # 子模块：没有 blob 可比
            120000) continue ;;                        # 符号链接：内容不在文件里，-f 判不了
        esac
        paths+=("$path"); shas+=("$sha")
    done < "$(git -C "$root" ls-files -s -z 2>/dev/null | feed)"

    local i n="${#paths[@]}"
    [ "$n" -gt 0 ] || return 0

    # (1) 存在性：checkout-index 会跳过 skip-worktree（稀疏检出正是靠这个位），
    # 被跳过的 plan.md / 任务目录会从视野里整个消失，而提交照进。
    for ((i = 0; i < n; i++)); do
        case "${paths[i]}" in
            # `hash-object --stdin-paths` 按**行**读输入：含换行的合法 POSIX 文件名
            # 会被拆成两行，数量对不上就整次中止。这种文件极罕见，跳过并留提示。
            *'
'*) note "路径含换行，跳过内容核对：${paths[i]}"; continue ;;
        esac
        if [ -f "$tree/${paths[i]}" ]; then
            present+=("${paths[i]}"); present_sha+=("${shas[i]}")
        else
            missing+=("${paths[i]}")
        fi
    done

    # (2) 内容：**必须**核对。checkout-index 会套 smudge 过滤器（实测：索引 blob 是
    # `AAA`，物化出来可以是 `BBB`），于是检查器看到的是被洗白的 plan / review /
    # architecture，而提交进去的是另一份。一次批量 `hash-object` 就够——逐个文件起
    # 进程的做法在 Windows 上是 3 秒/文件，批量是 0.1 秒/30 文件。
    local -a forged=()
    if [ "${#present[@]}" -gt 0 ]; then
        gitdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)"
        if [ -z "$gitdir" ]; then
            # Git < 2.13 没有 --absolute-git-dir（Ubuntu 16.04 的 2.7 就是）
            local gd
            gd="$(git -C "$root" rev-parse --git-dir 2>/dev/null)"
            case "$gd" in
                "") ;;
                /*|[A-Za-z]:/*) gitdir="$gd" ;;
                *) gitdir="$(cd "$root/$gd" 2>/dev/null && pwd)" ;;
            esac
        fi
        if [ -z "$gitdir" ]; then
            printf '  [x] 取不到 .git 目录，无法核对索引内容\n' >&2
            return 1
        fi
        local -a got=()
        while IFS= read -r line; do got+=("$line"); done < "$({
            cd "$tree" || exit 1
            printf '%s\n' "${present[@]}" |
                GIT_DIR="$gitdir" GIT_WORK_TREE="$tree" git hash-object --stdin-paths 2>/dev/null
        } | feed)"
        if [ "${#got[@]}" -ne "${#present[@]}" ]; then
            printf '  [x] 无法对索引内容求哈希（%s 个文件只拿到 %s 个）\n' "${#present[@]}" "${#got[@]}" >&2
            return 1
        fi
        for ((i = 0; i < ${#present[@]}; i++)); do
            [ "${got[i]}" = "${present_sha[i]}" ] || forged+=("${present[i]}")
        done
    fi

    if [ "${#missing[@]}" -gt 0 ] || [ "${#forged[@]}" -gt 0 ]; then
        if [ "${#missing[@]}" -gt 0 ]; then
            printf '  [x] 索引里有、物化树里没有（skip-worktree / 稀疏检出？）：\n' >&2
            printf '        %s\n' "${missing[@]:0:10}" >&2
        fi
        if [ "${#forged[@]}" -gt 0 ]; then
            printf '  [x] 物化出来的内容与索引 blob 不同（smudge 过滤器改写了内容？）：\n' >&2
            printf '        %s\n' "${forged[@]:0:10}" >&2
        fi
        printf '  检查的内容必须等于提交的内容。先关掉相关过滤/标记（\`git config --unset filter.<name>.smudge\`、\n' >&2
        printf '  \`git update-index --no-skip-worktree <path>\`）再提交；这几种状态下的「通过」没有意义。\n' >&2
        return 1
    fi
    return 0
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
    # 调用时的 cwd：命令行里点名的任务目录按它解析（脚本随后会 cd 到仓库根/临时树）。
    invoke_pwd="$(pwd)"
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$root" ] || root="$(cd "$(dirname "$0")/.." && pwd)"
    # git 给的是 `D:/…`，bash 的 pwd 给的是 `/d/…` —— 两种写法不能直接比前缀。
    # 统一成 bash 的写法，下面把点名路径折成仓库相对路径时才不会漏。
    root_pwd="$(cd "$root" && pwd)"

    # 判定逻辑在 check-gates.awk，与本脚本同目录。脚本自身始终取工作区版本
    # （钩子调的也是工作区的 scripts/check-gates.sh），所以要在 cd 进临时树之前解析。
    AWK_PROG="$(cd "$(dirname "$0")" && pwd)/check-gates.awk"
    if [ ! -f "$AWK_PROG" ]; then
        printf '找不到 %s —— 它与 check-gates.sh 必须放在一起\n' "$AWK_PROG" >&2
        exit 2
    fi

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
        # 物化目标用全局变量：它要在 main 返回之后仍然可见（EXIT trap 在这个
        # 目录的父目录上），用 local 会在 set -u 下变成未绑定变量。
        # 直接建在 $GATES_TMP 下：一个临时目录、一个 EXIT trap。
        check_tree_tmp="$GATES_TMP/tree"
        mkdir -p "$check_tree_tmp"
        # 物化失败必须硬停：否则会在一个空临时树里继续跑，每个任务目录都报
        # 「缺 plan.md / journal.md」——一堆假违规比一句报错难查得多。
        if ! git -C "$root" checkout-index -a --prefix="$check_tree_tmp/" 2>/dev/null; then
            printf '  [x] 无法把 git 索引物化到临时目录（checkout-index 失败），--staged 中止\n' >&2
            exit 2
        fi
        # 物化结果必须**逐条核对**，两件事：
        #   1. 存在性——checkout-index 跳过 skip-worktree（稀疏检出就靠这个位），
        #      被跳过的 plan.md / 任务目录从视野里整个消失，提交照进；
        #   2. 内容——checkout-index **会套 smudge 过滤器**（索引 blob 是 `AAA`，
        #      物化出来可以是 `BBB`），于是检查器读的是被洗白的那份。
        # 任一不符就中止（exit 2）：在不可信的副本上给出的「通过」没有意义。
        if ! verify_materialized "$root" "$check_tree_tmp"; then
            printf '  [x] 无法可信地物化 git 索引（工作区与索引不一致，见上），--staged 中止\n' >&2
            exit 2
        fi
        cd "$check_tree_tmp" || exit 2
    else
        cd "$root" || exit 2
    fi

    # 闸门 B：残留扫描。--staged 查索引，全量查工作区
    check_gate_b "$staged" "$root"

    # 架构：模块表 vs 实际目录。仓库状态不变量，两种模式都跑
    check_architecture "$staged" "$root"

    # 文档内相对引用 + ADR 互链：都是「仓库状态」不变量，和具体任务无关
    if [ "$staged" -eq 0 ]; then
        local hp
        hp="$(git -C "$root" config core.hooksPath 2>/dev/null)"
        # 归一化后再比：`.githooks/` / `./.githooks` / 绝对路径都指向同一个目录，
        # 字符串全等会把它们判成「没装钩子」，然后一条提示就放过去了。
        hp_norm="${hp%/}"
        case "$hp_norm" in
            ./.githooks) hp_norm=".githooks" ;;
        esac
        if [ -n "$hp_norm" ] && [ "$hp_norm" != ".githooks" ]; then
            # 绝对路径指向本仓库的 .githooks 也算装好了
            case "$hp_norm" in /*|[A-Za-z]:/*)
                if [ "$(cd "$hp_norm" 2>/dev/null && pwd)" = "$(cd "$root/.githooks" && pwd)" ]; then
                    hp_norm=".githooks"
                fi ;;
            esac
        fi
        if [ "$hp_norm" != ".githooks" ]; then
            note "core.hooksPath 不是 .githooks（当前：${hp:-未设置}）：提交前闸门不会自动执行。跑一次 \`git config core.hooksPath .githooks\`。"
        fi
        # 可执行位：clone 到 Linux / macOS 后，没有 +x 的钩子 git 会静默跳过。
        # 检查的是**索引里的 mode**，这个跨平台有意义——Windows 上 worktree 的 +x
        # 没有意义，但把 `100644` 提交出去，别人 clone 后钩子就不执行。所以这段
        # 不按 uname 跳过。
        # 工作区的 +x：索引 mode 对但工作区被 chmod -x 时（未暂存），git 也不会执行钩子。
        # 只在 POSIX 上判断（Windows 没有这个概念）。
        case "$(uname -s 2>/dev/null)" in
            MINGW*|MSYS*|CYGWIN*) ;;
            *)
                for f in .githooks/pre-commit .githooks/pre-merge-commit .githooks/pre-push; do
                    [ -f "$root/$f" ] || continue
                    [ -x "$root/$f" ] ||
                        fail "$f 没有可执行位（工作区）—— git 会静默跳过它。跑 \`chmod +x $f\`"
                done
                ;;
        esac
        for f in .githooks/pre-commit .githooks/pre-merge-commit .githooks/pre-push; do
            [ -f "$root/$f" ] || continue
            if [ -n "$(git -C "$root" ls-files -s -- "$f" 2>/dev/null | awk '$1 != "100755"')" ]; then
                fail "$f 在索引里不是可执行文件（100755）—— clone 到 Linux / macOS 后 git 会静默跳过这个钩子。跑 \`git update-index --chmod=+x $f\`"
            fi
        done
        if [ "$hp_norm" = ".githooks" ] &&
           { [ ! -f "$root/.githooks/pre-commit" ] ||
             ! git -C "$root" cat-file -e :.githooks/pre-commit 2>/dev/null ||
             [ ! -f "$root/.githooks/pre-merge-commit" ] ||
             ! git -C "$root" cat-file -e :.githooks/pre-merge-commit 2>/dev/null ||
             [ ! -f "$root/.githooks/pre-push" ] ||
             ! git -C "$root" cat-file -e :.githooks/pre-push 2>/dev/null; }; then
            # 钩子被删了但配置还指着它 —— 这时候「配置正确」是假象，闸门一次都不会跑。
            # 只提示不够：这是**最后一个**能发现「钩子缺失」的地方（提交时的核对只看
            # 得到下一次 commit；merge 闸门与可执行位各有独立入口）。
            fail "core.hooksPath 指向 .githooks，但 .githooks/{pre-commit,pre-merge-commit,pre-push} 有缺失（工作区或索引）—— 对应入口（commit / merge / push）的闸门不会执行（git 找不到钩子就静默跳过）。恢复它们（\`git checkout -- .githooks/\`）再继续"
        fi
    fi

    check_links "$staged"
    check_adr
    check_doc_counts "$staged"
    # 代码里的 `决策: ADR-NNNN` 锚点：只提示，不影响退出码
    check_anchors "$staged" "$root"

    # 要检查哪些任务目录
    local dirs=()
    local d p rest st p1 p2 np
    if [ "${#task_args[@]}" -gt 0 ]; then
        # 参数按**调用时**的 cwd 解析。脚本后面会 cd 到仓库根，
        # 从子目录用相对路径点名（`cd docs && ../scripts/check-gates.sh ../tasks/x`）
        # 就会找不到——那时 ../tasks/x 是相对 docs 的，不是相对仓库根。
        local a rel
        for a in "${task_args[@]}"; do
            case "$a" in
                /*|[A-Za-z]:[/\\]*) rel="$a" ;;
                *) rel="$invoke_pwd/$a" ;;
            esac
            case "$rel" in
                "$root_pwd"/*) rel="${rel#"$root_pwd"/}" ;;
            esac
            case "$rel" in
                tasks/_template|tasks/_template/)
                    printf '%s\n' "跳过 $rel（模板，不是任务）"
                    continue ;;
            esac
            if [ -d "$rel" ]; then dirs+=("$rel"); else fail "找不到任务目录: $a"; fi
        done
    elif [ "$staged" -eq 1 ]; then
        # D 也要算：只删 review.md 的那次提交同样得查那个任务目录，
        # 不然「T2/T3 必须有 review.md」在删除路径上是空的。
        while IFS=$'\t' read -r st p1 p2; do
            # 重命名/复制时第二列是目标路径；其余状态只有一列。
            case "$st" in R*|C*) np="$p2" ;; *) np="$p1" ;; esac
            [ -n "${np:-}" ] || continue

            # 拍平检测要放在重命名豁免**之前**：`git mv tasks/x tasks/_archive`
            # 在 _archive 不存在时正是 R100——跳过 R100 就会把这种归档方式放过去，
            # 而那层的文件从此不在任何全量检查的覆盖里。
            #
            # 注意 case 的 `*` 会跨 `/`：不能写 `tasks/_archive/*.md`——那会把
            # `tasks/_archive/<任务>/journal.md` 也匹配上，正常归档全被判成拍平。
            case "$np" in
                tasks/_archive/*)
                    rest="${np#tasks/_archive/}"
                    case "$rest" in
                        */*) : ;;   # 正常归档：<任务>/<文件>
                        *)
                            fail "$np: tasks/_archive/ 顶层不该有文件——归档要 'mkdir -p tasks/_archive' 之后再 git mv，见 tasks/README.md 的「归档」"
                            continue ;;
                    esac ;;
            esac

            # 纯重命名 / 纯复制（内容一字未变）不算改动。归档就是把任务目录挪进
            # tasks/_archive/，文件本身没变；按内容查会把「归档」这个被推荐的动作
            # 本身判红（旧格式的任务目录一归档就 60 条违规）。
            case "$st" in R100|C100) continue ;; esac

            case "$np" in
                # 归档过的任务在 tasks/_archive/<任务>/ 下，比在飞的深一层。
                # 改到它照样要查——「跳过」只针对全量自查，不是免检。
                tasks/_archive/*/*)
                    rest="${np#tasks/_archive/}"
                    dirs+=("tasks/_archive/${rest%%/*}") ;;
                tasks/*/*)
                    rest="${np#tasks/}"
                    d="tasks/${rest%%/*}"
                    case "$d" in tasks/_template) continue ;; esac
                    dirs+=("$d") ;;
            esac
        done < "$(git -c core.quotepath=false -C "$root" diff --cached --name-status -M --diff-filter=ACMRD 2>/dev/null | feed)"
    else
        # `tasks/_archive/` 里**直接躺着 .md 文件**说明归档方式用错了：
        # `git mv tasks/x tasks/_archive/` 在 _archive 不存在时会把任务目录改名成
        # `_archive`，文件被拍平到这一层。拍平之后全量自查会把它整个跳过——
        # 那些文件从此不在任何全量检查的覆盖里（--staged 碰到才会查）。
        for f in tasks/_archive/*.md; do
            [ -f "$f" ] || continue
            fail "$f: tasks/_archive/ 顶层不该有文件——归档要 'mkdir -p tasks/_archive' 之后再 git mv，见 tasks/README.md 的「归档」"
            break
        done
        for d in tasks/*/; do
            [ -d "$d" ] || continue
            # _template 是模板；_archive 是已完成并归档的（tasks/ 只放在飞的）。
            # 归档目录不是一个任务目录，它的子目录也不在 tasks/*/ 这一层——
            # 但留着这句，免得以后有人往 _archive/ 顶层放文件时被当成任务。
            case "$d" in tasks/_template/|tasks/_archive/) continue ;; esac
            dirs+=("${d%/}")
        done
    fi

    # 规模底线：只在 --staged 有意义（要有「这次提交」这个基准）
    check_scale "$staged" "$root" ${dirs[@]+"${dirs[@]}"}

    # 计划里的文件已被提交、但这个 T2/T3 任务还没有裁决单 —— 说明「先提交代码、
    # 后补审查」。归属靠 plan.md 的「相关文件」：它机器可读，而「哪次提交属于哪个
    # 任务」看不出来。多次提交里只要有一次命中，审查就来不及了。
    if [ "$staged" -eq 1 ]; then
        check_review_by_scope "$root"
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
        # 切片 / 决策条目：NN-*.md，NN 是 1–2 位数字（见 tasks/README.md）。
        # 同时认下划线分隔（`01_a.md`）——只认短横线的话，改个名字就整条免检了。
        # 两位数字的上限把 `2026-10-31-调研.md` 这类笔记排除在外（那是笔记不是切片）。
        local s
        for s in "$d"/[0-9][-_]*.md "$d"/[0-9][0-9][-_]*.md; do
            [ -f "$s" ] || continue
            printf '%s\n' "检查 $s"
            check_slice "$s"
            any=1
        done
        # 文件名不在约定里时，上面所有分支都不会碰它，那个文件于是整条免检。
        # **无条件**扫（有 plan.md 时也一样）：`100-x.md` 混进一个正常任务目录，
        # 同样会被静默跳过。三位以上数字开头的是笔记（tasks/README.md 的约定），只提示。
        local u
        for u in "$d"/*.[mM][dD]; do
            [ -f "$u" ] || continue
            case "${u##*/}" in
                plan.md|prd.md|journal.md|review.md) continue ;;
                [0-9][0-9][-_]*.md|[0-9][-_]*.md) continue ;;
                [0-9][0-9][0-9]*) note "$u: 三位以上数字开头，按 tasks/README.md 的约定当笔记处理，不检查"; continue ;;
            esac
            fail "$u: 不认识的任务文件名 —— 任务目录里只可能是 plan.md / prd.md / journal.md / review.md，或 NN-*.md 切片（NN 是 1–2 位数字）"
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
