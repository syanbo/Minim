import Foundation

/// 限制并发压缩数量的信号量
actor CompressionQueue {
    static let shared = CompressionQueue(
        maxConcurrent: min(ProcessInfo.processInfo.activeProcessorCount, 6)
    )

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        running += 1
    }

    func release() {
        running -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
