import Foundation

/// 解析 JPEG 量化表（DQT）估算原始编码质量，实现「智能压缩」：
/// 先测原图质量，再按映射表决定输出质量，避免对已压缩过的图重复劣化。
public enum JPEGQualityEstimator {

    // ITU T.81 Annex K 标准亮度量化表（自然顺序）
    private static let stdLuminance: [Int] = [
        16, 11, 10, 16, 24, 40, 51, 61,
        12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77,
        24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103, 99,
    ]

    // ITU T.81 Annex K 标准色度量化表（自然顺序）
    private static let stdChrominance: [Int] = [
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
    ]

    // zigzag 序列位置 → 自然顺序位置
    private static let zigzag: [Int] = [
        0, 1, 8, 16, 9, 2, 3, 10,
        17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13, 6, 7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63,
    ]

    /// 「原质量 → 输出质量」经验映射表，<61 一律 10
    private static let outputQualityMap: [Int: Int] = [
        61: 10, 62: 10, 63: 10, 64: 10, 65: 10, 66: 10, 67: 20, 68: 20, 69: 30, 70: 30,
        71: 30, 72: 40, 73: 40, 74: 40, 75: 40, 76: 40, 77: 40, 78: 40, 79: 40, 80: 40,
        81: 40, 82: 50, 83: 50, 84: 55, 85: 55, 86: 60, 87: 60, 88: 65, 89: 65, 90: 65,
        91: 70, 92: 70, 93: 75, 94: 80, 95: 85, 96: 85, 97: 90, 98: 95, 99: 99, 100: 99,
    ]

    /// 估算 JPEG 文件的编码质量（1-100），解析失败返回 nil
    public static func estimateQuality(of url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return estimateQuality(of: data)
    }

    public static func estimateQuality(of data: Data) -> Int? {
        guard let tables = parseQuantizationTables(data), !tables.isEmpty else { return nil }
        let luma = tables[0]
        let chroma = tables.count > 1 ? tables[1] : nil

        var bestQ = 0
        var bestError = Int.max
        for q in 1...100 {
            var error = distance(luma, scaled(stdLuminance, quality: q))
            if let chroma {
                error += distance(chroma, scaled(stdChrominance, quality: q))
            }
            if error < bestError {
                bestError = error
                bestQ = q
            }
        }
        return bestQ
    }

    /// 「默认」档位：按原版映射表得到输出质量
    public static func autoOutputQuality(forEstimated estimated: Int) -> Int {
        if estimated < 61 { return 10 }
        return outputQualityMap[min(estimated, 100)] ?? 40
    }

    /// 「保真」档位：不高于原质量，封顶 95
    public static func losslessOutputQuality(forEstimated estimated: Int) -> Int {
        min(estimated, 95)
    }

    // MARK: - 内部实现

    /// 遍历 JPEG marker 提取所有 DQT 表（转为自然顺序），到 SOS 为止
    static func parseQuantizationTables(_ data: Data) -> [[Int]]? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }

        var tables: [[Int]] = []
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { i += 1; continue }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }          // 填充字节
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            if marker == 0xDA || marker == 0xD9 { break }   // SOS / EOI

            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return tables.isEmpty ? nil : tables }

            if marker == 0xDB {
                // 一个 DQT 段可含多张表
                var p = i + 4
                let end = i + 2 + length
                while p < end {
                    let precision = Int(bytes[p]) >> 4      // 0: 8bit, 1: 16bit
                    p += 1
                    let valueSize = precision == 0 ? 1 : 2
                    guard p + 64 * valueSize <= end else { break }
                    var natural = [Int](repeating: 0, count: 64)
                    for k in 0..<64 {
                        let v: Int
                        if precision == 0 {
                            v = Int(bytes[p + k])
                        } else {
                            v = Int(bytes[p + k * 2]) << 8 | Int(bytes[p + k * 2 + 1])
                        }
                        natural[zigzag[k]] = v
                    }
                    tables.append(natural)
                    p += 64 * valueSize
                }
            }
            i += 2 + length
        }
        return tables.isEmpty ? nil : tables
    }

    /// IJG 缩放公式：由质量 q 生成标准表的缩放版本
    static func scaled(_ base: [Int], quality: Int) -> [Int] {
        let q = max(1, min(100, quality))
        let scale = q < 50 ? 5000 / q : 200 - 2 * q
        return base.map { max(1, min(255, ($0 * scale + 50) / 100)) }
    }

    private static func distance(_ a: [Int], _ b: [Int]) -> Int {
        zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
    }
}
