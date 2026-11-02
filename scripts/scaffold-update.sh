#!/usr/bin/env bash
#
# >>> usage
# 脚手架更新器 —— 把已经生成的项目里的脚手架文件升级到当前版本。
#
#   bash scripts/scaffold-update.sh <项目目录>                预览，不写盘
#   bash scripts/scaffold-update.sh <项目目录> --write        真正写盘
#   bash scripts/scaffold-update.sh <项目目录> --diff         预览时打印改动内容
#   bash scripts/scaffold-update.sh <项目目录> --from <sha>   指定基线版本
#   bash scripts/scaffold-update.sh <项目目录> --write --force
#                                                            目标仓库脏也照样写
#   bash scripts/scaffold-update.sh <项目目录> --write --keep-local <路径>
#   bash scripts/scaffold-update.sh <项目目录> --write --union <路径>
#                                                            给单个文件记下裁决
#
# 逐文件三方合并：
#   ours   = 项目里现在的文件
#   base   = 项目生成时的脚手架版本（旧模板，已替换 {{PROJECT_NAME}}）
#   theirs = 当前 templates/（同样已替换）
#
#   ours == base        → 升级成 theirs
#   theirs == base      → 保留 ours（只有本地改动）
#   ours == theirs      → 未变
#   两边都改过          → git merge-file 合并；有冲突就写冲突标记并报告
#   只在 theirs 里有    → 新增
#   只在 base 里有      → 模板删掉了：ours 没改就删，改过就保留并报告
#
# 已裁决的文件（记在 .scaffold-version 的 decision 段）不再走上面的判断：
#   keep-local  永远保留本地版；模板又变了就提示「请重新判断」
#   union       把模板里本地没有的行追加进来，本地行一条不删
# 用途：docs/commands.md、docs/pitfalls.md 这类「项目填满、模板只是骨架」的
# 文件，每次同步都会重新起冲突。裁决一次，之后只在模板真变了时才打扰你。
#
# 基线从哪来（按优先级）：
#   1. --from <sha>
#   2. 项目根的 .scaffold-version 里记的 commit（本脚本更新成功后写入）
#   3. 都没有 → 拿项目内容和脚手架历史逐个比对，挑最像的那个版本，并报匹配度
#
# 只碰 templates/ 里出现过的路径：src/、tasks/<任务>、.git/ 一概不动。
# 有冲突时三方快照留在 <项目>/.git/scaffold-work/<时间戳>/（项目不是 git 仓库时
# 落在 <项目>/.scaffold-work/），可以拿它们复核或重跑 git merge-file。
# 写完要自己看一眼 `git diff` 再提交——脚本不做提交。
#
# 退出码：0 = 完成（含无事可做），1 = 有冲突需要人工处理，2 = 用法/环境错误。
# <<< usage

set -u

# 用了关联数组（bash 4 起）。macOS 自带的 /bin/bash 是 3.2，跑不了——
# 这个脚本是脚手架仓库自己的工具（不随项目分发），和 scripts/check-tree.ps1 一样
# 只保证维护者本机能跑。
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { printf '错误: 需要 bash 4 以上（当前 %s）\n' "${BASH_VERSION:-未知}" >&2; exit 2; }

# 输出被 `| head` 之类提前关掉时不要中途死掉：这个脚本会写文件，半路退出比报错更糟。
trap '' PIPE

die() { printf '错误: %s\n' "$*" >&2; exit 2; }
note() { printf '  [!] %s\n' "$*"; }

usage() {
    sed -n '/^# >>> usage$/,/^# <<< usage$/p' "${BASH_SOURCE[0]}" | sed '1d;$d' | sed 's/^# \{0,1\}//'
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAFFOLD_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCAFFOLD_ROOT/templates"

WRITE=0
FROM=""
SHOW_DIFF=0
FORCE=0
KEEP_LOCAL=()
UNIONS=()
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --write)   WRITE=1 ;;
        --dry-run) WRITE=0 ;;
        --diff)    SHOW_DIFF=1 ;;
        --force)   FORCE=1 ;;
        --from)    shift; [ "$#" -gt 0 ] || die "--from 需要一个提交"; FROM="$1" ;;
        --from=*)  FROM="${1#--from=}" ;;
        --keep-local) shift; [ "$#" -gt 0 ] || die "--keep-local 需要一个路径"; KEEP_LOCAL+=("$1") ;;
        --keep-local=*) KEEP_LOCAL+=("${1#--keep-local=}") ;;
        --union)   shift; [ "$#" -gt 0 ] || die "--union 需要一个路径"; UNIONS+=("$1") ;;
        --union=*) UNIONS+=("${1#--union=}") ;;
        -h|--help) usage; exit 0 ;;
        -*)        die "未知选项: $1（--help 看用法）" ;;
        *)         POSITIONAL+=("$1") ;;
    esac
    shift
