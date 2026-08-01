// 生成应用图标：圆角渐变底 +「智」字，输出 1024px PNG
// 用法: swift scripts/make-icon.swift <输出.png>
import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS 图标习惯：内容占画布约 80%，四周留透明边
let inset: CGFloat = size * 0.1
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
path.addClip()

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.13, green: 0.68, blue: 0.55, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.65, alpha: 1)
)
gradient?.draw(in: rect, angle: -60)

let text = "智" as NSString
let font = NSFont.systemFont(ofSize: size * 0.46, weight: .semibold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let textSize = text.size(withAttributes: attrs)
text.draw(
    at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
    withAttributes: attrs
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("图标渲染失败")
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("✓ \(outputPath)")
