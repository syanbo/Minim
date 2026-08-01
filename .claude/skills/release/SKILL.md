---
name: release
description: 发布轻图 Minim 的新版本——改版本号、打 DMG、验证 bundle 完整性、创建 GitHub Release。当用户说「发版」「发布 x.y.z」「打个新版本」「出个 release」时使用。
---

# 发布新版本

参数是目标版本号（如 `1.1.0`）。没给就先问，不要猜。

## 前置检查（任何一项不通过就停下来问用户）

```bash
git fetch --tags            # gh release create 只在远端建 tag，本地不会自动有
git status --short          # 必须干净
git log origin/main..HEAD   # 必须为空（已推送）
make test                   # 必须全绿
```

**必须先 `git fetch --tags`**，否则下一步取改动清单时 `git log v<上个版本>..HEAD`
会报 `unknown revision`。

有未提交改动或未推送提交时**不要自作主张提交或推送**，报告给用户让他决定。

## 1. 改版本号

只改一处，`make-dmg.sh` 会自己读：

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString <版本号>" \
                        -c "Set :CFBundleVersion <递增整数>" Resources/Info.plist
```

`CFBundleVersion` 是构建号，每次发布必须比上一次大（macOS 靠它判断新旧）。
用 `PlistBuddy` 而不是 `sed`——plist 是结构化的，`sed` 改多行 key/value 容易写错。

## 2. 打包

```bash
rm -rf dist
make dmg
```

产物是 `dist/Minim-<版本号>.dmg`。

## 3. ⚠️ 验证 bundle 完整性（**这一步不能省**）

`make app` 只要编译过就会成功，但**外部工具没打进去的话，用户下载后压缩功能全挂**。
必须从 DMG 里取出 app、在**没有 Homebrew 的 PATH** 下实际运行四个工具：

```bash
MNT=$(hdiutil attach "dist/Minim-<版本号>.dmg" -nobrowse -readonly | grep -o '/Volumes/.*$' | head -1)
cp -R "$MNT/轻图.app" /tmp/minim-verify/
hdiutil detach "$MNT" -quiet
for t in pngquant oxipng gifsicle apngasm; do
  env -i PATH=/usr/bin:/bin "/tmp/minim-verify/轻图.app/Contents/Helpers/$t" --version
done
codesign --verify --deep --strict "/tmp/minim-verify/轻图.app"
```

注意挂载点解析：卷名是中文「轻图」，`awk '{print $NF}'` 会取错，必须 `grep -o '/Volumes/.*$'`。

四个工具任一报错或签名校验失败 → **停止发布**，报告给用户。

## 4. 提交版本号变更

```bash
git add Resources/Info.plist
git commit -m "chore: 版本号更新为 <版本号>"
git push origin main
```

## 5. 创建 Release

发布说明写进临时文件再传（`--notes` 直接写多行中文容易被 shell 吃掉）：

```bash
gh release create v<版本号> "dist/Minim-<版本号>.dmg" \
  --repo syanbo/Minim \
  --title "轻图 Minim <版本号>" \
  --notes-file /tmp/minim-notes.md
```

**发布说明要简洁**——用户是来下载的，不是来读文档的。控制在 15 行以内：

- `### 新增` / `### 修复` —— 每条一行，只写用户感知得到的变化，不写重构和内部改动
- `### 安装` —— brew 命令 + DMG 说明 + 系统要求 + Gatekeeper 一句话

功能细节放 README，别在这里重复。改动清单从
`git log v<上个版本>..HEAD --oneline` 提取，**不要凭印象编**。

## 6. 核对附件名

```bash
gh release view v<版本号> --repo syanbo/Minim --json assets --jq '.assets[].name'
```

**必须确认是 `Minim-<版本号>.dmg`。** GitHub 会过滤附件名里的非 ASCII 字符——
历史上 `轻图-1.0.0.dmg` 曾被截成 `-1.0.0.dmg`。`make-dmg.sh` 已经改用 ASCII 文件名，
但每次仍要核对，防止有人改回中文名。

若真的出现残缺名，`gh release delete-asset` 对付不了以连字符开头的文件名，走 API：

```bash
ID=$(gh api repos/syanbo/Minim/releases/tags/v<版本号> --jq '.assets[] | select(.name=="<残缺名>") | .id')
gh api -X DELETE "repos/syanbo/Minim/releases/assets/$ID"
```

## 7. ⚠️ 同步 Homebrew cask（**最容易忘的一步**）

不更新的话，`brew upgrade` 的用户永远停在旧版本，而且不会有任何报错——静默失效。

cask 在另一个仓库 [`syanbo/homebrew-tap`](https://github.com/syanbo/homebrew-tap)，
文件是 `Casks/minim.rb`，要改两处：`version` 和 `sha256`。

**sha256 必须取 Release 上那份**（本地重打包过就会不一致，装的人会校验失败）：

```bash
curl -sL "https://github.com/syanbo/Minim/releases/download/v<版本号>/Minim-<版本号>.dmg" -o /tmp/rel.dmg
shasum -a 256 /tmp/rel.dmg
```

改完 `ruby -c Casks/minim.rb` 自检语法，提交推送，然后实测：

```bash
brew update && brew upgrade --cask minim
```

## 8. 收尾

- 确认 README 的 Releases 链接仍然正确（指向 `releases/latest`，通常不用改）
- 报告 Release URL 和附件大小给用户
- 清理 `/tmp/minim-verify`、`/tmp/rel.dmg`

## 不要做的事

- **不要跳过第 3 步**。编译通过不代表 bundle 完整，这是本项目最容易翻车的地方。
- **不要在 CFBundleVersion 上偷懒**，不递增会让 macOS 认不出新版本。
- **不要自动改 README 的功能描述**。发版只管发版；功能文档跟着功能改动走。
