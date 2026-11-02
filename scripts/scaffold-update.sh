#!/usr/bin/env bash
#
# >>> usage
# 脚手架更新器 —— 把已经生成的项目里的脚手架文件升级到当前版本。
#
#   bash scripts/scaffold-update.sh <项目目录>                预览，不写盘
#   bash scripts/scaffold-update.sh <项目目录> --write        真正写盘
#   bash scripts/scaffold-update.sh <项目目录> --from <sha>   指定基线版本
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
# 基线从哪来（按优先级）：
#   1. --from <sha>
#   2. 项目根的 .scaffold-version 里记的 commit（本脚本更新成功后写入）
#   3. 都没有 → 拿项目内容和脚手架历史逐个比对，挑最像的那个版本，并报匹配度
#
# 只碰 templates/ 里出现过的路径：src/、tasks/<任务>/、.git/ 一概不动。
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
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --write)   WRITE=1 ;;
        --dry-run) WRITE=0 ;;
        --from)    shift; [ "$#" -gt 0 ] || die "--from 需要一个提交"; FROM="$1" ;;
        --from=*)  FROM="${1#--from=}" ;;
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
if [ -f "$VERSION_FILE" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            project_name) [ -n "$PROJECT_NAME" ] || PROJECT_NAME="$v" ;;
            commit)       [ -n "$BASE_COMMIT" ] || BASE_COMMIT="$v" ;;
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
#   - 项目侧哈希一次 `hash-object --stdin-paths` 算完，不是每文件一次
#   - 占位符文件一次 grep 找出来，不是每文件一次
# 剩下的成本是每个历史版本一次 `ls-tree`（46 个版本约 5 秒）。只在不带
# .scaffold-version 的旧项目上跑一次，之后都走记录里的提交。
#
# 带 {{PROJECT_NAME}} 的文件不参与：模板展开后必然和项目对不上，那是占位符替换的
# 结果，不是版本差异。用剩下的文件打分，项目自己改过的文件只会拉低一点分数。
autodetect_base() {
    local c meta p rel sha pct total score best="" best_pct=-1
    local -A proj=() skip=()
    local -a paths=()

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

    # 一次进程算完项目侧所有哈希（stdin 一行一个路径，输出顺序与输入一致）
    local i=0
    while IFS= read -r sha; do
        proj["${paths[$i]}"]="$sha"
        i=$((i + 1))
    done < <( cd "$PROJECT" && printf '%s\n' "${paths[@]}" | git hash-object --stdin-paths 2>/dev/null )

    while IFS= read -r c; do
        [ -n "$c" ] || continue
        total=0
        score=0
        while IFS=$'\t' read -r meta p; do
            rel="${p#templates/}"
            [ -n "${proj[$rel]+x}" ] || continue
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

# ---------------------------------------------------------------- 逐文件

n_up=0 n_keep=0 n_merge=0 n_conf=0 n_add=0 n_del=0 n_same=0 n_foreign=0

is_repo=0
git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 && is_repo=1

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

while IFS= read -r p; do
    [ -n "$p" ] || continue
    b="$WORK/base/$p"
    t="$WORK/theirs/$p"
    o="$PROJECT/$p"

    has_b=0; [ -f "$b" ] && has_b=1
    has_t=0; [ -f "$t" ] && has_t=1
    has_o=0; [ -f "$o" ] && has_o=1

    # 模板删掉了这个文件
    if [ "$has_t" -eq 0 ]; then
        [ "$has_o" -eq 1 ] || continue                      # 项目也没有：无事
        if cmp -s "$o" "$b"; then
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
            if cmp -s "$o" "$t"; then
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
        if cmp -s "$b" "$t"; then
            printf '  保留   %s（本地已删除，模板没动）\n' "$p"
            n_keep=$((n_keep + 1))
        else
            printf '  保留   %s（本地已删除，模板有改动 —— 自己判断要不要恢复）\n' "$p"
            n_keep=$((n_keep + 1))
        fi
        continue
    fi

    if cmp -s "$o" "$t"; then
        n_same=$((n_same + 1))
    elif cmp -s "$o" "$b"; then
        printf '  升级   %s\n' "$p"
        n_up=$((n_up + 1))
        if [ "$WRITE" -eq 1 ]; then cat "$t" > "$o"; mark_exec "$p"; fi
    elif cmp -s "$t" "$b"; then
        printf '  保留   %s（本地改过，模板没动）\n' "$p"
        n_keep=$((n_keep + 1))
    else
        merged="$WORK/merged"
        if git merge-file -p -L local -L scaffold-base -L scaffold-new "$o" "$b" "$t" > "$merged"; then
            printf '  合并   %s\n' "$p"
            n_merge=$((n_merge + 1))
            if [ "$WRITE" -eq 1 ]; then cat "$merged" > "$o"; mark_exec "$p"; fi
        else
            printf '  冲突   %s（已写冲突标记）\n' "$p"
            n_conf=$((n_conf + 1))
            if [ "$WRITE" -eq 1 ]; then cat "$merged" > "$o"; mark_exec "$p"; fi
        fi
    fi
done < <(
    { [ -d "$WORK/base" ] && ( cd "$WORK/base" && find . -type f | sed 's|^\./||' )
      ( cd "$WORK/theirs" && find . -type f | sed 's|^\./||' )
    } | sort -u
)

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
    {
        printf 'scaffold=%s\n' "$SCAFFOLD_ROOT"
        printf 'project_name=%s\n' "$PROJECT_NAME"
        printf 'commit=%s\n' "$record"
        printf 'updated=%s\n' "$(date +%Y-%m-%d)"
    } > "$VERSION_FILE"
fi

# ---------------------------------------------------------------- 汇总

printf '\n汇总: 升级 %d / 合并 %d / 保留 %d / 冲突 %d / 新增 %d / 删除 %d / 未变 %d / 未动 %d\n' \
    "$n_up" "$n_merge" "$n_keep" "$n_conf" "$n_add" "$n_del" "$n_same" "$n_foreign"

if [ "$WRITE" -eq 0 ]; then
    printf '\n这是预览，没有写盘。确认后加 --write 执行。\n'
    exit 0
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
