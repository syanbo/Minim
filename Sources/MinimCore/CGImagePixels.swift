import Foundation
import CoreGraphics

/// CGImage 像素缓冲提取（静态 WebP 与动画 WebP 共用，保证两条路径颜色一致）
enum CGImagePixels {

    /// 绘制成直通（非预乘）RGBA8 缓冲——
    /// 预乘会让发光/半透明渐变发灰发暗；指定尺寸时把图绘到该画布上（帧尺寸不一致时对齐）
    static func straightRGBA(of image: CGImage, width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let w = width ?? image.width
        let h = height ?? image.height
        let rowBytes = w * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * h)
        guard let context = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixels }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 反预乘：CGContext 只支持预乘输出，手动还原直通 alpha
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            if a != 0 && a != 255 {
                pixels[i] = UInt8(min(255, Int(pixels[i]) * 255 / a))
                pixels[i + 1] = UInt8(min(255, Int(pixels[i + 1]) * 255 / a))
                pixels[i + 2] = UInt8(min(255, Int(pixels[i + 2]) * 255 / a))
            }
        }
        return pixels
    }
}
