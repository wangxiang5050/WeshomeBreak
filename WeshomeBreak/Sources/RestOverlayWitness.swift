import Foundation

/// 看休息遮罩的启动方式。菜单栏应用没有浏览器可开的页面；
/// 带 `--show-rest` 启动时铺上遮罩、开始播放，并把竖线所对的谱面 DOM 写成一份记录。
enum RestOverlayWitness {
    static let argument = "--show-rest"
    static let messageName = "overlayDom"
    static let domRecordURL = URL(fileURLWithPath: "/tmp/weshome-break-overlay-dom.json")

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}
