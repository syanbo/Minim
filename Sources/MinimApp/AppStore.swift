import Foundation
import Observation
import MinimCore

@MainActor
@Observable
final class AppStore {
    var tasks: [ImageTask] = []
    var quality: QualityPreset = .auto {
        didSet { defaults.set(quality.rawValue, forKey: "quality") }
    }
    var generateWebP = false {
        didSet { defaults.set(generateWebP, forKey: "generateWebP") }
    }
    /// 转 JPG：PNG / 静态 WebP 额外输出一张 JPG
    var autoConvert = false {
        didSet { defaults.set(autoConvert, forKey: "autoConvert") }
    }
    /// 转 PNG：JPG / 静态 WebP 额外输出一张无损 PNG
    var convertToPNG = false {
        didSet { defaults.set(convertToPNG, forKey: "convertToPNG") }
    }
    /// 替换原图模式：只对之后添加的图片生效，不回溯已完成任务
    /// （否则源文件已被覆盖，再压会二次劣化）
    var replaceOriginal = false {
        didSet { defaults.set(replaceOriginal, forKey: "replaceOriginal") }
    }

    // 裁剪缩放（复刻原版：开关 + 宽/高 + 是否限制宽高比）
    // 裁剪缩放：只持久化，设置变更后通过状态栏「应用新设置」手动触发重压
    var resizeEnabled = false {
        didSet { defaults.set(resizeEnabled, forKey: "resizeEnabled") }
    }
    var resizeWidth = 0 {
        didSet { defaults.set(resizeWidth, forKey: "resizeWidth") }
    }
    var resizeHeight = 0 {
        didSet { defaults.set(resizeHeight, forKey: "resizeHeight") }
    }
    var resizeKeepRatio = true {
        didSet { defaults.set(resizeKeepRatio, forKey: "resizeKeepRatio") }
    }

    // 动图转换：输出格式 / 抽帧步长 / 循环设置（弹出面板关闭时统一触发重压）
    var animOutput: AnimOutputFormat = .gif {
        didSet { defaults.set(animOutput.rawValue, forKey: "animOutput") }
    }
    var animFrameKeep = FrameKeep.all {
        didSet {
            defaults.set(animFrameKeep.keep, forKey: "animFrameKeepNum")
            defaults.set(animFrameKeep.outOf, forKey: "animFrameKeepDen")
        }
    }
    /// 播放速度倍数（1 = 原速，与抽帧解耦）
    var animSpeed = 1.0 {
        didSet { defaults.set(animSpeed, forKey: "animSpeed") }
    }
    /// "keep" 保留原设置 / "infinite" 无限循环 / "custom" 自定义次数
    var animLoopMode = "keep" {
        didSet { defaults.set(animLoopMode, forKey: "animLoopMode") }
    }
    var animLoopCount = 1 {
        didSet { defaults.set(animLoopCount, forKey: "animLoopCount") }
    }

    var presentFileImporter = false
    /// 当前在对比弹框中查看的任务
    var compareTask: ImageTask?
    /// 进行中的任务句柄（用于取消）与阶段文案
    @ObservationIgnored
    private var running: [UUID: Task<Void, Never>] = [:]
    private var stages: [UUID: String] = [:]

    private var animLoopOverride: Int? {
        switch animLoopMode {
        case "infinite": 0
        case "custom": max(1, animLoopCount)
        default: nil
        }
    }

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    init() {
        if let raw = defaults.string(forKey: "quality"),
           let saved = QualityPreset(rawValue: raw) {
            quality = saved
        }
        generateWebP = defaults.bool(forKey: "generateWebP")
        autoConvert = defaults.bool(forKey: "autoConvert")
        convertToPNG = defaults.bool(forKey: "convertToPNG")
        replaceOriginal = defaults.bool(forKey: "replaceOriginal")
        resizeEnabled = defaults.bool(forKey: "resizeEnabled")
        resizeWidth = defaults.integer(forKey: "resizeWidth")
        resizeHeight = defaults.integer(forKey: "resizeHeight")
        resizeKeepRatio = defaults.object(forKey: "resizeKeepRatio") as? Bool ?? true
        if let raw = defaults.string(forKey: "animOutput"),
           let saved = AnimOutputFormat(rawValue: raw) {
            animOutput = saved
        }
        if let den = defaults.object(forKey: "animFrameKeepDen") as? Int, den > 0 {
            animFrameKeep = FrameKeep(
                keep: defaults.integer(forKey: "animFrameKeepNum"), outOf: den
            )
        } else if let step = defaults.object(forKey: "animFrameStep") as? Int, step > 1 {
            // 迁移旧设置：「每 N 帧删 1」等价于「每 N 帧保留 N-1 帧」
            animFrameKeep = FrameKeep(keep: step - 1, outOf: step)
        }
        animSpeed = defaults.object(forKey: "animSpeed") as? Double ?? 1.0
        animLoopMode = defaults.string(forKey: "animLoopMode") ?? "keep"
        animLoopCount = max(1, defaults.integer(forKey: "animLoopCount"))
    }

