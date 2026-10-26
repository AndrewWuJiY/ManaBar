import Foundation

/// Cursor 个人账期额度。接口未公开,失败时由调用方保留上一份快照。
/// 团队席位经常不返回 `planUsage`,此时给出明确错误,不把空响应当成 0%。
enum CursorQuotaClient {
    static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!

    nonisolated static func fetch(accessToken: String) async -> Result<QuotaSnapshot, QuotaError> {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { return .failure(.transport("\(error)")) }
        guard let http = resp as? HTTPURLResponse else {
            return .failure(.transport("non-http"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            let oneLine = msg.replacingOccurrences(of: "\n", with: " ")
            let clipped = oneLine.count > 180 ? String(oneLine.prefix(180)) : oneLine
            return .failure(.http(http.statusCode, clipped))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.decode("not json object"))
        }
        return parse(root: root)
    }

    nonisolated static func parse(root: [String: Any]) -> Result<QuotaSnapshot, QuotaError> {
        guard let plan = object(root, "planUsage", "plan_usage") else {
            return .failure(.unsupported(
                "Cursor 没有返回个人包含额度(团队席位常见),暂不支持"
            ))
        }
        guard let used = usedPercent(plan) else {
            return .failure(.unsupported(
                "Cursor 当前套餐没有可显示的个人包含额度"
            ))
        }
        let cycleStart = epochDate(value(root, "billingCycleStart", "billing_cycle_start"))
        let cycleEnd = epochDate(value(root, "billingCycleEnd", "billing_cycle_end"))
        let windowSeconds: Int? = {
            guard let cycleStart, let cycleEnd else { return nil }
            let seconds = Int(cycleEnd.timeIntervalSince(cycleStart))
            return seconds > 0 ? seconds : nil
        }()
        let billing = QuotaWindow(usedPercent: used, resetsAt: cycleEnd, windowSeconds: windowSeconds)
        return .success(QuotaSnapshot(
            app: .cursor,
            fiveHour: nil,
            weekly: nil,
            weeklyOpus: nil,
            weeklySonnet: nil,
            planType: nil,
            fetchedAt: Date(),
            billingCycle: billing,
            onDemand: onDemandWindow(root, resetsAt: cycleEnd, windowSeconds: windowSeconds)
        ))
    }

    /// 已用百分比。优先用剩余 / 上限(美分),和菜单栏「剩余」口径一致。
    nonisolated private static func usedPercent(_ plan: [String: Any]) -> Double? {
        let limit = doubleValue(value(plan, "limit", "limit"))
        let remaining = doubleValue(value(plan, "remaining", "remaining"))
        if let limit, limit > 0, let remaining {
            return clamp((1 - remaining / limit) * 100)
        }
        let included = doubleValue(value(plan, "includedSpend", "included_spend"))
        if let limit, limit > 0, let included {
            return clamp(included / limit * 100)
        }
        if let total = doubleValue(value(plan, "totalPercentUsed", "total_percent_used")) {
            return clamp(total)
        }
        return nil
    }

    nonisolated private static func onDemandWindow(
        _ root: [String: Any],
        resetsAt: Date?,
        windowSeconds: Int?
    ) -> QuotaWindow? {
        guard let spend = object(root, "spendLimitUsage", "spend_limit_usage") else { return nil }
        let limit = doubleValue(value(spend, "individualLimit", "individual_limit"))
        guard let limit, limit > 0 else { return nil }
        let usedCents = doubleValue(value(spend, "individualUsed", "individual_used"))
        let remaining = doubleValue(value(spend, "individualRemaining", "individual_remaining"))
        let used: Double
        if let usedCents {
            used = clamp(usedCents / limit * 100)
        } else if let remaining {
            used = clamp((1 - remaining / limit) * 100)
        } else {
            return nil
        }
        return QuotaWindow(usedPercent: used, resetsAt: resetsAt, windowSeconds: windowSeconds)
    }

    nonisolated private static func object(_ dict: [String: Any], _ camel: String, _ snake: String) -> [String: Any]? {
        (dict[camel] as? [String: Any]) ?? (dict[snake] as? [String: Any])
    }

    nonisolated private static func value(_ dict: [String: Any], _ camel: String, _ snake: String) -> Any? {
        dict[camel] ?? dict[snake]
    }

    nonisolated private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    /// 账期字段有时是毫秒字符串,有时是秒。10 位及以下按秒。
    nonisolated private static func epochDate(_ any: Any?) -> Date? {
        guard let raw = doubleValue(any), raw > 0 else { return nil }
        let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    nonisolated private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