done
[ "${#POSITIONAL[@]}" -eq 1 ] || { usage; exit 2; }

[ -d "$TEMPLATE_DIR" ] || die "找不到模板目录: $TEMPLATE_DIR"
PROJECT="$(cd "${POSITIONAL[0]}" 2>/dev/null && pwd)" || die "找不到项目目录: ${POSITIONAL[0]}"
[ "$PROJECT" != "$SCAFFOLD_ROOT" ] || die "这是脚手架仓库自己，不是生成出来的项目"
[ -f "$PROJECT/AGENTS.md" ] || die "$PROJECT 里没有 AGENTS.md —— 看起来不是这个脚手架生成的项目"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- 基线

is_commit() { git -C "$SCAFFOLD_ROOT" rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1; }

git -C "$SCAFFOLD_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$SCAFFOLD_ROOT 不是 git 仓库 —— 基线要从脚手架历史里取"

# 项目名：项目自己的文件最可信——生成时写过占位符，标题里就带着名字。
# 目录被改过名（或者这是别人拷过来的一份）时，拿目录名当项目名会把每个带
# {{PROJECT_NAME}} 的文件都判成「本地改过」，还会把错的名字写进新文件。
name_from_agents() {
    local f="$PROJECT/AGENTS.md" line prefix
    [ -f "$f" ] || return 1
    [ -f "$TEMPLATE_DIR/AGENTS.md" ] || return 1
    line="$(head -n 1 "$f")"
    prefix="$(head -n 1 "$TEMPLATE_DIR/AGENTS.md" | sed 's/{{PROJECT_NAME}}.*//')"
    case "$line" in
        "$prefix"?*) printf '%s' "${line#"$prefix"}" ;;
        *) return 1 ;;
    esac
}

PROJECT_NAME=""
BASE_COMMIT="$FROM"
VERSION_FILE="$PROJECT/.scaffold-version"
# 关联数组（bash 4）。写成 `DEC_STRAT=()` 会当**索引**数组，下标被当算术表达式，
# 于是 `DEC_STRAT[.gitattributes]` 直接报 "syntax error: operand expected"。
declare -A DEC_STRAT=()
declare -A DEC_SHA=()
declare -A DNEW=()
GATE_PREV=""
if [ -f "$VERSION_FILE" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            project_name) [ -n "$PROJECT_NAME" ] || PROJECT_NAME="$v" ;;
            commit)       [ -n "$BASE_COMMIT" ] || BASE_COMMIT="$v" ;;
            gate_violations) [ -n "$GATE_PREV" ] || GATE_PREV="$v" ;;
            # `decision <策略> <路径> <记录时的模板 blob>`：整行没有 '='，于是 k 是整行
            decision\ *)
                read -r _tag _strat _path _sha <<< "$k"
                if [ -n "${_path:-}" ]; then
                    DEC_STRAT["$_path"]="$_strat"
                    DEC_SHA["$_path"]="${_sha:-}"
                fi
                ;;
        esac
    done < "$VERSION_FILE"
fi
FROM_CONTENT="$(name_from_agents || true)"
if [ -n "$FROM_CONTENT" ]; then
    [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "$FROM_CONTENT" ] \
        && note "记录里的项目名是「$PROJECT_NAME」，但 AGENTS.md 标题写的是「$FROM_CONTENT」——以文件内容为准"
    PROJECT_NAME="$FROM_CONTENT"
fi
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="$(basename "$PROJECT")"

if [ -n "$BASE_COMMIT" ] && ! is_commit "$BASE_COMMIT"; then
    note "基线提交 $BASE_COMMIT 在脚手架里不存在，改为按内容比对"
    BASE_COMMIT=""