    /// 工具栏设置变更后待重压的任务（不自动运行，用户点「应用新设置」才执行）；
    /// 动图有独立的重试流程、覆盖模式的源文件已被替换，均不参与
    var staleTaskIDs: [UUID] {
        let current = settings
        return tasks.compactMap { task in
            guard !task.isAnimated, let last = task.lastRunSettings else { return nil }
            switch task.state {
            case .done, .failed:
                if case .overwrite = last.outputMode { return nil }
                return baseSettingsEqual(last, current) ? nil : task.id
            case .awaitingStart, .pending, .processing:
                return nil
            }
        }
    }

    func recompressStale() {
        for id in staleTaskIDs {
            update(taskID: id, state: .pending)
            process(taskID: id)
        }
    }

    /// 比较与静态图片相关的设置：把动图参数对齐后整体比较。
    /// 不要退回手工逐字段列举——新增设置项时漏掉一个不会报错，
    /// 只会表现为「改了开关却不提示重新生成」这种难查的静默失效
    private func baseSettingsEqual(_ a: CompressionSettings, _ b: CompressionSettings) -> Bool {
        var normalized = a
        normalized.anim = b.anim
        return normalized == b
    }

    var doneCount: Int {
        tasks.count { $0.state.isDone }
    }

    var totalSaved: Int64 {
        tasks.reduce(0) {
            guard let result = $1.state.result else { return $0 }
            return $0 + max(0, result.originalSize - result.outputSize)
        }
    }

    var settings: CompressionSettings {
        CompressionSettings(
            quality: quality,
            generateWebP: generateWebP,
            outputMode: replaceOriginal
                ? .overwrite
                : .fixedSubdir(OutputMode.defaultSubdirName),
            resize: (resizeEnabled && (resizeWidth > 0 || resizeHeight > 0))
                ? ResizeSpec(
                    width: resizeWidth, height: resizeHeight,
                    keepAspectRatio: resizeKeepRatio
                )
                : nil,
            autoConvert: autoConvert,
            convertToPNG: convertToPNG,
            anim: AnimSettings(
                output: animOutput,
                frameKeep: animFrameKeep,
                speed: animSpeed,
                loopOverride: animLoopOverride
            )
        )
    }

    /// 任务实际生效的动图参数：行内覆盖优先，否则跟随工具栏全局设置。
    /// 非 GIF 输入没有「GIF 压缩」档，统一矫正为自身格式的重编码
    func animConfig(for task: ImageTask) -> AnimSettings {
        var config = task.animConfig ?? settings.anim
        config.output = config.output.resolved(for: task.format) ?? config.output
        return config
    }

    /// 该任务是否脱离了全局设置（行内单独调过参数）
    func hasAnimOverride(_ task: ImageTask) -> Bool {
        task.animConfig != nil
    }

    func add(urls: [URL]) {
        var newTasks: [ImageTask] = []
        let existing = Set(tasks.map(\.sourceURL))
        for url in expand(urls: urls) where !existing.contains(url) {
            if var task = ImageTask(sourceURL: url) {
                // 动图不自动开始：先展示信息，用户确认参数后手动点开始；
                // 参数默认跟随工具栏（animConfig 为 nil），行内改过才脱离
                if task.isAnimated {
                    task.state = .awaitingStart
                }
                newTasks.append(task)
            }
        }
        tasks.append(contentsOf: newTasks)
        for task in newTasks where !task.isAnimated {
            process(taskID: task.id)
        }
    }

    /// 动图任务：应用行内参数并开始处理
    func startAnim(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = .pending
        process(taskID: taskID)
    }

    /// 一键开始所有待开始的动图
    func startAllAnim() {
        for task in tasks where task.state.isAwaitingStart {
            startAnim(taskID: task.id)
        }
    }

