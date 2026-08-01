# 轻图 Minim

macOS 原生图片压缩工具。拖进来，压好的图就在旁边的 `minim/` 文件夹里，**文件名一个不变**——
整个文件夹压完可以直接替换回项目。

SwiftUI 编写，原生 Apple Silicon（arm64），支持深色模式，**压缩全程在本地完成，
不上传任何图片**。唯一的网络请求是检查新版本（读取 GitHub 上公开的 Release 信息），
可在菜单里关掉，详见[更新](#更新)。

- **macOS 14+ / Apple Silicon**
- 支持输入：PNG · JPG · WebP · GIF · APNG
- 图形界面 + 命令行（`minim-cli`）

## 安装

**Homebrew**（推荐，以后跟着 `brew upgrade` 一起更新）：

```bash
brew install --cask syanbo/tap/minim
```

**或**从 [Releases](https://github.com/syanbo/Minim/releases/latest) 下载 DMG，拖进「应用程序」。

两种方式都不需要额外装压缩工具 —— pngquant / oxipng / gifsicle / apngasm 已经打进
app bundle。

首次打开若提示「无法验证开发者」，在「系统设置 → 隐私与安全性」里点「仍要打开」
（ad-hoc 签名，未做公证）。

## 更新

「轻图」菜单里有两项：

- **检查更新…** —— 手动查一次
- **启动时自动检查更新** —— 默认开启，**每天最多查一次**；不想联网就关掉它

检查只做一件事：请求 GitHub 上这个仓库公开的 Release 信息，比对版本号。
**不发送任何图片、文件路径或使用数据**，也不会自动下载或安装。发现新版只是提示你，
点「前往下载」会打开 Releases 页面，装不装由你决定。

这是整个 App 唯一的网络请求，实现在
[`UpdateChecker.swift`](Sources/MinimApp/UpdateChecker.swift)，可自行核对。

## 压缩策略

每种格式走各自最合适的链路，不是一套参数打天下：

| 格式 | 处理方式 |
| --- | --- |
| **JPG** | 解析量化表（DQT）估算原图质量，按映射表决定输出质量——**已经压过的图不会被重复劣化** |
| **PNG** | pngquant 有损量化（转 png8）→ oxipng 无损优化；已是索引色或「保真」档只走无损 |
| **GIF** | gifsicle `-O3` + 按档位 `--lossy` |
| **WebP** | ImageIO 解码 + libwebp 重编码，无损/有损双候选取更优 |

质量档位：`10% / 30% / 50% / 80% / 默认 / 保真`。

两条兜底规则：

- 压缩结果不比原图小时**自动保留原图**，标记「已最优」
- 静态 WebP 没有可解析的质量元数据，所以**省下不足 10% 时保留原图**——避免已优化过的
  WebP 反复处理造成代际劣化

## 三个转换开关

工具条上的 `WebP` / `JPG` / `PNG` 语义完全一致：**额外输出一份该格式，不替换主输出**。
想同时要哪几种，就勾哪几个。

| 开关 | 对哪些输入生效 | 产出 |
| --- | --- | --- |
| **WebP** | PNG · JPG | `名字.webp`（同名换扩展） |
| **JPG** | PNG · 静态 WebP | `名字-jpg.jpg`（透明部分平铺白底） |
| **PNG** | JPG · 静态 WebP | `名字-png.png`（真无损、保留透明，不受质量档影响） |

- 目标格式与输入格式相同时自动跳过（PNG 不会再出一份 PNG）
- 动图一律不适用
- 目标文件名会覆盖列表中已有的图片时（例如同目录下已经有 `名字.webp`），
  **跳过并在行内提示**，不会误删你自己的文件

## 输出位置

默认输出到源目录下的 `minim/` 文件夹，文件名保持不变。拖入文件夹时会自动跳过 `minim`
目录，不会把自己的产物再压一遍。

也可以切到「替换原图」模式（不保留原图，只对之后添加的图片生效）。

## 裁剪缩放

设定宽 × 高后二选一：

- **等比缩放** —— 缩到框内，不变形
- **居中裁剪** —— 缩放覆盖后裁出精确尺寸

超过原图的维度按原图处理（**不放大**）。GIF 用 gifsicle 缩放，动图帧完整保留。

## 动图

动图（GIF / 动图 WebP / APNG）拖进来**不会自动开始**——先展示帧数、时长、循环次数、尺寸，
你在行内设好参数再点「开始」。多个待开始时状态栏可以「全部开始」。

行内可调：

| 参数 | 选项 |
| --- | --- |
| 输出格式 | GIF 压缩 / 动画 WebP / APNG（无损） |
| 抽帧 | 每 N 帧保留 K 帧，**总时长不变** |
| 速度 | 倍速播放，与抽帧解耦 |
| 循环 | 保留原设置 / 无限 / 自定义次数 |

动画 WebP 用 libwebp 的 `WebPAnimEncoder` 进程内编码，APNG 走 apngasm 差分装配，
两者都会逐帧套用「裁剪缩放」。

行内改过的参数会被记住，作为下次拖入动图的默认值。

## 不自动重跑

这是刻意的设计：**任何设置变更都不会自动重压已完成的任务**。

- 工具条设置改了 → 状态栏出现「重新生成（N）」，你点了才执行
- 动图参数改了 → 该行出现「重试」

免得一不小心把一批已经满意的产物覆盖掉。所有选项都会自动记忆，重启后保留。

## 命令行

```
用法: minim-cli <图片文件...> [选项]
  -q <10|30|50|80|auto|lossless>   质量档位（默认 auto）
  --webp                           额外生成一份 WebP（GIF / WebP 输入除外）
  --jpg                            额外生成一份 JPG（PNG / 静态 WebP 输入，透明填白底）
  --png                            额外生成一份无损 PNG（JPG / 静态 WebP 输入）
  -o <目录>                        输出到指定目录（默认输出到源目录下的 minim 文件夹）
  --overwrite                      覆盖源文件
  --resize <宽x高>                 等比缩放到框内（0 表示该维度按原图，不放大）
  --resize-crop <宽x高>            缩放覆盖后居中裁剪成精确宽x高
  --anim <webp|apng>               动图（GIF/动图WebP）转出动画 WebP 或 APNG
  --keep <K/N>                     抽帧：每 N 帧保留 K 帧（如 1/2 删一半、1/4 只留 25%）
  --frame-step <N>                 抽帧旧写法：每 N 帧删 1（等价 --keep N-1/N）
  --speed <倍数>                   播放速度（如 1.5；默认 1 原速，与抽帧独立）
  --loops <N>                      循环次数（0 = 无限；默认保留原图设置）
  --detect                         只检测 JPEG 质量，不压缩
```

装进 PATH（默认 `~/.local/bin`，不需要 sudo）：

```bash
make install                      # 或 make install PREFIX=/usr/local（需 sudo）
make uninstall
```

> 注意：这样安装的 `minim-cli` 依赖 Homebrew 的 pngquant / oxipng / gifsicle。
> 只有 `.app` 才会把这些工具打进 bundle。

```bash
# 批量压缩，同时输出 WebP
minim-cli assets/*.png -q auto --webp

# WebP 转出 PNG 和 JPG 各一份
minim-cli hero.webp --png --jpg

# GIF 转动画 WebP，抽掉一半帧，1.5 倍速
minim-cli loading.gif --anim webp --keep 1/2 --speed 1.5

# 看看这张 JPG 之前被压到什么质量
minim-cli photo.jpg --detect
```

## 构建

开发依赖：Xcode 命令行工具、Homebrew

```bash
brew install pngquant oxipng gifsicle

make app      # 构建并组装 dist/轻图.app（含工具打包 + ad-hoc 签名）
make run      # 构建并启动
make test     # MinimCore 单元测试
make dmg      # 打包 DMG（版本号取自 Info.plist）
```

brew 工具会被拷进 app bundle（`Contents/Helpers` + `Contents/Frameworks`，动态库自动
重定向），所以**打包后的 app 不依赖 Homebrew 环境**。

发版只改一处版本号：`Resources/Info.plist` 的 `CFBundleShortVersionString`。

## 项目结构

| 目录 | 职责 |
| --- | --- |
| `Sources/MinimCore` | 压缩引擎，**不含任何 UI**，可单测 |
| `Sources/MinimApp` | SwiftUI 界面 |
| `Sources/MinimCLI` | 命令行工具 `minim-cli` |
| `Tests/MinimCoreTests` | 引擎单元测试 |
| `scripts/` | .app 组装、工具打包、图标生成 |

压缩相关的新逻辑放 `MinimCore` 并补测试，不写进 View。

## 依赖

| 工具 | 用途 | 分发方式 |
| --- | --- | --- |
| [pngquant](https://pngquant.org) | PNG 有损量化 | 打进 bundle |
| [oxipng](https://github.com/shssoichiro/oxipng) | PNG 无损优化 | 打进 bundle |
| [gifsicle](https://www.lcdf.org/gifsicle/) | GIF 压缩与缩放 | 打进 bundle |
| [apngasm](https://github.com/apngasm/apngasm) | APNG 差分装配 | 随仓库 `Vendor/` |
| [libwebp](https://github.com/SDWebImage/libwebp-Xcode) | WebP 编码 | SwiftPM 源码编译 |

## 许可

[MIT](LICENSE) © 2026 少言syanbo
