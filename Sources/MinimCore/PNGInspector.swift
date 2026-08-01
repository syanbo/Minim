import Foundation

/// 直接解析 PNG IHDR，判断色彩类型（是否已是索引色 png8）
public enum PNGInspector {
    public struct Info: Sendable {
        public let width: Int
        public let height: Int
        public let bitDepth: Int
        public let colorType: Int

        /// colorType 3 = 索引色（调色板），即 png8 类图片，无需再跑 pngquant
        public var isIndexed: Bool { colorType == 3 }
        /// colorType 4/6 带 alpha 通道
        public var hasAlphaChannel: Bool { colorType == 4 || colorType == 6 }
    }

    public static func inspect(_ url: URL) -> Info? {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 33)
        else { return nil }
        try? handle.close()
        return inspect(data ?? Data())
    }

    public static func inspect(_ data: Data) -> Info? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let bytes = [UInt8](data.prefix(33))
        guard bytes.count >= 33, Array(bytes[0..<8]) == signature else { return nil }
        // 第 8-15 字节：IHDR chunk 长度 + 类型
        guard Array(bytes[12..<16]) == [UInt8]("IHDR".utf8) else { return nil }
        let width = Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19])
        let height = Int(bytes[20]) << 24 | Int(bytes[21]) << 16 | Int(bytes[22]) << 8 | Int(bytes[23])
        return Info(width: width, height: height, bitDepth: Int(bytes[24]), colorType: Int(bytes[25]))
    }
}
