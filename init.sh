#!/usr/bin/env bash
# 项目初始化脚本 (Linux / macOS / WSL)
# 用法: bash init.sh <项目名称>
# 示例: bash init.sh my-app

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "用法: bash init.sh <项目名称>"
    echo "示例: bash init.sh my-app"
    exit 1
fi

PROJECT_NAME="$1"

# 校验项目名。
# 允许：ASCII 字母数字、点、下划线、连字符，以及中文等非 ASCII 字符（UTF-8 原样透传）。
# 拒绝：路径分隔符、空白、控制字符和 shell/sed 元字符——它们会破坏 cp/sed 或造成路径穿越；
#       也拒绝尾随的点，因为 Windows 会把它规范化掉，导致 mkdir 与后续路径落到不同目录。
# 规则与 init.ps1 保持一致，两边接受集必须相同。
reject_project_name() {
    echo "错误: 项目名 '$PROJECT_NAME' 非法"
    echo '允许字母、数字、点、下划线、连字符和中文等非 ASCII 字符；不能是 . / .. / .git（不分大小写），'
    echo '不能以 - 开头或以 . 结尾，也不能含空格、引号、反斜杠、/ 或 & $ ` ; | < > ( ) * ? 等元字符。'
    exit 1
}

# 控制字符逐字节挡：**不用 `[[:cntrl:]]`**。那个字符类是 locale 相关的——UTF-8
# locale 下按字符判，C locale 下按字节判，于是同一个名字在两台机器上得到相反结论
# （实测：Windows CI 上 U+0085 / U+009B 被放行，本地被拦下）。这份集合与 init.ps1
# 的 `[\x00-\x1F\x7F-\x9F]` 一一对应：C0 与 DEL 是单字节；C1（U+0080–U+009F）在
# UTF-8 里是 `0xC2` 后跟 `0x80–0x9F`，所以按两字节序列挡。
#
# 字节用 `printf -v` 落到变量，**不能**写成 `$(printf ...)`：命令替换会吃掉结尾
# 换行，0x0A 会变成空串，而 `*""*` 在 case 里匹配一切——一个换行条目就能把整批
# 合法名字误杀（实测）。
case "$PROJECT_NAME" in
    "") reject_project_name ;;
esac
octet() { printf -v OCTET "\\$(printf '%o' "$1")"; }
controls=()
_i=1
while [ "$_i" -le 31 ]; do
    octet "$_i"; controls+=("$OCTET")
    _i=$((_i + 1))
done
octet 127; controls+=("$OCTET")
# 十进制边界：`[ ]` 的 -le 不是算术上下文，`0200` 在那里是 200。写成八进制会让
# 循环多跑 3 倍、还会把 0xA0 之后的第二字节也造进表里。
_i=128
while [ "$_i" -le 159 ]; do
    octet "$_i"; controls+=("$(printf '\302')$OCTET")
    _i=$((_i + 1))
done
for _ch in "${controls[@]}"; do
    case "$PROJECT_NAME" in
        *"$_ch"*) reject_project_name ;;
    esac
done

# .git 不分大小写：Windows 的文件名不区分大小写，.GIT 和 .git 是同一个东西。
# 保留设备名同理：Windows 上 CON/NUL/COM1 之类的名字建不出普通目录（Git Bash 下
# mkdir 会留下一个设备项）。取第一个点之前的部分来判断，CON.txt 也是设备名。
# COM0/LPT0 也算：实测 Windows 会把 com0 改名，建出来的目录不是你要的那个名字。
lower_name="$(printf '%s' "$PROJECT_NAME" | LC_ALL=C tr 'A-Z' 'a-z')"
case "$lower_name" in
    .|..|.git|-*|*.) reject_project_name ;;
esac
case "${lower_name%%.*}" in
    con|prn|aux|nul|com[0-9]|lpt[0-9]) reject_project_name ;;
esac

if [ -n "$(printf '%s' "$PROJECT_NAME" | LC_ALL=C tr -d 'A-Za-z0-9._\200-\377-')" ]; then
    reject_project_name
fi

# 不可见 / Unicode 空白：NBSP、软连字符、零宽字符（U+2000–U+200F）、行段分隔符、
# 窄 NBSP、词连接符、表意空格、BOM。粘贴来的名字常混进这些——建出来的目录
# 看不见，也打不回去。只要**含有**就拦，不限于整名都是它。
# 这份集合必须与 init.ps1 的字符类一一对应。
# 用八进制字节转义而不是 `$'\uXXXX'`：后者依赖 locale，在 LC_ALL=C 下会转出
# 完全不同的字节（实测会把合法中文名误判为非法）。八进制是逐字节的，与 locale 无关。
invisible=(
    $'\302\240' $'\302\255' $'\342\200\250' $'\342\200\251' $'\342\200\257'
    $'\342\201\237' $'\342\201\240' $'\343\200\200' $'\357\273\277'
)
# 用算术 while 而不是 `seq`：少一个外部命令依赖（每个依赖都是一个平台差异面）。
_i=0
while [ "$_i" -le 15 ]; do
    invisible+=("$(printf '\342\200'; printf "\\$(printf '%o' $((0200 + _i)))")")
    _i=$((_i + 1))
