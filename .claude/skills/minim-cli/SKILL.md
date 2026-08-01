---
name: minim-cli
description: 用 minim-cli 压缩和转换图片（PNG / JPG / WebP / GIF / APNG）。当用户说「压一下这些图」「图太大了」「转成 WebP」「批量压缩」「这张图能再小点吗」「GIF 转动图」，或提交前想瘦身图片资源时使用。本地运行、不联网、不上传任何图片。
---

# minim-cli — 本地图片压缩

macOS 原生压缩工具，全程本地，不上传任何文件。

## 第一步：找到二进制（每次都先做，别假设它在）

按顺序探测，找到就用，**都找不到就停下来告诉用户怎么装，不要编一个路径去跑**：

```bash
# 1) 已在 PATH（用户跑过 make install）
command -v minim-cli

# 2) 从本 skill 自身位置回溯到仓库（~/.claude/skills/ 下通常是符号链接，必须 resolve）
SKILL_REAL="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "<本文件路径>")"
REPO="$(dirname "$(dirname "$(dirname "$(dirname "$SKILL_REAL")")")")"
ls "$REPO/.build/release/minim-cli" "$REPO/.build/debug/minim-cli" 2>/dev/null
```

都没有时告诉用户：

> 需要先构建：`cd <Minim 仓库> && make install`（装进 `/usr/local/bin`），
> 或 `swift build -c release` 后用 `.build/release/minim-cli`。

## 安全约束（重要）

- **默认绝不加 `--overwrite`**。它会直接替换用户的源文件、不可撤销。
  只有用户明确说「替换原图 / 覆盖原文件 / 就地压缩」时才用，用之前再确认一次。
- 默认输出到源目录下的 `minim/` 子目录，**文件名保持不变**——整个文件夹压完可以直接
  替换回项目。想放别处用 `-o <目录>`。
- 处理前先报告将影响哪些文件、产物落在哪；批量超过 ~20 张时先说明规模再开跑。
- 不要对用户没提到的文件顺手做压缩。

## 常用配方

```bash
# 批量压缩，产物在各自目录的 minim/ 下
minim-cli assets/*.png assets/*.jpg

# 网页素材：压缩 + 额外出一份 WebP（同名换扩展，可直接配 <picture>）
minim-cli assets/*.png --webp

# 收到一堆 WebP，需要 PNG/JPG 兜底给老浏览器
minim-cli images/*.webp --png --jpg

# 压得狠一点（10% 档），输出到指定目录
minim-cli photo.jpg -q 10 -o /tmp/out

# 不想有任何画质损失
minim-cli logo.png -q lossless

# 限制尺寸：等比缩到 1200 宽以内（高度传 0 = 按原图，且绝不放大）
minim-cli hero.jpg --resize 1200x0

# 固定尺寸缩略图：缩放覆盖后居中裁剪成精确 400×400
minim-cli avatar.jpg --resize-crop 400x400

# GIF 转动画 WebP，抽掉一半帧（总时长不变），1.5 倍速
minim-cli loading.gif --anim webp --keep 1/2 --speed 1.5

# 这张 JPG 之前被压到什么质量？（只读，不产出文件）
minim-cli photo.jpg --detect
```

质量档位 `-q`：`10` / `30` / `50` / `80` / `auto`（默认）/ `lossless`。
`auto` 对 JPG 会先解析量化表估算原图质量再决定输出质量，**已经压过的图不会被重复劣化**。

## 三个转换开关

`--webp` / `--jpg` / `--png` 语义一致：**额外输出一份该格式，不替换主输出**。

| 开关 | 对哪些输入生效 | 产出 |
| --- | --- | --- |
| `--webp` | PNG · JPG | `名字.webp` |
| `--jpg` | PNG · 静态 WebP | `名字-jpg.jpg`（透明填白底） |
| `--png` | JPG · 静态 WebP | `名字-png.png`（真无损、保留透明） |

目标格式与输入格式相同时自动跳过；动图一律不适用。

## 读懂输出（这些不是失败）

```
photo.jpg: 340 KB → 96 KB (-71.8%)              正常
icon.png: 12 KB → 12 KB (-0.0%) [已最优，保留原图]   ← 压不动，保留了原图，不是错误
hero.webp: ... [已最优，保留原图]                  ← 静态 WebP 省不足 10% 时刻意保留
banner.png: ...  WebP: 已跳过（会覆盖同名文件）      ← 同目录已有 banner.webp，为防误删而跳过
```

- **「已最优，保留原图」不是失败**。压缩结果不比原图小时会保留原文件。
- 静态 WebP 另有一条规则：**省下不足 10% 就保留原图**——WebP 没有可解析的质量元数据，
  反复重编码会持续劣化，所以宁可不动。
- **「已跳过（会覆盖同名文件）」**说明转换产物的文件名会撞上参数里的另一个输入文件，
  为免误删而跳过。想要的话把冲突文件挪开，或用 `-o` 输出到别处。

## 陷阱

- **动图在 CLI 里是直接处理的**，没有图形界面那种「先看信息再点开始」的确认步骤。
  给 GIF 加 `--anim` 前先跟用户确认输出格式和抽帧比例。
- **抽帧不改变总时长**：`--keep 1/2` 是删掉一半帧、剩下的帧各自延长，动画时长不变。
  想让它变快用 `--speed`，两者独立。
- 未知选项会直接报错退出（不会被当成文件路径），拼错了看报错就行。

## 维护

本文件真身在 **Minim 仓库的 `.claude/skills/minim-cli/`**，随仓库版本控制——
改 CLI 参数时请在同一个 commit 里更新它。

`~/.claude/skills/minim-cli` 若存在，是指向这里的**符号链接**（本机状态，不进 Git）。
换机器或重装后需要重新链接：

```bash
ln -s <Minim 仓库>/.claude/skills/minim-cli ~/.claude/skills/minim-cli
```