    /// 行内改参数 → 该任务脱离全局设置
    func updateAnimConfig(taskID: UUID, _ config: AnimSettings) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].animConfig != config else { return }
        tasks[index].animConfig = config
    }

    /// 恢复跟随工具栏全局设置
    func resetAnimConfig(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].animConfig = nil
    }

    var overriddenAnimCount: Int {
        tasks.count { $0.animConfig != nil }
    }

    func resetAllAnimOverrides() {
        for index in tasks.indices where tasks[index].animConfig != nil {
            tasks[index].animConfig = nil
        }
    }

    var awaitingAnimCount: Int {
        tasks.count { $0.state.isAwaitingStart }
    }

    var finishedCount: Int {
        tasks.count {
            switch $0.state {
            case .done, .failed: true
            case .awaitingStart, .pending, .processing: false
            }
        }
    }

    /// 只移除已完成/失败的任务；待开始的动图会保留（它们还没被处理过）
    func clearFinished() {
        tasks.removeAll {
            switch $0.state {
            case .done, .failed: true
            case .awaitingStart, .pending, .processing: false
            }
        }
        if let compare = compareTask, !tasks.contains(where: { $0.id == compare.id }) {
            compareTask = nil
        }
    }

    /// 移除全部任务（含待开始与排队中）
    func removeAll() {
        cancelAll()
        tasks.removeAll()
        compareTask = nil
    }

    private func process(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]
        var settings = self.settings
        if task.isAnimated {
            settings.anim = animConfig(for: task)
        }
        tasks[index].lastRunSettings = settings
        let source = task.sourceURL
        running[taskID] = Task {
            await CompressionQueue.shared.acquire()
            defer { Task { await CompressionQueue.shared.release() } }
            guard !Task.isCancelled else { return }
            self.update(taskID: taskID, state: .processing)
            do {
                let result = try await CompressionEngine.compress(
                    source: source, settings: settings,
                    onStage: { [weak self] stage in
                        Task { @MainActor in self?.stages[taskID] = stage }
                    }
                )
                self.finish(taskID: taskID, state: .done(result))
            } catch is CancellationError {
                self.finish(taskID: taskID, state: .awaitingStart)
            } catch {
                self.finish(
                    taskID: taskID,
                    state: Task.isCancelled ? .awaitingStart : .failed(Self.readable(error))
                )
            }
        }
    }

    /// 取消处理中的任务，回到可重新开始的状态
    func cancel(taskID: UUID) {
        running[taskID]?.cancel()
        running[taskID] = nil
        stages[taskID] = nil
        update(taskID: taskID, state: .awaitingStart)
    }

    func cancelAll() {
        for (id, task) in running {
            task.cancel()
            update(taskID: id, state: .awaitingStart)
        }
        running.removeAll()
        stages.removeAll()
    }

    var runningCount: Int {
        tasks.count {
            switch $0.state {
            case .pending, .processing: true
            case .awaitingStart, .done, .failed: false
            }
        }
    }

    /// 处理中的阶段文案（如「量化调色板 12/64」）
    func stage(for taskID: UUID) -> String? {
        stages[taskID]
    }

    private func finish(taskID: UUID, state: ImageTaskState) {
        running[taskID] = nil
        stages[taskID] = nil
        update(taskID: taskID, state: state)
    }

    /// 外部工具的原始报错对用户没有意义，转成可读文案
    private static func readable(_ error: Error) -> String {
        guard let toolError = error as? ExternalToolError else { return "处理失败" }
        let detail = toolError.message
            .split(separator: "\n").first.map(String.init) ?? toolError.message
        return "\(toolError.tool) 处理失败：\(detail.prefix(120))"
    }

    private func update(taskID: UUID, state: ImageTaskState) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = state
    }

    /// 展开文件夹（浅层一级），过滤出图片文件。
    /// explicit = 用户直接指定的条目（不过滤自家产物目录，用户明确想压它）；
    /// 递归发现的子项传 false，避免把自己的产物再压一遍
    private func expand(urls: [URL], explicit: Bool = true) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            let isDir = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
            if isDir {
                // 只展开一级：递归发现的子目录不再深入
                guard explicit else { continue }
                let children = (try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                result.append(contentsOf: expand(
                    urls: children.sorted { $0.lastPathComponent < $1.lastPathComponent },
                    explicit: false
                ))
            } else {
                if !explicit, url.pathComponents.contains(OutputMode.defaultSubdirName) { continue }
                result.append(url)
            }
        }
        return result
    }
}
