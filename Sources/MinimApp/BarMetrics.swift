import SwiftUI

/// 窗口上下两条「横条」的高度。主区域（工具条 / 状态栏）与侧边对比面板的
/// 头部 / 底部都从这里取值，中缝两侧的分隔线才能连成一条直线。
/// 加控件把某一条撑高时，改这里的数值——不要只改一边的 padding
enum BarMetrics {
    /// 工具条高度（SettingsBar）
    static let toolbar: CGFloat = 43
    /// 状态栏高度（StatusBar），同时也是对比面板底部条的高度
    static let status: CGFloat = 31
    /// 标题栏高度（实测值）。侧边面板是从窗口顶端开始排版的，
    /// 主区域的工具条却在标题栏之下，头部要补上这一段才对得齐
    static let titleBar: CGFloat = 32
    /// 对比面板头部高度
    static let inspectorHeader: CGFloat = titleBar + toolbar
}
