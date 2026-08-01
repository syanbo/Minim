# 轻图 Minim

macOS 原生图片压缩工具。SwiftUI 编写，原生支持 Apple Silicon（arm64），支持深色模式。

## 功能

- 拖拽 / 选择 PNG、JPG、WebP、GIF、APNG 批量压缩（支持拖入文件夹）
- 质量档位：10% / 30% / 50% / 80% / 默认 / 保真
- **JPG 智能压缩**：解析量化表估算原图质量，据此决定输出质量，避免重复压缩劣化
- PNG：pngquant 有损量化（转 png8）→ oxipng 无损优化；已是索引色或保真档只走无损
- GIF：gifsicle -O3 + 按档位 --lossy
- 静态 WebP：ImageIO 解码 + libwebp 重编码（无损 / 有损双候选取更优）
- **三个转换开关**，语义统一为「额外输出一份 X」，不替换主输出：
  - **WebP** — PNG / JPG 额外输出 `.webp`
  - **JPG** — PNG / 静态 WebP 额外输出 `名字-jpg.jpg`（透明部分平铺白底）
  - **PNG** — JPG / 静态 WebP 额外输出 `名字-png.png`（无损，保留透明）
- 压缩结果不比原图小时自动保留原图（标记「已最优」）
- 输出到源目录下的 `minim/` 固定文件夹，**文件名保持不变**（整个文件夹压完可直接替换回
  项目）；WebP 与主输出同目录、同名换扩展
- 可切换「替换原图」模式（不保留原图，只对之后添加的图片生效）
- 拖入文件夹时自动跳过 `minim` 输出目录，不会把自己的产物再压一遍
- **裁剪缩放**：设定宽×高后，「等比缩放」缩到框内不变形；「居中裁剪」缩放覆盖后裁出精确
  尺寸。超过原图的维度按原图处理（不放大），GIF 用 gifsicle 缩放（动图帧保留）
- **动图转换**：GIF / 动图 WebP 拖入后**不自动处理**——先展示基础信息（帧数/时长/循环/
  尺寸），行内单独设置输出格式（GIF 压缩 / 动画 WebP / APNG 无损）、**抽帧**（每 N 帧取 1，
  总时长不变）、**循环次数**（保留 / 无限 / 自定义），点「开始」执行；多个待开始时状态栏可
  「全部开始」，完成后参数行保留，改动参数会出现「重试」按钮（不自动重跑）。行内参数会被
  记住，作为下次拖入动图的默认值。动画 WebP 用 libwebp WebPAnimEncoder 进程内编码，
  APNG 走系统 ImageIO，逐帧套用「裁剪缩放」
- 所有选项自动记忆，重启后保留

## 构建

依赖：Xcode 命令行工具、Homebrew（`brew install pngquant oxipng gifsicle`）

```bash
make app      # 构建并组装 dist/轻图.app（含工具打包 + ad-hoc 签名）
make run      # 构建并启动
make test     # MinimCore 单元测试
make dmg      # 打包 DMG
swift run minim-cli photo.webp -q auto --png --jpg   # 命令行版
```

brew 工具会被拷入 app bundle（`Contents/Helpers` + `Contents/Frameworks`，动态库自动
重定向），打包后的 app 不依赖 Homebrew 环境。

## 结构

- `Sources/MinimCore` — 压缩引擎（无 UI，可单测）：各格式压缩器、JPEG 质量估算、外部工具封装
- `Sources/MinimApp` — SwiftUI 界面
- `Sources/MinimCLI` — 命令行工具 `minim-cli`
- `scripts/` — .app 组装、工具打包、图标生成

## 许可

[MIT](LICENSE) © 2026 少言syanbo
