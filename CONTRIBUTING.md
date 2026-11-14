# 参与贡献

先读 [`AGENTS.md`](AGENTS.md)——那是这个仓库的硬约束，尤其是这三条：

1. `templates/` 必须**纯 LF**（一个 CR 会让两个 init 脚本产出不同的项目）；
2. `init.sh` 与 `init.ps1` 的项目名接受/拒绝集**完全一致**，产物**逐字节相同**；
3. `README.md` 里那棵树是**唯一真源**，`templates/` 和两个脚本的产物都向它对齐。

生成出来的项目那套规则（任务分级、闸门、审查）**不适用于本仓库**，别把它们当贡献指南。

## 改完要跑

```powershell
# Windows（权威检查：README 树 == templates/ == 两个脚本产物）
powershell -ExecutionPolicy Bypass -File scripts/check-tree.ps1

# 改过闸门检查器或更新器时，另跑对应验收
bash scripts/fixtures/gate-test.sh     # 闸门判据，约 20–30 分钟
bash scripts/fixtures/update-test.sh   # 更新器，约 2–4 分钟
bash scripts/fixtures/name-test.sh     # 项目名接受集，约 1 分钟（没有 PowerShell 的机器会跳过）
# 项数不写在这里：它每加一条断言就漂一次（闸门 check_doc_counts 会拦）。
# 真实数字看各自的收尾输出（PASS n / FAIL m）。
```

只改了 `templates/` 里任何东西（哪怕一行文档）时，第一个会红的是 `gate-test.sh` 的 **`G-pristine`**：它在全新生成的项目上跑全量与 `--staged`，要求**零违规**。这条是为了兜「模板里新增了一个会被判断链的示例名 / 一句会被判成占位符的话」——那种错只有真的生成一个项目才看得见。

提交时 `.githooks/pre-commit` 会自动跑第一项（全量，约 20 秒）。被拦下就修，**不要**用 `git commit --no-verify` 绕过。

非 Windows 机器跑不了 `check-tree.ps1`（脚本自身拒绝非 Windows，`exit 3`，与有没有 `pwsh` 无关）——`templates/` 与 `init.sh` 产物的逐字节比对与三个 fixture 本该在 CI 里跑，见 `.github/workflows/check.yml`。**那三组 job 在第一次 push 之前没跑过**（仓库此前没有 remote），所以在 macOS / Linux 上改这些东西时，本地能跑多少就跑多少；推上去之后以 Actions 结果为准。

## 提交信息

一个提交一件事，写清**为什么**（不是「改了什么」——`git diff` 已经说了）。修缺陷时带上复现方式。

## 许可

提交即表示同意以 [MIT](LICENSE) 发布你的贡献。
