import Foundation
import Observation
import MinimCore

/// 检查 GitHub Releases 上有没有新版本。
///
/// **这是本 App 唯一的网络请求**——只读取公开的 Release 元数据，
/// 不发送任何图片、路径或使用数据。用户可以在「轻图」菜单里关掉自动检查。
@MainActor
@Observable
final class UpdateChecker {

    enum State: Equatable {
        case idle
        case checking
        /// 已是最新
        case upToDate(current: String)
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// 手动检查时才弹结果；自动检查只在「有新版本」时打扰用户
    private(set) var presentsResult = false

    var autoCheckEnabled: Bool {
        didSet { defaults.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheckAt"
    private static let endpoint = URL(
        string: "https://api.github.com/repos/syanbo/Minim/releases/latest"
    )!
    /// 自动检查的最小间隔。GitHub 未认证 API 限 60 次/小时/IP，
    /// 而且没必要每次启动都打扰人家的服务器
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    init() {
        // 没写过这个 key 时默认开启（对应「启动时自动检查」这个选择）
        autoCheckEnabled = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 启动时调用：关掉了、或距上次检查不足一天，就什么都不做
    func checkOnLaunchIfNeeded() {
        guard autoCheckEnabled else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.autoCheckInterval else { return }
        Task { await check(userInitiated: false) }
    }

    /// 菜单里「检查更新…」调用
    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    func dismiss() {
        presentsResult = false
        state = .idle
    }

    private func check(userInitiated: Bool) async {
        guard state != .checking else { return }
        state = .checking
        presentsResult = userInitiated
        defaults.set(Date(), forKey: Self.lastCheckKey)

        do {
            var request = URLRequest(url: Self.endpoint)
            // GitHub API 要求带 User-Agent，否则返回 403
            request.setValue("Minim/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw UpdateError.badStatus(code)
            }

            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let latest = ReleaseVersion(release.tagName),
                  let current = ReleaseVersion(currentVersion) else {
                throw UpdateError.unparsableVersion(release.tagName)
            }

            if latest > current {
                state = .updateAvailable(version: latest.description, url: release.htmlUrl)
                // 有新版本时即使是自动检查也要告诉用户
                presentsResult = true
            } else {
                state = .upToDate(current: currentVersion)
            }
        } catch {
            state = .failed(Self.readable(error))
            // 自动检查失败不打扰用户——网断了不是他的错
        }
    }

    private static func readable(_ error: Error) -> String {
        switch error {
        case UpdateError.badStatus(let code): "GitHub 返回 \(code)"
        case UpdateError.unparsableVersion(let tag): "无法识别的版本号「\(tag)」"
        case let urlError as URLError where urlError.code == .notConnectedToInternet: "网络未连接"
        case let urlError as URLError where urlError.code == .timedOut: "请求超时"
        default: "检查失败"
        }
    }

    private enum UpdateError: Error {
        case badStatus(Int)
        case unparsableVersion(String)
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }
    }
}
