import Foundation
import MinimCore

func printUsage() {
    print("""
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
    """)
}

var files: [URL] = []
var settings = CompressionSettings()
var detectOnly = false

var args = Array(CommandLine.arguments.dropFirst())

/// 取选项的值；缺失时报错退出
func nextValue(_ flag: String) -> String {
    guard !args.isEmpty else {
        print("\(flag) 缺少参数")
        printUsage()
        exit(1)
    }
    return args.removeFirst()
}

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-q":
        let value = nextValue(arg)
        switch value {
        case "10": settings.quality = .p10
        case "30": settings.quality = .p30
        case "50": settings.quality = .p50
        case "80": settings.quality = .p80
        case "auto": settings.quality = .auto
        case "lossless": settings.quality = .lossless
        default:
            print("未知质量档位: \(value)"); exit(1)
        }
    case "--webp":
        settings.conversions.insert(.webp)
    case "--jpg":
        settings.conversions.insert(.jpeg)
    case "--png":
        settings.conversions.insert(.png)
    case "--anim":
        guard let format = AnimOutputFormat(rawValue: nextValue(arg)), format != .gif else {
            print("动图输出格式应为 webp 或 apng"); exit(1)
        }
        settings.anim.output = format
    case "--keep":
        let parts = nextValue(arg).split(separator: "/")
        guard parts.count == 2, let k = Int(parts[0]), let n = Int(parts[1]),
              k >= 1, n >= k else {
            print("--keep 格式应为 K/N（K ≤ N），如 1/2"); exit(1)
        }
        settings.anim.frameKeep = FrameKeep(keep: k, outOf: n)
    case "--frame-step":
        guard let step = Int(nextValue(arg)), step >= 1 else {
            print("--frame-step 需要 ≥1 的整数"); exit(1)
        }
        settings.anim.frameKeep = step > 1
            ? FrameKeep(keep: step - 1, outOf: step)
            : .all
    case "--speed":
        guard let speed = Double(nextValue(arg)), speed >= 0.25, speed <= 4 else {
            print("--speed 需要 0.25~4 之间的数值"); exit(1)
        }
        settings.anim.speed = speed
    case "--loops":
        guard let loops = Int(nextValue(arg)), loops >= 0 else {
            print("--loops 需要 ≥0 的整数（0 = 无限）"); exit(1)
        }
        settings.anim.loopOverride = loops
    case "-o":
        settings.outputMode = .customDir(URL(fileURLWithPath: nextValue(arg)))
    case "--overwrite":
        settings.outputMode = .overwrite
    case "--resize", "--resize-crop":
        let parts = nextValue(arg).lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else {
            print("尺寸格式应为 宽x高，如 800x600"); exit(1)
        }
        settings.resize = ResizeSpec(width: w, height: h, keepAspectRatio: arg == "--resize")
    case "--detect":
        detectOnly = true
    case "-h", "--help":
        printUsage(); exit(0)
    case "--convert":
        print("--convert 已更名为 --jpg")
        exit(1)
    default:
        // 拼错的选项不能被当成图片路径静默吞掉——那会变成
        // 「不支持的图片格式」并让整条流水线以非零码退出，指不到真正的原因
        guard !arg.hasPrefix("-") else {
            print("未知选项: \(arg)")
            printUsage()
            exit(1)
        }
        files.append(URL(fileURLWithPath: arg))
    }
}

guard !files.isEmpty else { printUsage(); exit(1) }

if detectOnly {
    for url in files {
        if let q = JPEGQualityEstimator.estimateQuality(of: url) {
            print("\(url.lastPathComponent): 估计质量 \(q)，默认档输出 \(JPEGQualityEstimator.autoOutputQuality(forEstimated: q))")
        } else {
            print("\(url.lastPathComponent): 无法解析（非 JPEG？）")
        }
    }
    exit(0)
}

let semaphore = DispatchSemaphore(value: 0)
// 本次参数里的所有输入都不能被候选产物覆盖（如 a.png 的 WebP 候选撞上 a.webp）
let protectedPaths = Set(files)
Task {
    var failures = 0
    for url in files {
        do {
            let result = try await CompressionEngine.compress(
                source: url, settings: settings, protectedPaths: protectedPaths
            )
            var line = "\(url.lastPathComponent): \(ByteFormatter.string(result.originalSize)) → " +
                "\(ByteFormatter.string(result.outputSize)) (\(ByteFormatter.ratioString(result.savedRatio)))"
            if result.keptOriginal { line += " [已最优，保留原图]" }
            for candidate in result.converted {
                line += "  \(candidate.label): \(ByteFormatter.string(candidate.size))"
            }
            for target in result.skipped {
                line += "  \(target.label): 已跳过（会覆盖同名文件）"
            }
            print(line)
        } catch {
            failures += 1
            print("\(url.lastPathComponent): 失败 — \(error)")
        }
    }
    exit(failures > 0 ? 2 : 0)
}
semaphore.wait()
