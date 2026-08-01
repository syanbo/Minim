---
name: release
description: 发布轻图 Minim 的新版本——改版本号、写 CHANGELOG、推 tag，剩下的打包/验证/建 Release/同步 cask 由 CI 完成。当用户说「发版」「发布 x.y.z」「打个新版本」「出个 release」时使用。
---

# 发布新版本

参数是目标版本号（如 `1.2.0`）。没给就先问，不要猜。

**打包、验证、建 Release、同步 Homebrew cask 都由 `.github/workflows/release.yml` 完成**，
触发条件是推送 `v*` tag。人工只做四件机器做不了的事：定版本号、写 CHANGELOG、推 tag、验收。

**不要在本地 `gh release create`**，会和 CI 抢同一个 tag。

## 前置检查（任何一项不通过就停下来问用户）

```bash
git fetch --tags            # 本地 tag 必须是最新的，否则取改动清单会报 unknown revision
git status --short          # 必须干净
git log origin/main..HEAD   # 必须为空（已推送）
make test                   # 必须全绿
```

有未提交改动或未推送提交时**不要自作主张提交或推送**，报告给用户让他决定。

## 1. 改版本号

只改一处，`make-dmg.sh` 和 CI 都从这里读：

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString <版本号>" \
                        -c "Set :CFBundleVersion <递增整数>" Resources/Info.plist
```

`CFBundleVersion` 是构建号，每次发布必须比上一次大（macOS 靠它判断新旧）。
用 `PlistBuddy` 而不是 `sed`——plist 是结构化的，`sed` 改多行 key/value 容易写错。

**tag 与 `CFBundleShortVersionString` 不一致时 CI 第一步就会红**，这是刻意的。

## 2. 写 CHANGELOG（**发布说明就是从这里取的**）

在 `CHANGELOG.md` 顶部加一节 `## [<版本号>] - YYYY-MM-DD`，底部补上链接引用。
CI 会抠出这一节当 Release 说明，**没有对应小节直接构建失败**。

- `### 新增` / `### 修复` —— 每条一行，只写用户感知得到的变化，不写重构和内部改动
- 控制在 15 行以内；功能细节放 README，别在这里重复
- 改动清单从 `git log v<上个版本>..HEAD --oneline` 提取，**不要凭印象编**
- 安装说明（brew 命令 / DMG / 系统要求 / Gatekeeper）由 CI 自动追加，**不用写进 CHANGELOG**

## 3. 提交并推送

```bash
git add Resources/Info.plist CHANGELOG.md
git commit -m "chore: 版本号更新为 <版本号>"
git push origin main
```

## 4. 打 tag 触发发版

```bash
git tag v<版本号>
git push origin v<版本号>
```

CI 随即完成：校验版本号一致 → `make dmg` → 挂载 DMG 取出 .app 跑
`scripts/verify-bundle.sh`（四个工具 + 签名）→ 建 Release 传包 → 核对附件名是 ASCII →
下载 Release 上那份 DMG 算 sha256 → 更新 `syanbo/homebrew-tap` 的 `Casks/minim.rb`。

## 5. 盯 CI

```bash
gh run watch "$(gh run list --workflow=Release --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```

红了先看是哪一步，**不要绕过 CI 手动发布**：

| 失败步骤 | 多半是 |
| --- | --- |
| 校验版本号与 tag 一致 | Info.plist 忘改，或 tag 打错 |
| 验证 bundle 完整性 | 工具没打进 bundle / 签名坏了，**这是最该拦住的情况** |
| 生成发布说明 | CHANGELOG 里没有该版本的小节 |
| 同步 Homebrew cask | 缺 `TAP_TOKEN`，或 tap 仓库的 cask 格式变了 |

改完重来要先删 tag：`git tag -d v<版本号> && git push --delete origin v<版本号>`，
Release 若已建出来也要 `gh release delete v<版本号>`。

## 6. 验收

```bash
gh release view v<版本号> --json assets --jq '.assets[] | "\(.name) \(.size)"'
brew update && brew upgrade --cask minim
```

报告 Release URL 和附件大小给用户。

## 一次性配置

cask 同步需要本仓库有 secret **`TAP_TOKEN`**：一个对 `syanbo/homebrew-tap` 有
`contents: write` 的细粒度 PAT。缺了这一步 CI 的 cask job 会红（刻意不静默跳过——
cask 不更新的话 `brew upgrade` 的用户会永远停在旧版本且没有任何报错）。

## 不要做的事

- **不要跳过 CI 自己打包发布**。bundle 完整性验证是本项目最容易翻车的地方，
  那一步在 CI 里是强制的。
- **不要在 CFBundleVersion 上偷懒**，不递增会让 macOS 认不出新版本。
- **不要手动改 tap 仓库的 cask**，CI 会覆盖。
- **不要自动改 README 的功能描述**。发版只管发版；功能文档跟着功能改动走。
