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
# 约定: templates/ 顶层的 prd.md / plan.md / journal.md 是任务模板，落到 tasks/_template/。
(cd "$TEMPLATE_DIR" && find . -type f | sed 's|^\./||' | sort) | while IFS= read -r src; do
    case "$src" in
        prd.md|plan.md|journal.md) dst="tasks/_template/$src" ;;
        *)                         dst="$src" ;;
    esac
    mkdir -p "$TARGET_DIR/$(dirname "$dst")"
    cp "$TEMPLATE_DIR/$src" "$TARGET_DIR/$dst"
done

if [ ! -f "$TARGET_DIR/AGENTS.md" ]; then
    echo "错误: 模板复制失败，$TEMPLATE_DIR 下没有 AGENTS.md"
    exit 1
fi

# 替换项目名占位符
for f in "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/README.md"; do
    if [ -f "$f" ]; then
        sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$f" 2>/dev/null || \
        sed -i '' "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$f"
    fi
done

# 初始化 git
cd "$TARGET_DIR"
git init >/dev/null 2>&1

echo ""
echo "项目 '$PROJECT_NAME' 创建成功!"
echo ""
echo "下一步:"
echo "  cd $PROJECT_NAME"
echo "  1. 初始化技术栈 (npm init, create-next-app, uv init 等)"
echo "  2. 让本地 Agent 帮你填写 AGENTS.md、CONTEXT.md 和 docs/"
echo "  3. git add . && git commit -m 'init: 项目脚手架 + 技术栈'"
