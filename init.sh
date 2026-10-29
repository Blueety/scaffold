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
# 允许：ASCII 字母数字、点、下划线、连字符，以及中文等非 ASCII 字节（UTF-8 原样透传）。
# 拒绝：路径分隔符、空白、控制字符和 shell/sed 元字符——它们会破坏 cp/sed 或造成路径穿越。
# 用 tr 做「补集删除」而不是字符类取反：不依赖 locale，LC_ALL=C 下同样正确。
reject_project_name() {
    echo "错误: 项目名 '$PROJECT_NAME' 非法"
    echo '允许字母、数字、点、下划线、连字符和中文；不能是 . / .. / .git，也不能以 - 开头。'
    echo '也不能含空格、引号、反斜杠、/ 或 & $ ` ; | < > ( ) * ? 等元字符。'
    exit 1
}

case "$PROJECT_NAME" in
    ""|.|..|.git|-*) reject_project_name ;;
esac
if [ -n "$(printf '%s' "$PROJECT_NAME" | LC_ALL=C tr -d 'A-Za-z0-9._\200-\377-')" ]; then
    reject_project_name
fi

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
    tmp="$(mktemp)"
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
cd "$TARGET_DIR"
if ! git_init_err="$(git init 2>&1 >/dev/null)"; then
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
if ! git config core.quotepath false; then
    echo "错误: 设置 core.quotepath=false 失败"
    echo "手动执行: cd $TARGET_DIR && git config core.quotepath false"
    exit 1
fi

echo ""
echo "项目 '$PROJECT_NAME' 创建成功!"
echo ""
echo "下一步:"
echo "  cd $PROJECT_NAME"
echo "  1. 初始化技术栈 (npm init, create-next-app, uv init 等)"
echo "  2. 让本地 Agent 帮你填写 AGENTS.md、CONTEXT.md 和 docs/"
echo "  3. git add . && git commit -m 'init: 项目脚手架 + 技术栈'"
