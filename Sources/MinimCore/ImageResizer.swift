import Foundation
import CoreGraphics
import ImageIO

/// 位图裁剪缩放（PNG/JPEG/WebP 共用；GIF 走 gifsicle）
public enum ImageResizer {

    /// 等比缩放后的尺寸（缩到 w×h 框内，不放大）
    static func fitSize(
        originalWidth: Int, originalHeight: Int, targetWidth: Int, targetHeight: Int
    ) -> (width: Int, height: Int) {
        let scale = min(
            Double(targetWidth) / Double(originalWidth),
            Double(targetHeight) / Double(originalHeight),
            1
        )
        return (
            max(1, Int((Double(originalWidth) * scale).rounded())),
            max(1, Int((Double(originalHeight) * scale).rounded()))
        )
    }

    /// 覆盖目标宽高比的最大居中裁剪区域（原图坐标系，左上原点）——
    /// 先按此裁剪再缩放到目标尺寸，等价于「缩放覆盖后居中裁剪」且不需要中间产物
    public static func coverCropRect(
        originalWidth: Int, originalHeight: Int, targetWidth: Int, targetHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let scale = min(
            Double(originalWidth) / Double(targetWidth),
            Double(originalHeight) / Double(targetHeight)
        )
        let width = min(originalWidth, max(1, Int((Double(targetWidth) * scale).rounded())))
        let height = min(originalHeight, max(1, Int((Double(targetHeight) * scale).rounded())))
        return ((originalWidth - width) / 2, (originalHeight - height) / 2, width, height)
    }

    /// 对已解码图像应用裁剪缩放；返回 nil 表示尺寸没变化，无需处理
    public static func apply(_ spec: ResizeSpec, to image: CGImage) -> CGImage? {
        let ow = image.width
        let oh = image.height
        let target = spec.clampedTarget(originalWidth: ow, originalHeight: oh)

        let canvasWidth: Int
        let canvasHeight: Int
        let drawRect: CGRect
        if spec.keepAspectRatio {
            // 等比缩放到框内
            let size = fitSize(
                originalWidth: ow, originalHeight: oh,
                targetWidth: target.width, targetHeight: target.height
            )
            if size.width == ow && size.height == oh { return nil }
            canvasWidth = size.width
            canvasHeight = size.height
            drawRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        } else {
            // 缩放覆盖目标框后居中裁剪（对应原版 imagemagick crop gravity=Center）
            if target.width == ow && target.height == oh { return nil }
            canvasWidth = target.width
            canvasHeight = target.height
            let scale = max(
                Double(target.width) / Double(ow),
                Double(target.height) / Double(oh)
            )
            let drawWidth = Double(ow) * scale
            let drawHeight = Double(oh) * scale
            drawRect = CGRect(
                x: (Double(target.width) - drawWidth) / 2,
                y: (Double(target.height) - drawHeight) / 2,
                width: drawWidth,
                height: drawHeight
            )
        }

        guard let context = CGContext(
            data: nil,
            width: canvasWidth, height: canvasHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: drawRect)
        return context.makeImage()
    }

    /// 从文件解码并应用裁剪缩放；返回 nil 表示无需处理
    public static func resizedImage(from url: URL, spec: ResizeSpec) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary)
        else { return nil }
        return apply(spec, to: image)
    }

    /// 把图像无损写为 PNG（作为 pngquant/oxipng 流程的输入）
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw ExternalToolError(tool: "ImageIO", message: "无法创建 PNG 输出")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ExternalToolError(tool: "ImageIO", message: "PNG 编码失败")
        }
    }

    /// 读取图片像素尺寸（不解码全图）
    public static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}
