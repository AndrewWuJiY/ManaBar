import Foundation

enum UsageApp: String, Sendable, Codable, Hashable, CaseIterable {
    case codex
    case claude
}

/// 单次 API 调用解析出的用量记录（内存中流转，不直接持久化）。
struct UsageEntry: Sendable, Equatable {
    var app: UsageApp
    var model: String
    var day: Date              // 本地时区 0 点
    var timestamp: Date
    var inputTokens: Int       // 已扣 cacheRead（Codex 解析时已处理）
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int
    var costUSD: Decimal
}

/// (day, app, model) 聚合桶；UsageAggregator 内存表的值。
struct UsageBucket: Sendable, Equatable, Codable {
    var app: UsageApp
    var model: String
    var day: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int
    var costUSD: Decimal
}

struct UsageTotals: Sendable, Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var costUSD: Decimal = 0

    static let zero = UsageTotals()

    mutating func add(_ bucket: UsageBucket) {
        inputTokens += bucket.inputTokens
        outputTokens += bucket.outputTokens
        cacheReadTokens += bucket.cacheReadTokens
        cacheCreationTokens += bucket.cacheCreationTokens
        costUSD += bucket.costUSD
    }

    /// 含缓存的输入侧 token(input + cache_read + cache_creation)。与 cc-switch / ccusage 的 input 口径一致。
    var inputWithCacheTokens: Int {
        inputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// 全量 token(输入含缓存 + 输出)。与 cc-switch / ccusage 的总量口径一致。
    var totalTokens: Int {
        inputWithCacheTokens + outputTokens
    }
}

/// Decimal <-> String 编解码，避免 Double 精度漂。
extension Decimal {
    var asPlainString: String {
        var copy = self
        return NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
    }

    init?(plainString: String) {
        self.init(string: plainString, locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// UsageBucket 的 Codable 用 Decimal 字符串。
extension UsageBucket {
    enum CodingKeys: String, CodingKey {
        case app, model, day, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, costUSD
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.app = try c.decode(UsageApp.self, forKey: .app)
        self.model = try c.decode(String.self, forKey: .model)
        self.day = try c.decode(Date.self, forKey: .day)
        self.inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        self.outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        self.cacheReadTokens = try c.decode(Int.self, forKey: .cacheReadTokens)
        self.cacheCreationTokens = try c.decode(Int.self, forKey: .cacheCreationTokens)
        let costStr = try c.decode(String.self, forKey: .costUSD)
        self.costUSD = Decimal(plainString: costStr) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(app, forKey: .app)
        try c.encode(model, forKey: .model)
        try c.encode(day, forKey: .day)
        try c.encode(inputTokens, forKey: .inputTokens)
        try c.encode(outputTokens, forKey: .outputTokens)
        try c.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try c.encode(cacheCreationTokens, forKey: .cacheCreationTokens)
        try c.encode(costUSD.asPlainString, forKey: .costUSD)
    }
}

enum UsageDay {
    /// 本地时区 0 点。
    static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
