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
bash scripts/fixtures/gate-test.sh     # 106 项
bash scripts/fixtures/update-test.sh   # 55 项
bash scripts/fixtures/name-test.sh     # 19 项（项目名接受集；没有 PowerShell 的机器会跳过）
```

提交时 `.githooks/pre-commit` 会自动跑第一项（全量，约 20 秒）。被拦下就修，**不要**用 `git commit --no-verify` 绕过。

非 Windows 机器跑不了 `check-tree.ps1`（脚本自身拒绝非 Windows，`exit 3`，与有没有 `pwsh` 无关）——`templates/` 与 `init.sh` 产物的逐字节比对与三个 fixture 在 CI 里跑，见 `.github/workflows/check.yml`。PR 上看到 CI 红就是这条不变量破了。

## 提交信息

一个提交一件事，写清**为什么**（不是「改了什么」——`git diff` 已经说了）。修缺陷时带上复现方式。

## 许可

提交即表示同意以 [MIT](LICENSE) 发布你的贡献。
