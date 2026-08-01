import Foundation

public struct ExternalToolError: Error, CustomStringConvertible {
    public let tool: String
    public let message: String
    public var description: String { "\(tool): \(message)" }
}

/// 定位并运行打包在 app 内（或 brew 安装）的外部压缩工具
public enum ExternalTool {
    public struct RunResult: Sendable {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data
    }

    /// 查找顺序：app bundle 的 Contents/Helpers → brew 路径
    public static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers")
            .appendingPathComponent(name)
        if fm.isExecutableFile(atPath: helper.path) { return helper }
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    @discardableResult
    public static func run(
        _ name: String,
        _ arguments: [String],
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> RunResult {
        guard let executable = locate(name) else {
            throw ExternalToolError(
                tool: name,
                message: "未找到工具，请重新构建 app 或执行 brew install \(name)"
            )
        }
        let result = try await launch(executable: executable, arguments: arguments)
        guard allowedExitCodes.contains(result.status) else {
            let err = String(data: result.stderr, encoding: .utf8) ?? ""
            throw ExternalToolError(
                tool: name,
                message: "退出码 \(result.status)：\(err.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }
        return result
    }

    private static func launch(executable: URL, arguments: [String]) async throws -> RunResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // 任务被取消时终止子进程，否则外部工具会一直跑完（大动图可达数十秒）
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    // readToEnd 在 terminationHandler 里读取，避免管道缓冲区写满死锁的前提是
                    // 输出量小；压缩工具 stdout 均走文件，这里足够
                    let stdout = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let stderr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    continuation.resume(returning: RunResult(
                        status: proc.terminationStatus, stdout: stdout, stderr: stderr
                    ))
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
