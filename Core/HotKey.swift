import AppKit
import Carbon.HIToolbox

// MARK: - HotKeyCenter
//
// 全局快捷键中心。目前只有一个固定快捷键:⌃⌥F 显示/隐藏悬浮窗。
// 用 Carbon RegisterEventHotKey 实现:菜单栏 App 在后台(.accessory 非激活态)
// 也能响应,且不需要辅助功能授权。SwiftUI Commands 的快捷键只在 App 激活时有效,
// 对常驻后台的菜单栏 App 没用,所以必须走这条路。

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// 快捷键触发时的动作,由 AppDelegate 在启动时注入。
    var onToggleFloating: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// signature 'MBAR' + id 1,系统用它区分不同 App / 不同快捷键
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_4152), id: 1)

    private init() {}

    /// 按设置注册 / 注销 ⌃⌥F。重复调用安全(内部幂等)。
    func setToggleFloatingEnabled(_ enabled: Bool) {
        if enabled {
            register()
        } else {
            unregister()
        }
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(controlKey | optionKey),
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("HotKeyCenter: RegisterEventHotKey failed (\(status)),⌃⌥F 可能被其他 App 占用")
            return
        }
        hotKeyRef = ref
    }

    private func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C 回调不能捕获上下文,通过 userData 带回 self。
        // Carbon 快捷键事件在主线程 run loop 分发,assumeIsolated 回到 MainActor 是安全的。
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    center.onToggleFloating?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
