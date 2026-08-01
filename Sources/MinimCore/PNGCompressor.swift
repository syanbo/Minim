import Foundation

public enum PNGCompressor {
    /// PNG 压缩流水线：
    /// - 保真档 / 已是索引色 → 仅 oxipng 无损优化
    /// - 其余档位 → pngquant 有损量化（转 png8）→ oxipng 无损再优化
    public static func compress(
        source: URL, to destination: URL, preset: QualityPreset
    ) async throws {
        let info = PNGInspector.inspect(source)
        let fm = FileManager.default

        var current = source
        if let range = preset.pngquantQualityRange, info?.isIndexed != true {
            let quantized = destination.deletingPathExtension()
                .appendingPathExtension("pngquant.tmp.png")
            defer { try? fm.removeItem(at: quantized) }

            // 98 = --skip-if-larger 触发，99 = 达不到质量下限；两者都回退无损
            let result = try await ExternalTool.run("pngquant", [
                "--force",
                "--skip-if-larger",
                "--speed", "3",
                "--quality", "\(range.min)-\(range.max)",
                "--output", quantized.path,
                "256",
                "--", source.path,
            ], allowedExitCodes: [0, 98, 99])

            if result.status == 0, fm.fileExists(atPath: quantized.path) {
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: quantized, to: destination)
                current = destination
            }
        }

        if current == source {
            // 未经 pngquant（保真/索引色/量化被跳过），先拷贝到目标再原地无损优化
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: source, to: destination)
        }
        try await ExternalTool.run("oxipng", [
            "-o", "3", "--strip", "safe", "--quiet", destination.path,
        ])
    }
}
