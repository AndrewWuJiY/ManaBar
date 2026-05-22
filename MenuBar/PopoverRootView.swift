import SwiftUI
import AppKit

struct PopoverRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 10) {
                QuotaOverviewCard(
                    title: "Codex",
                    subtitle: "OpenAI",
                    tint: .codexAccent,
                    snapshot: appState.codexQuota,
                    error: appState.codexQuotaError
                )

                QuotaOverviewCard(
                    title: "Claude",
                    subtitle: "Anthropic",
                    tint: .claudeAccent,
                    snapshot: appState.claudeQuota,
                    error: appState.claudeQuotaError
                )
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CCBar")
                .font(.headline)

            Spacer()

            if let status = headerStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(isRefreshing)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private var headerStatus: String? {
        let latest = [
            appState.codexRefreshState.lastSuccessAt,
            appState.claudeRefreshState.lastSuccessAt
        ].compactMap { $0 }.max()

        if let latest {
            return "Updated \(Self.relativeAge(from: latest)) ago"
        }

        if appState.codexQuotaError != nil || appState.claudeQuotaError != nil {
            return "Refresh failed"
        }

        return nil
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            let startedAt = Date()
            await appState.refreshNow()

            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < 0.5 {
                try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
            }

            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private static func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

private struct QuotaOverviewCard: View {
    let title: String
    let subtitle: String
    let tint: Color
    let snapshot: QuotaSnapshot?
    let error: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header

                VStack(spacing: 8) {
                    QuotaWindowRow(label: "5h", window: snapshot?.fiveHour, tint: tint)
                    QuotaWindowRow(label: "1w", window: snapshot?.weekly, tint: tint)
                }

                HStack {
                    Text("Today cost")
                    Text("今日 cost")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("-")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if let message = shortError(error) {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if snapshot == nil {
                    Text("waiting for data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func shortError(_ error: String?) -> String? {
        guard let error, !error.isEmpty else { return nil }
        let oneLine = error.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count <= 110 { return oneLine }
        return String(oneLine.prefix(107)) + "..."
    }
}

private struct QuotaWindowRow: View {
    let label: String
    let window: QuotaWindow?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, alignment: .leading)

                ProgressView(value: progressValue)
                    .tint(statusColor)

                Text(percentText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack {
                Spacer()
                    .frame(width: 32)
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var progressValue: Double {
        guard let window else { return 0 }
        return window.remainingPercent / 100
    }

    private var percentText: String {
        guard let window else { return "--%" }
        return "\(Int(window.remainingPercent.rounded()))%"
    }

    private var resetText: String {
        guard let window else { return "waiting for data" }
        guard let resetsAt = window.resetsAt else { return "reset unknown" }
        let seconds = max(0, Int(resetsAt.timeIntervalSince(Date())))
        if seconds < 60 {
            return "reset in <1m"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "reset in \(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0
                ? "reset in \(hours)h \(remainingMinutes)m"
                : "reset in \(hours)h"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours > 0
            ? "reset in \(days)d \(remainingHours)h"
            : "reset in \(days)d"
    }

    private var statusColor: Color {
        guard let window else { return .secondary }
        let remaining = window.remainingPercent
        if remaining <= 0 { return .red }
        if remaining < 20 { return .orange }
        return tint
    }
}

private extension Color {
    static var codexAccent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.596, green: 0.596, blue: 0.616, alpha: 1)
                : NSColor(calibratedRed: 0.424, green: 0.424, blue: 0.439, alpha: 1)
        })
    }

    static var claudeAccent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.902, green: 0.541, blue: 0.431, alpha: 1)
                : NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
        })
    }
}