fi

# 占位符替换：和 init 脚本同一条规则（项目名里的 / & 之类已被 init 拒掉）。
# 先一次 grep 找出带占位符的文件（只有 AGENTS.md / README.md 这种），再逐个替换：
# 每文件一次 grep 在这个环境里是 ~0.1s/次，28 个文件就是 3 秒。
render_placeholders() {
    local dir="$1" f tmp
    while IFS= read -r f; do
        tmp="$(mktemp)"
        sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$f" > "$tmp" && cat "$tmp" > "$f"
        rm -f "$tmp"
    done < <(grep -rl '{{PROJECT_NAME}}' "$dir" 2>/dev/null | sort)
}

# 把某个提交的 templates/ 展开到 $2 并替换占位符。
# 一次 `git archive | tar`，不是每文件一次 `git show`——本机起一个进程约 0.1s，
# 28 个文件逐次展开要 3 秒，整棵树打包一次 0.4 秒。
render_commit() {
    local c="$1" dest="$2"
    mkdir -p "$dest"
    git -C "$SCAFFOLD_ROOT" archive --format=tar "$c:templates" | tar -xf - -C "$dest" || return 1
    render_placeholders "$dest"
}

# 工作区的 templates/（可能带着还没提交的改动）——「新版」取它，
# 因为脚手架常常在改到一半时就要把项目升上去。
render_worktree() {
    local dest="$1"
    mkdir -p "$dest"
    cp -r "$TEMPLATE_DIR/." "$dest/" || return 1
    render_placeholders "$dest"
}

# 没有基线记录时：拿项目现有内容和脚手架历史比对，挑一致率最高的版本。
#
# 比的是 git blob 哈希，不是文件内容。两个提速点，都是因为本机起一个进程约 0.1s：
#   - 项目侧哈希一次算完，不是每文件一次
#   - 占位符文件一次 grep 找出来，不是每文件一次
# 剩下的成本是每个历史版本一次 `ls-tree`（46 个版本约 5 秒）。只在不带
# .scaffold-version 的旧项目上跑一次，之后都走记录里的提交。
#
# **项目侧的哈希必须走索引，不能直接 hash-object 工作区文件。**
# `git hash-object` 默认套 clean 过滤器，于是 `core.autocrlf=true` 的机器会把
# CRLF 归一成 LF 再算哈希：一份只有行尾不同的文件，和模板 blob 算出同一个哈希，
# 该扣的分没扣，基线就挑到别的版本；换一台 autocrlf=false 的机器又是另一个结果。
# `git ls-files -s` 给的是索引里的 blob——它和脚手架历史里的 blob 是同一个口径
# （都是 clean 之后的），不受本机 config 影响。索引里没有的文件（还没 add、
# 项目不是仓库）才现算，且 `--no-filters` 按原始字节，不经过任何归一。
#
# 带 {{PROJECT_NAME}} 的文件不参与：模板展开后必然和项目对不上，那是占位符替换的
# 结果，不是版本差异。用剩下的文件打分，项目自己改过的文件只会拉低一点分数。
autodetect_base() {
    local c meta p rel sha pct total score best="" best_pct=-1 mode stage
    local -A proj=() skip=()
    local -a paths=() rest=()

    while IFS= read -r rel; do
        skip["$rel"]=1
    done < <( grep -rl '{{PROJECT_NAME}}' "$TEMPLATE_DIR" 2>/dev/null \
              | sed "s|^$TEMPLATE_DIR/||" | sort )

    while IFS= read -r rel; do
        [ -n "${skip[$rel]+x}" ] && continue
        [ -f "$PROJECT/$rel" ] || continue
        paths+=("$rel")
    done < <( cd "$TEMPLATE_DIR" && find . -type f | sed 's|^\./||' | sort )
    [ "${#paths[@]}" -gt 0 ] || return 1

    # 1) 索引里的 blob（一次进程）。清理过，和脚手架历史同口径。
    if git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
        while IFS=$'\t' read -r meta p; do
            [ -n "$meta" ] || continue
            read -r mode sha stage <<< "$meta"
            [ -n "$sha" ] && proj["$p"]="$sha"
        done < <( git -C "$PROJECT" -c core.quotepath=false ls-files -s 2>/dev/null )
    fi

    # 2) 索引里没有的：按原始字节算，不套 autocrlf。
    for rel in "${paths[@]}"; do
        [ -n "${proj[$rel]+x}" ] || rest+=("$rel")
    done
    if [ "${#rest[@]}" -gt 0 ]; then
        local i=0
        while IFS= read -r sha; do
            proj["${rest[$i]}"]="$sha"
            i=$((i + 1))
        done < <( cd "$PROJECT" && printf '%s\n' "${rest[@]}" \
                 | git hash-object --no-filters --stdin-paths 2>/dev/null )
    fi

    while IFS= read -r c; do
        [ -n "$c" ] || continue
        total=0
        score=0
        while IFS=$'\t' read -r meta p; do
            rel="${p#templates/}"
            [ -n "${skip[$rel]+x}" ] && continue    # 占位符文件：索引里也有，必须在这里再排一次
            [ -n "${proj[$rel]:-}" ] || continue
            total=$((total + 1))
            sha="${meta##* }"
            [ "$sha" = "${proj[$rel]}" ] && score=$((score + 1))
        done < <(git -C "$SCAFFOLD_ROOT" -c core.quotepath=false ls-tree -r "$c" -- templates)
        [ "$total" -gt 0 ] || continue
        pct=$((score * 100 / total))
        if [ "$pct" -gt "$best_pct" ]; then best_pct="$pct"; best="$c"; fi
    done < <(git -C "$SCAFFOLD_ROOT" log --format=%H -n 100 -- templates)
    printf '%s %s\n' "$best" "$best_pct"
}