done
for _ch in "${invisible[@]}"; do
    case "$PROJECT_NAME" in
        *"$_ch"*) reject_project_name ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)/$PROJECT_NAME"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

# 检查目标目录是否已存在
if [ -d "$TARGET_DIR" ]; then
    echo "错误: 目录 '$PROJECT_NAME' 已存在"
    exit 1
fi

# 检查模板目录是否存在
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "错误: 找不到模板目录 '$TEMPLATE_DIR'"
    exit 1
fi

echo "正在创建项目: $PROJECT_NAME"

# 创建目录结构（src 没有模板文件，单独建）
mkdir -p "$TARGET_DIR/src"

# 复制模板文件。
# 文件清单从 templates/ 自身遍历得出，不硬编码：新增模板无需改脚本，
# 也避免在脚本里写中文文件名（不同平台的编码/区域设置会破坏字面量）。
# templates/ 的目录结构与生成结果一一对应，脚本不做任何重映射。
(cd "$TEMPLATE_DIR" && find . -type f | sed 's|^\./||' | sort) | while IFS= read -r src; do
    mkdir -p "$TARGET_DIR/$(dirname "$src")"
    cp "$TEMPLATE_DIR/$src" "$TARGET_DIR/$src"
done

if [ ! -f "$TARGET_DIR/AGENTS.md" ]; then
    echo "错误: 模板复制失败，$TEMPLATE_DIR 下没有 AGENTS.md"
    exit 1
fi

# 替换项目名占位符（遍历全部模板文件，不硬编码文件名）。
# 用 sed 写到临时文件再写回，避开 GNU/BSD 的 sed -i 差异，失败时能看到原因。
while IFS= read -r f; do
    tmp="$(mktemp "${TMPDIR:-/tmp}/scaffold.XXXXXX")"
    if ! sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$f" > "$tmp"; then
        echo "错误: 替换占位符失败: $f"
        rm -f "$tmp"
        exit 1
    fi
    if ! cat "$tmp" > "$f"; then
        echo "错误: 写回失败: $f"
        rm -f "$tmp"
        exit 1
    fi
    rm -f "$tmp"
done < <(find "$TARGET_DIR" -type f)

# 初始化 git。断言真的建出来了，不把失败当成功。
#
# 一律用 git -C "$TARGET_DIR"，不 cd 进去：Windows 会规范化尾随点之类的路径，
# cd 可能落到调用者的目录，于是 git init 在调用者的目录里建出一个游离仓库。
if ! git_init_err="$(git -C "$TARGET_DIR" init 2>&1 >/dev/null)"; then
    echo "错误: git init 失败"
    if [ -n "$git_init_err" ]; then printf '%s\n' "$git_init_err" | sed 's/^/  /'; fi
    echo "项目文件已创建在 $TARGET_DIR，但没有初始化 git 仓库。"
    echo "确认 git 已安装后重试: cd $TARGET_DIR && git init"
    exit 1
fi
if [ ! -d "$TARGET_DIR/.git" ]; then
    echo "错误: git init 未报错，但 $TARGET_DIR/.git 不存在"
    exit 1
fi

# 关掉路径转义。core.quotepath 默认 true，git 会把非 ASCII 路径转成八进制再加引号
# （本脚手架自带 docs/agents/架构师.md 等中文文件名），Agent 拿到这种路径没法直接用。
#
# 同时启用随项目分发的 git 钩子：.git/hooks 不受版本控制，所以钩子放在 .githooks/，
# 用 core.hooksPath 指过去。不设这一步，闸门检查就只是一次性的。
set_git_config() {
    if ! git -C "$TARGET_DIR" config "$1" "$2"; then
        echo "错误: 设置 $1=$2 失败"
        echo "手动执行: cd $TARGET_DIR && git config $1 $2"
        exit 1
    fi
}
set_git_config core.quotepath false
set_git_config core.hooksPath .githooks

# 钩子和检查脚本要有可执行位，并且要把这个位记进 git 索引：cp 不保留权限，
# 而 Windows 上 git add 会记成 100644，之后 clone 到 Linux/macOS 时 git 会因为
# 钩子不是可执行文件而静默跳过它。
while IFS= read -r f; do
    rel="${f#"$TARGET_DIR"/}"
    if ! chmod +x "$f"; then
        echo "错误: 加可执行位失败: $rel"
        exit 1
    fi
    if ! git -C "$TARGET_DIR" add --chmod=+x -- "$rel"; then
        echo "错误: 记录可执行位失败: $rel"
        exit 1
    fi
done < <(find "$TARGET_DIR/scripts" "$TARGET_DIR/.githooks" -type f | sort)

echo ""
echo "项目 '$PROJECT_NAME' 创建成功!"
echo ""
echo "下一步:"
echo "  cd $PROJECT_NAME"
echo "  1. 初始化技术栈 (npm init, create-next-app, uv init 等)"
echo "  2. 让本地 Agent 帮你填写 AGENTS.md、CONTEXT.md 和 docs/"
echo "  3. git add . && git commit -m 'init: 项目脚手架 + 技术栈'"
