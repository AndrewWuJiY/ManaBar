// CCBarClaudeWatchdog
//
// 一个最小化的进程套娃中间层,专门用于"代 cc-bar 启动 `claude` CLI"。
//
// 为什么需要它(隐私归属):
//   macOS TCC 在做"哪个 App 想访问这个受保护资源"的判定时,会沿进程链上溯找到第一个
//   有独立 code signature / responsibility identity 的 ancestor。如果 cc-bar 主体直接
//   `Process()` 起 claude CLI,所有 claude 的文件访问行为都被归到 CCBar.app 头上,
//   弹窗会提示"CCBar 想访问 文稿 / 桌面 / 相册...",对用户极不友好且容易引起误解
//   (cc-bar 自身只是个只读监控,不会主动访问这些目录)。
//
//   插入这一层 watchdog 后,claude 的父进程链上首先看到的是 watchdog 二进制本身。
//   只要 watchdog 单独签名、Info.plist 设置合适的 display name,TCC 就会归因到
//   watchdog,而不是 ccbar 主体。
//
// 这只是个透明转发器,没有任何业务逻辑——保持精简到极致是刻意的。
// 参考实现:CodexBar 的 `Sources/CodexBarClaudeWatchdog/main.swift`。

import Darwin
import Foundation

private enum WatchdogExitCode {
    static let usage: Int32 = 64
    static let spawnFailed: Int32 = 70
}

// nonisolated(unsafe) 是因为 Swift 6 严格并发下信号 handler 需要全局可变状态,
// 而信号 handler 本身是 C 风格回调,只能裸碰全局变量。
private nonisolated(unsafe) var globalChildPID: pid_t = 0
private nonisolated(unsafe) var globalShouldTerminate: Int32 = 0

private func usageAndExit() -> Never {
    fputs("Usage: CCBarClaudeWatchdog -- <binary> [args...]\n", stderr)
    Darwin.exit(WatchdogExitCode.usage)
}

/// 把 child 所在的整个进程组干掉,先 SIGTERM 等一会再 SIGKILL。
/// CLI 启动 node 子进程是常态,只 kill 直接 child 会留下孤儿。
private func killProcessTree(childPID: pid_t, graceSeconds: TimeInterval = 0.5) {
    let pgid = getpgid(childPID)
    if pgid > 0 {
        kill(-pgid, SIGTERM)
    } else {
        kill(childPID, SIGTERM)
    }

    let deadline = Date().addingTimeInterval(graceSeconds)
    var status: Int32 = 0
    while Date() < deadline {
        let rc = waitpid(childPID, &status, WNOHANG)
        if rc == childPID { return }
        usleep(50000)
    }

    if pgid > 0 {
        kill(-pgid, SIGKILL)
    } else {
        kill(childPID, SIGKILL)
    }
}

/// 标准 wait(2) 状态字解码。Swift 没法 import 那几个 function-like 宏。
private func exitCode(fromWaitStatus status: Int32) -> Int32 {
    let low = status & 0x7F
    if low == 0 {
        return (status >> 8) & 0xFF
    }
    if low != 0x7F {
        return 128 + low
    }
    return 1
}

let argv = CommandLine.arguments
guard let sep = argv.firstIndex(of: "--") else { usageAndExit() }
let childArgs = Array(argv[(sep + 1)...])
guard !childArgs.isEmpty else { usageAndExit() }

let childBinary = childArgs[0]
let childArgv = childArgs

let spawnResult: Int32 = childArgv.withUnsafeBufferPointer { buffer in
    var cStrings: [UnsafeMutablePointer<CChar>?] = buffer.map { strdup($0) }
    cStrings.append(nil)
    defer { cStrings.forEach { if let p = $0 { free(p) } } }

    return cStrings.withUnsafeMutableBufferPointer { cBuffer in
        var pid: pid_t = 0
        let rc: Int32 = childBinary.withCString { childPath in
            posix_spawnp(&pid, childPath, nil, nil, cBuffer.baseAddress, environ)
        }
        if rc == 0, pid > 0 {
            globalChildPID = pid
        }
        return rc
    }
}

guard spawnResult == 0, globalChildPID > 0 else {
    fputs("CCBarClaudeWatchdog: failed to spawn child: \(childBinary) (rc=\(spawnResult))\n", stderr)
    Darwin.exit(WatchdogExitCode.spawnFailed)
}

// 给 child 一个独立进程组,这样 kill 整组才不会误伤到 watchdog 自己。
_ = setpgid(globalChildPID, globalChildPID)

private func terminateChild() {
    if globalChildPID > 0 {
        killProcessTree(childPID: globalChildPID)
    }
}

private func handleTerminationSignal(_ sig: Int32) {
    globalShouldTerminate = sig
}

signal(SIGTERM, handleTerminationSignal)
signal(SIGINT, handleTerminationSignal)
signal(SIGHUP, handleTerminationSignal)

var status: Int32 = 0
while true {
    let rc = waitpid(globalChildPID, &status, WNOHANG)
    if rc == globalChildPID {
        Darwin.exit(exitCode(fromWaitStatus: status))
    }

    if globalShouldTerminate != 0 {
        let sig = globalShouldTerminate
        terminateChild()
        _ = waitpid(globalChildPID, &status, 0)
        Darwin.exit(128 + sig)
    }

    // 父进程(cc-bar)崩了或者被强杀,我们也跟着收尾,避免变孤儿。
    if getppid() == 1 {
        terminateChild()
        _ = waitpid(globalChildPID, &status, 0)
        Darwin.exit(exitCode(fromWaitStatus: status))
    }

    usleep(200_000)
}