MATCH_PCT=""
if [ -z "$BASE_COMMIT" ]; then
    DETECTED="$(autodetect_base)"
    BASE_COMMIT="${DETECTED%% *}"
    MATCH_PCT="${DETECTED##* }"
    [ -n "$BASE_COMMIT" ] || die "在脚手架历史里找不到能对上的版本，请用 --from <sha> 指定"
    [ "$MATCH_PCT" -ge 50 ] || note "最像的版本只对上 ${MATCH_PCT}% 的文件 —— 项目可能改动较多，合并结果请仔细看"
fi

if [ -n "$BASE_COMMIT" ] && ! git -C "$SCAFFOLD_ROOT" merge-base --is-ancestor "$BASE_COMMIT" HEAD 2>/dev/null; then
    note "基线 $BASE_COMMIT 不是当前 HEAD 的祖先（脚手架历史被改写过？）—— 合并结果请仔细看"
fi

render_commit "$BASE_COMMIT" "$WORK/base" || die "展开基线版本 $BASE_COMMIT 失败"
render_worktree "$WORK/theirs" || die "展开当前 templates/ 失败"

NEW_COMMIT="$(git -C "$SCAFFOLD_ROOT" rev-parse HEAD 2>/dev/null || true)"

printf '项目: %s\n' "$PROJECT"
if [ -n "$MATCH_PCT" ]; then
    printf '基线: %s（按内容比对，一致率 %s%%）\n' "${BASE_COMMIT:0:7}" "$MATCH_PCT"
else
    printf '基线: %s\n' "${BASE_COMMIT:0:7}"
fi
printf '新版: %s\n\n' "${NEW_COMMIT:0:7}"

# ---------------------------------------------------------------- 裁决

# 模板侧的 blob：用来判断「裁决之后模板有没有再变」。
template_sha() {
    [ -f "$1" ] || return 0
    git hash-object --no-filters -- "$1" 2>/dev/null || true
}

# 登记 --keep-local / --union。只接受模板里真实存在的路径：写错的路径不会
# 被任何一次同步用到，却会一直躺在 .scaffold-version 里像条规则。
record_decisions() {
    local p strat t
    for p in ${KEEP_LOCAL[@]+"${KEEP_LOCAL[@]}"}; do
        [ -f "$WORK/theirs/$p" ] || die "--keep-local 的路径不在 templates/ 里: $p"
        DEC_STRAT["$p"]="keep-local"
        DEC_SHA["$p"]="$(template_sha "$WORK/theirs/$p")"
        DNEW["$p"]=1
        note "记下裁决: keep-local $p"
    done
    for p in ${UNIONS[@]+"${UNIONS[@]}"}; do
        [ -f "$WORK/theirs/$p" ] || die "--union 的路径不在 templates/ 里: $p"
        DEC_STRAT["$p"]="union"
        DEC_SHA["$p"]="$(template_sha "$WORK/theirs/$p")"
        DNEW["$p"]=1
        note "记下裁决: union $p"
    done
}
if [ "${#KEEP_LOCAL[@]}" -gt 0 ] || [ "${#UNIONS[@]}" -gt 0 ]; then
    [ "$WRITE" -eq 1 ] || note "裁决只在 --write 时写入 .scaffold-version；这次是预览，只展示"
    record_decisions
