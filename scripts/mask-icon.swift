// 把方形图标底图套上 macOS 标准圆角蒙版（居中裁方 → 824/1024 内容区 → 圆角裁切 → 透明边）
// 用法: swift scripts/mask-icon.swift <底图.png> <输出.png>
import AppKit

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]

guard let source = NSImage(contentsOfFile: input),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fatalError("无法读取 \(input)") }

// 居中裁成正方形
let side = min(cg.width, cg.height)
let cropped = cg.cropping(to: CGRect(
    x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side
))!

let canvas: CGFloat = 1024
// macOS 图标网格：内容区 824×1024，圆角半径约 185
let content: CGFloat = 824
let radius: CGFloat = 185
let inset = (canvas - content) / 2

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
let rect = NSRect(x: inset, y: inset, width: content, height: content)
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
NSImage(cgImage: cropped, size: .zero).draw(
    in: rect, from: .zero, operation: .sourceOver, fraction: 1
)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("渲染失败") }
try! png.write(to: URL(fileURLWithPath: output))
print("✓ \(output)")
