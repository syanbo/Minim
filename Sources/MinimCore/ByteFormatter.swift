import Foundation

public enum ByteFormatter {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 压缩率展示，如 "-37.5%"；负优化返回 "+x%"
    public static func ratioString(_ savedRatio: Double) -> String {
        String(format: "%+.1f%%", -savedRatio * 100)
    }
}