fi

# ---------------------------------------------------------------- 逐文件

n_up=0 n_keep=0 n_merge=0 n_conf=0 n_add=0 n_del=0 n_same=0 n_foreign=0
n_skip=0 n_union=0 n_stale=0
STALE=()

is_repo=0
git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 && is_repo=1

# 目标仓库脏就不写：脚本写的是模板路径，人改的可能是同一批文件，
# 混在一起提交时说不清哪些是工具写的——上一次事故就是这么来的。
# 只看已跟踪文件的改动：`.scaffold-version` 首次运行后是未跟踪的，
# 把它算进「脏」会让第二次运行被自己的产物挡下。
if [ "$WRITE" -eq 1 ] && [ "$is_repo" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
    dirty="$(git -C "$PROJECT" -c core.quotepath=false status --porcelain --untracked-files=no 2>/dev/null)"
    if [ -n "$dirty" ]; then
        printf '错误: 目标仓库有未提交的改动，拒绝写盘（会和你的改动混在一起）：\n' >&2
        printf '%s\n' "$dirty" | sed 's/^/    /' >&2
        printf '先提交或 stash，或者加 --force。\n' >&2
        exit 2
    fi
fi

# 冲突现场：base/ours/theirs 各留一份，否则只能凭记忆裁决。
# 优先放 .git/ 里——git 自己就不跟踪，不需要动目标的 .gitignore。
KEEP_DIR=""
keep_conflict() {
    local p="$1" o="$2" b="$3" t="$4" gitdir
    if [ -z "$KEEP_DIR" ]; then
        if [ "$is_repo" -eq 1 ]; then
            gitdir="$(git -C "$PROJECT" rev-parse --absolute-git-dir 2>/dev/null || printf '%s/.git' "$PROJECT")"
            KEEP_DIR="$gitdir/scaffold-work/$(date +%Y%m%d-%H%M%S)"
        else
            KEEP_DIR="$PROJECT/.scaffold-work/$(date +%Y%m%d-%H%M%S)"
        fi
        mkdir -p "$KEEP_DIR" || return 0
        printf 'base=%s\nnew=%s\n' "${BASE_COMMIT:-}" "${NEW_COMMIT:-}" > "$KEEP_DIR/REVISIONS"
    fi
    mkdir -p "$KEEP_DIR/$(dirname "$p")" 2>/dev/null || true
    cp "$o" "$KEEP_DIR/$p.ours" 2>/dev/null || true
    cp "$b" "$KEEP_DIR/$p.base" 2>/dev/null || true
    cp "$t" "$KEEP_DIR/$p.theirs" 2>/dev/null || true
}

# union：只把模板里本地没有的行追加进去，本地一行不删。
union_append() {
    local o="$1" t="$2" line
    [ -s "$o" ] && [ -n "$(tail -c 1 "$o")" ] && printf '\n' >> "$o"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -Fxq -- "$line" "$o" || printf '%s\n' "$line" >> "$o"
    done < "$t"
}

# 新增 / 合并后的文件如果是脚本或钩子，可执行位必须记进索引：
# Windows 上 chmod 不可靠，而 clone 到 Linux/macOS 时钩子没有可执行位会被静默跳过。
mark_exec() {
    local rel="$1"
    case "$rel" in
        scripts/*|.githooks/*)
            chmod +x "$PROJECT/$rel" 2>/dev/null || true
            [ "$is_repo" -eq 1 ] && git -C "$PROJECT" add --chmod=+x -- "$rel" >/dev/null 2>&1
            ;;
    esac
}

# 比较时忽略纯行尾差异。项目自带 `* text=auto eol=lf`，行尾只是 checkout 的产物；
# 工作区里一个 CRLF 的文件不该被当成「我改过它」，否则每个文件都会走合并，
# 而 git merge-file 会把「整份都变了」判成冲突。
same() {
    cmp -s "$1" "$2" && return 0
    # 退一步：忽略行尾 CR 再比。不用 `diff --strip-trailing-cr`——BSD 的 diff 没这个选项。
    cmp -s <(sed 's/\r$//' "$1") <(sed 's/\r$//' "$2")
}

# --diff：让「升级」这个结论带上内容。默认只给分类，十个文件全凭信任接受。
show_diff() {
    [ "$SHOW_DIFF" -eq 1 ] || return 0
    local out
    out="$(diff -u "$1" "$2" 2>/dev/null | sed -n '3,22p')" || true
    [ -n "$out" ] || return 0
    printf '%s\n' "$out" | sed 's/^/      /'
}

while IFS= read -r p; do
    [ -n "$p" ] || continue
    b="$WORK/base/$p"
    t="$WORK/theirs/$p"
    o="$PROJECT/$p"

    has_b=0; [ -f "$b" ] && has_b=1
    has_t=0; [ -f "$t" ] && has_t=1
    has_o=0; [ -f "$o" ] && has_o=1

    # 已裁决的文件：先看裁决，不再走下面的判断
    if [ -n "${DEC_STRAT[$p]:-}" ]; then
        strat="${DEC_STRAT[$p]}"
        cur_sha=""
        [ "$has_t" -eq 1 ] && cur_sha="$(template_sha "$t")"
        novel="${DNEW[$p]:-}"
        # 刚在命令行上记下的裁决要当场生效，不能因为「模板 sha 刚记过」就跳过——
        # 那会让第一次 --keep-local / --union 什么都不做，等下次才有效。
        if [ -z "$novel" ] && { [ "$has_t" -eq 0 ] || [ "$cur_sha" = "${DEC_SHA[$p]:-}" ]; }; then
            printf '  跳过   %s（已裁决 %s，模板未变）\n' "$p" "$strat"
            n_skip=$((n_skip + 1))
            continue
        fi
        case "$strat" in
            keep-local)
                if [ -n "$novel" ]; then
                    printf '  裁决   %s（keep-local：保留本地版）\n' "$p"
                    n_skip=$((n_skip + 1))
                    continue
                fi
                printf '  提示   %s（已裁决保留本地，但模板已变 —— 重新判断后重记裁决）\n' "$p"
                STALE+=("$p")
                n_stale=$((n_stale + 1))
                continue
                ;;
            union)
                if [ "$has_o" -eq 0 ]; then
                    printf '  保留   %s（本地已删，裁决是 union —— 自己看要不要恢复）\n' "$p"
                    n_keep=$((n_keep + 1))
                    continue
                fi
                printf '  并集   %s\n' "$p"
                n_union=$((n_union + 1))
                if [ "$WRITE" -eq 1 ]; then union_append "$o" "$t"; mark_exec "$p"; fi
                DEC_SHA["$p"]="$cur_sha"
                continue
                ;;
        esac
    fi

    # 模板删掉了这个文件
    if [ "$has_t" -eq 0 ]; then
        [ "$has_o" -eq 1 ] || continue                      # 项目也没有：无事
        if same "$o" "$b"; then
            printf '  删除   %s\n' "$p"
            n_del=$((n_del + 1))
            [ "$WRITE" -eq 1 ] && rm -f "$o"
        else
            printf '  保留   %s（模板已删，本地改过）\n' "$p"
            n_keep=$((n_keep + 1))
        fi
        continue
    fi

    # 模板新增了这个文件
    if [ "$has_b" -eq 0 ]; then
        if [ "$has_o" -eq 1 ]; then
            # 项目自己就有同名文件：不是从模板来的，绝不覆盖
            if same "$o" "$t"; then
                n_same=$((n_same + 1))
            else
                printf '  跳过   %s（项目已有同名文件，不是模板来的）\n' "$p"
                n_foreign=$((n_foreign + 1))
            fi
            continue
        fi
        printf '  新增   %s\n' "$p"
        n_add=$((n_add + 1))
        if [ "$WRITE" -eq 1 ]; then
            mkdir -p "$(dirname "$o")"
            cp "$t" "$o"
            mark_exec "$p"
        fi
        continue
    fi

    # 项目自己删掉了某个模板文件
    if [ "$has_o" -eq 0 ]; then
        if same "$b" "$t"; then
            printf '  保留   %s（本地已删除，模板没动）\n' "$p"
            n_keep=$((n_keep + 1))
        else
            printf '  保留   %s（本地已删除，模板有改动 —— 自己判断要不要恢复）\n' "$p"
            n_keep=$((n_keep + 1))
        fi
        continue
    fi

    if same "$o" "$t"; then
        n_same=$((n_same + 1))
    elif same "$o" "$b"; then
        printf '  升级   %s\n' "$p"
        n_up=$((n_up + 1))
        show_diff "$b" "$t"
        if [ "$WRITE" -eq 1 ]; then cat "$t" > "$o"; mark_exec "$p"; fi
    elif same "$t" "$b"; then
        printf '  保留   %s（本地改过，模板没动）\n' "$p"
        n_keep=$((n_keep + 1))
    else
        merged="$WORK/merged"
        # 本地那一版先归一到 LF 再参与合并：项目锁 eol=lf，CR 不是内容。
        # 不归一的话，一个 CRLF 文件会被 git merge-file 判成「每一行都变了」。
        sed 's/\r$//' "$o" > "$WORK/ours.lf"
        if git merge-file -p -L local -L scaffold-base -L scaffold-new "$WORK/ours.lf" "$b" "$t" > "$merged"; then
            printf '  合并   %s\n' "$p"
            n_merge=$((n_merge + 1))
            show_diff "$b" "$t"
            if [ "$WRITE" -eq 1 ]; then cat "$merged" > "$o"; mark_exec "$p"; fi
        else
            printf '  冲突   %s（已写冲突标记）\n' "$p"
            n_conf=$((n_conf + 1))
            show_diff "$b" "$t"
            if [ "$WRITE" -eq 1 ]; then
                keep_conflict "$p" "$o" "$b" "$t"
                cat "$merged" > "$o"
                mark_exec "$p"
            fi
        fi
    fi
done < <(
    { [ -d "$WORK/base" ] && ( cd "$WORK/base" && find . -type f | sed 's|^\./||' )
      ( cd "$WORK/theirs" && find . -type f | sed 's|^\./||' )
    } | sort -u
)

# ---------------------------------------------------------------- 事后自检

# 装进来的闸门对新项目是零违规，对既有项目是一堆存量债——上一次就是这么来的：
# 工具装完一声不吭，使用者隔了两轮才发现有 599 条。
gate_violations=""
gate_report() {
    [ -f "$PROJECT/scripts/check-gates.sh" ] || return 0
    printf '\n自检：在目标仓库跑一次闸门检查（新装进来的规则对历史文件也会判）…\n'
    local out n
    out="$( cd "$PROJECT" && "${BASH:-bash}" scripts/check-gates.sh 2>&1 )" || true
    n="$(printf '%s\n' "$out" | grep -c '^  \[x\]')" || n=0
    gate_violations="$n"
    if [ "$n" -eq 0 ]; then
        printf '  存量违规 0 条，钩子可以放心启用。\n'
    else
        printf '  存量违规 %s 条:\n' "$n"
        printf '%s\n' "$out" | grep '^  \[x\]' | head -5 | sed 's/^/  /'
        [ "$n" -gt 5 ] && printf '  …（还有 %s 条）\n' "$((n - 5))"
        if [ -n "$GATE_PREV" ] && [ "$n" -gt "$GATE_PREV" ]; then
            printf '  比上次多 %s 条 —— 这次升级让规则变严了。\n' "$((n - GATE_PREV))"
        fi
        printf '  启用钩子前先清零，否则每次提交都会被拦；治理路线见 tasks/README.md 的「闸门升级后的存量违规」。\n'
    fi
    hp="$(git -C "$PROJECT" config --get core.hooksPath 2>/dev/null || true)"
    if [ "$hp" != ".githooks" ]; then
        printf '  提示: core.hooksPath 不是 .githooks，钩子不会执行（git config core.hooksPath .githooks）。\n'
    fi
}

# ---------------------------------------------------------------- 版本记录

if [ "$WRITE" -eq 1 ]; then
    # 脚手架自己还有没提交的改动时，别把 HEAD 记成基线——那和实际写进去的内容不符，
    # 下次更新会拿错的基线去合并。留空，下次自动比对，等脚手架提交后就自愈了。
    dirty="$(git -C "$SCAFFOLD_ROOT" -c core.quotepath=false status --porcelain -- templates 2>/dev/null)"
    record="$NEW_COMMIT"
    if [ -n "$dirty" ]; then
        record=""
        note "脚手架 templates/ 有未提交改动 —— 不记录基线提交，下次更新会按内容重新比对"
    fi

    gate_report

    {
        printf 'scaffold=%s\n' "$SCAFFOLD_ROOT"
        printf 'project_name=%s\n' "$PROJECT_NAME"
        printf 'commit=%s\n' "$record"
        printf 'updated=%s\n' "$(date +%Y-%m-%d)"
        [ -n "$gate_violations" ] && printf 'gate_violations=%s\n' "$gate_violations"
        # 裁决按路径排序，diff 里才不会每次换位置
        if [ "${#DEC_STRAT[@]}" -gt 0 ]; then
            for p in $(printf '%s\n' "${!DEC_STRAT[@]}" | sort); do
                printf 'decision %s %s %s\n' "${DEC_STRAT[$p]}" "$p" "${DEC_SHA[$p]:-}"
            done
        fi
    } > "$VERSION_FILE"
fi

# ---------------------------------------------------------------- 汇总

printf '\n汇总: 升级 %d / 合并 %d / 并集 %d / 保留 %d / 冲突 %d / 新增 %d / 删除 %d / 跳过 %d / 未变 %d / 未动 %d\n' \
    "$n_up" "$n_merge" "$n_union" "$n_keep" "$n_conf" "$n_add" "$n_del" "$n_skip" "$n_same" "$n_foreign"

# 「下次还得人工」= 这次两边都动过的文件。数字不落盘就是每次重新猜一遍。
both=$((n_merge + n_conf + n_union + n_stale))
if [ "$both" -gt 0 ]; then
    printf '下次同步预计仍需人工: %d 个（模板与本地都在动）\n' "$both"
    [ "$n_stale" -eq 0 ] && [ "$n_skip" -eq 0 ] && \
        printf '  这些文件如果本来就该「本地说了算」，用 --write --keep-local <路径> 裁决一次，之后不再打扰。\n'
fi
if [ "$n_stale" -gt 0 ]; then
    printf '已裁决但模板又改了（需要重新判断）: %s\n' "${STALE[*]}"
fi

if [ -d "$PROJECT/tasks" ] && [ -n "$(find "$PROJECT/tasks" -mindepth 1 -maxdepth 1 -type d ! -name '_template' ! -name '_archive' 2>/dev/null | head -n 1)" ]; then
    printf '这个项目已有任务历史；模板的新规则会对旧任务全部判红，治理路线见 tasks/README.md 的「闸门升级后的存量违规」。\n'
fi

if [ "$WRITE" -eq 0 ]; then
    printf '\n这是预览，没有写盘。确认后加 --write 执行。\n'
    exit 0
fi

if [ -n "$KEEP_DIR" ]; then
    printf '\n冲突现场: %s\n  每个冲突文件留了 .ours / .base / .theirs，复核或重跑:\n' "$KEEP_DIR"
    printf '  git merge-file -p <f>.ours <f>.base <f>.theirs\n'
fi

if [ "$n_conf" -gt 0 ]; then
    printf '\n有 %d 个文件冲突，搜索 <<<<<<< 处理。' "$n_conf"
    [ "$is_repo" -eq 1 ] && printf ' 看全貌: git -C "%s" diff' "$PROJECT"
    printf '\n'
    exit 1
fi

printf '\n已写盘。下一步:\n'
if [ "$is_repo" -eq 1 ]; then
    printf '  git -C "%s" diff      # 看一眼改了什么\n' "$PROJECT"
    printf '  git -C "%s" status    # .scaffold-version 也要提交\n' "$PROJECT"
else
    printf '  这个项目不是 git 仓库 —— 没有 diff 可看，回滚不了，建议先 git init\n'
fi
exit 0
