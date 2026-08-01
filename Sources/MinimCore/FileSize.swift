import Foundation

extension URL {
    /// 文件字节数；读取失败返回 0（各压缩路径用 0 表示「产物无效」）
    public var fileSizeBytes: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
