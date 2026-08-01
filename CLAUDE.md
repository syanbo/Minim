# 轻图 Minim

macOS 原生图片压缩工具。SwiftUI，仅 macOS 14+ / arm64。详细功能见 README.md。

## 命令

```bash
make app     # 构建 + 组装 dist/轻图.app（含工具打包 + ad-hoc 签名）
make run     # 构建并启动
make test    # MinimCore 单元测试
make dmg     # 打包 DMG（版本号从 Info.plist 读）
```

- **构建一律用 `make app`，不要直接 `swift build`** —— 后者只编译，不会把
  pngquant / oxipng / gifsicle / apngasm 打进 bundle，出来的 App 压缩功能全挂。
- 发版改版本号只改一处：`Resources/Info.plist` 的 `CFBundleShortVersionString`，
  `make-dmg.sh` 会自动读取并命名 DMG。

## 结构

| 目录 | 职责 |
| --- | --- |
| `Sources/MinimCore` | 压缩引擎，**不含任何 UI**，可单测 |
| `Sources/MinimApp` | SwiftUI 界面，全局状态在 `AppStore.swift` |
| `Sources/MinimCLI` | 命令行版 `minim-cli` |
| `scripts/` | .app 组装、工具打包、图标生成 |

压缩相关的新逻辑放 MinimCore 并补测试，不要写进 View。

## 约定

- **界面文案、代码注释一律中文。**
- **任何设置变更都不自动重跑已完成的任务。** 工具条设置改了 → 状态栏出现
  「重新生成（N）」按钮手动触发；动图参数改了 → 行内出现「重试」按钮。
  这是用户明确要求的交互原则，不要"顺手优化"成自动重跑。
- **动图（GIF / 动图 WebP / APNG）拖入后不自动开始**，先展示帧数/时长/循环/尺寸，
  用户行内设好参数再点「开始」。静态图才是拖入即压。
- **工具条（`SettingsBar.swift`）每个控件都必须 `.fixedSize()`**，否则窗口变窄时
  会被挤压变形。加新控件时照抄现有写法。
- 压缩结果不比原图小时保留原图，标记「已最优」——不要改成强制覆盖。
- 输出文件名保持不变（复刻原版逻辑，整个文件夹压完可直接替换回项目）。

## 环境依赖

开发机需要 `brew install pngquant oxipng gifsicle`；`apngasm` 已随仓库放在
`Vendor/tools/`。打包后的 App 不依赖 Homebrew。
