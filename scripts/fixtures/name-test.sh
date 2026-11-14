#!/usr/bin/env bash
#
# 项目名校验的一致性验收：同一张名字表分别喂给 init.sh 与 init.ps1，
# 两个脚本必须**同时接受或同时拒绝**（AGENTS.md 硬约束 2 的后半句）。
#
# 为什么需要它：两个脚本的校验规则是两套独立实现，靠人肉保证「接受集完全相同」。
# 已经出现过一次真实差异（init.ps1 放过尾随换行与 C1 控制字符，init.sh 拒绝），
# 而任何一边出错的表现都不一样：bash 侧是清楚的「项目名非法」，PowerShell 侧
# 是一句 .NET 绑定异常。
#
# 用法：bash scripts/fixtures/name-test.sh
# 退出码 0 = 两边一致（或本机没有 PowerShell，跳过）。需要 bash 与 PowerShell。

set -u
trap '' PIPE

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"
INIT_PS1="$REPO_ROOT/init.ps1"

# PowerShell 不认 MSYS 的 `/d/...` 路径（那是 bash 的写法），必须换成 `D:\...`。
# 没有 cygpath 就原样传——那种机器上也没有 PowerShell，走不到这里。
ps_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}
B="${BASH:-bash}"

PS=""
for c in pwsh powershell.exe powershell; do
    if command -v "$c" >/dev/null 2>&1; then PS="$c"; break; fi
done
if [ -z "$PS" ]; then
    echo "跳过：这台机器没有 PowerShell，无法比对 init.ps1 的接受集（这不是失败）"
    exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/name-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sh" "$TMP/ps"

pass=0; fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# 一轮对照：$1=标签 $2=bash 侧的字面量（用 printf 生成，避免 shell 吃掉控制字符）
#            $3=PowerShell 侧的表达式  $4=期望（accept | reject，省略则只比一致性）
#
# 为什么必须有 $4：只比「两边结果相同」，两个脚本**同时放过**一个非法名字也会 PASS。
# 曾经的真实缺陷正是两边一起放过 C1 控制字符——一致性检查对它无能为力。
compare() {
    local label="$1" bash_val="$2" ps_expr="$3" want="${4:-}" r1 r2 a b
    rm -rf "$TMP/sh" "$TMP/ps"; mkdir -p "$TMP/sh" "$TMP/ps"

    ( cd "$TMP/sh" && "$B" "$INIT_SH" "$bash_val" ) >/dev/null 2>&1
    r1=$?
    # 同一张表还要在 LC_ALL=C 下再跑一遍：init.sh 的判定必须与 locale 无关。
    # 真实缺陷正是这样漏掉的——本地 UTF-8 locale 拦下的名字，CI 的 C locale 放行
    # （Windows runner 实测）。只比两边一致性发现不了它，只在一种 locale 下跑也发现不了。
    #
    # 两次之间必须清空目录：上一次接受了就会生成 `<名字>/`，再跑一次 init.sh 会因为
    # 「目录已存在」而拒绝——那是另一条规则，会伪装成 locale 差异（实测踩过一次）。
    rm -rf "$TMP/sh"; mkdir -p "$TMP/sh"
    ( cd "$TMP/sh" && LC_ALL=C "$B" "$INIT_SH" "$bash_val" ) >/dev/null 2>&1
    r1c=$?
    ( cd "$TMP/ps" && "$PS" -NoProfile -ExecutionPolicy Bypass \
        -Command "& '$(ps_path "$INIT_PS1")' $ps_expr" ) >/dev/null 2>&1
    r2=$?

    a=$([ "$r1" -eq 0 ] && echo 接受 || echo 拒绝)
    ac=$([ "$r1c" -eq 0 ] && echo 接受 || echo 拒绝)
    b=$([ "$r2" -eq 0 ] && echo 接受 || echo 拒绝)
    case "$want" in accept) want="接受" ;; reject) want="拒绝" ;; esac
    if [ "$a" != "$ac" ]; then
        no "$label：init.sh 的判定依赖 locale（UTF-8 locale $a，C locale $ac）"
    elif [ "$a" != "$b" ]; then
        no "$label：init.sh $a（exit $r1）但 init.ps1 $b（exit $r2）"
    elif [ -n "$want" ] && [ "$a" != "$want" ]; then
        no "$label：两边都$a，但应当$want"
    else
        ok "$label：两边都$a"
    fi
}

echo "== 名字接受集：init.sh vs init.ps1 =="

# 应当两边都接受
compare "普通 ASCII"            'ok-name'            "'ok-name'" accept
compare "下划线与点"            'a_b.c'              "'a_b.c'" accept
compare "非 ASCII（中文）"      '中文名'             "'中文名'" accept
compare "非 ASCII（希腊字母）"  'αβγ'                "'αβγ'" accept

# 应当两边都拒绝
compare "前导连字符"            '-abc'               "'-abc'" reject
compare "尾随点"                'abc.'               "'abc.'" reject
compare "空格"                  'a b'                "'a b'" reject
compare "斜杠"                  'a/b'                "'a/b'" reject
compare "分号"                  'a;b'                "'a;b'" reject
compare "星号"                  'a*b'                "'a*b'" reject
compare "点目录"                '.'                  "'.'" reject
compare "双点目录"              '..'                 "'..'" reject
compare ".git"                  '.git'               "'.git'" reject
compare "保留设备名 CON"        'CON'                "'CON'" reject
compare "保留设备名 com1.txt"   'com1.txt'           "'com1.txt'" reject
compare "尾随换行"              $'abc\n'             "([string]'abc' + [char]10)" reject
compare "C0 制表符"             $'a\tb'              "([string]'a' + [char]9 + 'b')" reject
# C1 必须用**显式 UTF-8 字节**构造，不能写 `$'a\u0085b'`：bash 在非 UTF-8 locale 下
# 会把 `\u0085` 编成裸字节 0x85（不是 U+0085 的 UTF-8 编码 C2 85），于是同一个用例
# 在不同机器上喂的其实是两种输入——Windows CI 上就是这样被误判成「init.sh 放行」的。
compare "C1 U+0085"             "$(printf 'a\302\205b')" "([string]'a' + [char]0x85 + 'b')" reject
compare "C1 U+009B"             "$(printf 'a\302\233b')" "([string]'a' + [char]0x9B + 'b')" reject

# init.sh 专属：**非法 UTF-8 字节串**必须拒绝。PowerShell 收不到裸字节（argv 会先被
# 解码），所以这里没有对照物，只断言 bash 侧的行为——否则一个 0x85 裸字节在 bash
# 侧被放行、在 ps 侧被解码成 U+0085 后拒绝，「接受集相同」这条就悄悄破了。
for v in "$(printf 'a\205b')" "$(printf 'a\303\050b')"; do
    rm -rf "$TMP/sh"; mkdir -p "$TMP/sh"
    if ( cd "$TMP/sh" && "$B" "$INIT_SH" "$v" ) >/dev/null 2>&1; then
        no "非法 UTF-8 字节串被 init.sh 接受（应当拒绝）"
    else
        ok "非法 UTF-8 字节串被 init.sh 拒绝"
    fi
done

printf '\n结果: PASS %d / FAIL %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
