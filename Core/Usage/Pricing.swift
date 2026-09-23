import Foundation
import CryptoKit

/// 模型价格（USD / 百万 token）。命中不到的模型 cost 计 0，token 仍记录。
nonisolated struct ModelPrice: Sendable, Equatable {
    var input: Decimal
    var output: Decimal
    var cacheRead: Decimal
    var cacheCreation: Decimal
}

/// 价格查询入口。两层表：
/// 1. 远程表（`RemotePricing` 从 LiteLLM 拉取，运行时注入，**优先**）；
/// 2. 内置表 `builtInTable`（写死，远程缺模型 / 从未拉取成功时兜底）。
/// 扫描器在后台线程调用，所以对外成员都标 `nonisolated`，可变状态由 `PricingStore` 加锁保护。
enum Pricing {
    /// 内置兜底表，与 cc-switch `seed_model_pricing` / CodexBar `CostUsagePricing` 对齐（2026 上半年价位）。
    /// 键为归一化后的模型名（剥 `openai/` 前缀和末尾 `-YYYYMMDD` / `-YYYY-MM-DD` 日期段）。
    nonisolated static let builtInTable: [String: ModelPrice] = [
        // —— Claude 5 / 4.x 系（input 已不含 cache_read）——
        "claude-fable-5":    .init(input: 10,  output: 50,  cacheRead: 1.00, cacheCreation: 12.50),
        // Opus 5.5 官方降价：$4 / $20，cache read 0.05x（$0.20），5 分钟 cache write 1.25x（$5）；1M 上下文无溢价
        "claude-opus-5-5":   .init(input: 4,   output: 20,  cacheRead: 0.20, cacheCreation: 5.00),
        // Opus 5 沿用 Opus 4.5 以来未变的 $5 / $25 档
        "claude-opus-5":     .init(input: 5,   output: 25,  cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-8":   .init(input: 5,   output: 25,  cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-7":   .init(input: 5,   output: 25,  cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-6":   .init(input: 5,   output: 25,  cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-5":   .init(input: 5,   output: 25,  cacheRead: 0.50, cacheCreation: 6.25),
        "claude-opus-4-1":   .init(input: 15,  output: 75,  cacheRead: 1.50, cacheCreation: 18.75),
        "claude-opus-4":     .init(input: 15,  output: 75,  cacheRead: 1.50, cacheCreation: 18.75),
        // Sonnet 5 原定 2026-09-01 涨到 $3/$15 的计划已取消,$2/$10 即官方标准价,无需上调
        "claude-sonnet-5":   .init(input: 2,   output: 10,  cacheRead: 0.20, cacheCreation: 2.50),
        "claude-sonnet-4-7": .init(input: 3,   output: 15,  cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4-6": .init(input: 3,   output: 15,  cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4-5": .init(input: 3,   output: 15,  cacheRead: 0.30, cacheCreation: 3.75),
        "claude-sonnet-4":   .init(input: 3,   output: 15,  cacheRead: 0.30, cacheCreation: 3.75),
        "claude-haiku-4-5":  .init(input: 1,   output: 5,   cacheRead: 0.10, cacheCreation: 1.25),
        "claude-haiku-4":    .init(input: 0.8, output: 4,   cacheRead: 0.08, cacheCreation: 1.0),

        // —— Codex / GPT-5 系（input 含 cache_read，调用侧已扣 billable）。
        // 注：实际 5.5 在 >272k context 有阶梯价；本表采用 cc-switch 一致的「单档」价。
        "gpt-5":             .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5-mini":        .init(input: 0.25, output: 2,   cacheRead: 0.025, cacheCreation: 0),
        "gpt-5-nano":        .init(input: 0.05, output: 0.40, cacheRead: 0.005, cacheCreation: 0),
        "gpt-5-codex":       .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.1":           .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.1-codex":     .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.2":           .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.3":           .init(input: 1.25, output: 10,  cacheRead: 0.125, cacheCreation: 0),
        "gpt-5.4":           .init(input: 2.50, output: 15,  cacheRead: 0.25,  cacheCreation: 0),
        "gpt-5.4-codex":     .init(input: 2.50, output: 15,  cacheRead: 0.25,  cacheCreation: 0),
        "gpt-5.5":           .init(input: 5,    output: 30,  cacheRead: 0.50,  cacheCreation: 0),
        "gpt-5.5-codex":     .init(input: 5,    output: 30,  cacheRead: 0.50,  cacheCreation: 0),
        "gpt-5.5-pro":       .init(input: 5,    output: 30,  cacheRead: 0.50,  cacheCreation: 0),
        "gpt-5.6":           .init(input: 5,    output: 30,  cacheRead: 0.50,  cacheCreation: 0),
        // 5.6 sol/terra/luna 取官方 Standard 短上下文档（>272k 有阶梯价，维持单档口径）
        "gpt-5.6-sol":       .init(input: 5,    output: 30,  cacheRead: 0.50,  cacheCreation: 6.25),
        "gpt-5.6-terra":     .init(input: 2.50, output: 15,  cacheRead: 0.25,  cacheCreation: 3.125),
        "gpt-5.6-luna":      .init(input: 1,    output: 6,   cacheRead: 0.10,  cacheCreation: 1.25),

        // —— GPT-6 系 ——
        // Astra 官方 Standard 短上下文档（≤272k）：$10 in / $1 cache read / $12.50 cache write / $50 out。
        // >272k 长上下文按整请求重计（input、cache 2x，output 1.5x）；Fast 模式 2x；Batch/Flex 0.5x。
        // 与 5.6 系一致，本表仍只取 Standard 短上下文单档。
        "gpt-6-astra":       .init(input: 10,   output: 50,  cacheRead: 1.00,  cacheCreation: 12.50),
        // Sol / Luna 2026-09-22 发布，官方 Standard 短上下文档（≤272k），同样只取单档：
        // Sol $2 in / $0.20 cache read / $2.50 cache write / $10 out；Luna $0.10 / $0.01 / $0.125 / $0.50。
        "gpt-6-sol":         .init(input: 2,    output: 10,  cacheRead: 0.20,  cacheCreation: 2.50),
        "gpt-6-luna":        .init(input: 0.10, output: 0.50, cacheRead: 0.01, cacheCreation: 0.125),
        // Codex 侧若出现带后缀的变体，官方未单独公布价，暂按 Astra 同价登记
        "gpt-6-astra-codex": .init(input: 10,   output: 50,  cacheRead: 1.00,  cacheCreation: 12.50),
        "codex-mini-latest": .init(input: 1.50, output: 6,   cacheRead: 0.375, cacheCreation: 0)
        // codex-auto-review 内部 review，官方未公开计费；不入表 → cost=0，token 仍记录
    ]

    /// 归一化模型名：去 `openai/` 前缀；剥末尾 `-YYYY-MM-DD` 或 `-YYYYMMDD` 日期后缀；
    /// 兼容 Vertex AI 的 `@日期` 写法。
    nonisolated static func normalize(model: String) -> String {
        var m = model
        if m.hasPrefix("openai/") {
            m.removeFirst("openai/".count)
        }
        // Vertex 风格：`name@YYYYMMDD`
        if let at = m.firstIndex(of: "@") {
            m = String(m[m.startIndex..<at])
        }
        // Anthropic 风格：`-YYYYMMDD` 或 `-YYYY-MM-DD`
        let patterns = [#"-\d{4}-\d{2}-\d{2}$"#, #"-\d{8}$"#]
        for pat in patterns {
            if let range = m.range(of: pat, options: .regularExpression) {
                m.removeSubrange(range)
                break
            }
        }
        return m.lowercased()
    }

    nonisolated private static let perMillion: Decimal = 1_000_000

    nonisolated private static let store = PricingStore(builtIn: builtInTable)

    /// 查单个模型价格：远程表优先，内置表兜底；都没有返回 nil。
    nonisolated static func price(for model: String) -> ModelPrice? {
        store.price(for: normalize(model: model))
    }

    /// 注入远程价格表（键须已归一化）。返回合并后的指纹是否变化——变化时调用方需触发全量重算。
    @discardableResult
    nonisolated static func applyRemote(_ table: [String: ModelPrice]) -> Bool {
        store.setRemote(table)
    }

    /// 计算单次调用花费。
    /// - Parameters:
    ///   - app: 用于隐含的 cache_read 语义；Codex 含、Claude 不含（调用方传 input 时已自处理）。
    ///   - input/output/cacheRead/cacheCreation: 直接乘价。
    nonisolated static func cost(
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheCreation: Int
    ) -> Decimal {
        guard let p = price(for: model) else { return 0 }
        let i = Decimal(input)     * p.input        / perMillion
        let o = Decimal(output)    * p.output       / perMillion
        let cr = Decimal(cacheRead) * p.cacheRead   / perMillion
        let cc = Decimal(cacheCreation) * p.cacheCreation / perMillion
        return i + o + cr + cc
    }

    /// UI 用：查不到价格的模型显示「未定价」而不是 $0.00。
    nonisolated static func hasPrice(model: String) -> Bool {
        price(for: model) != nil
    }

    /// 合并后价格表（远程覆盖内置）的内容指纹（SHA-256，确定性，跨进程稳定）。
    /// 扫描状态 / 汇总缓存持久化它；表一变（新增模型、改价、远程表更新）→ 指纹变 →
    /// 缓存自动失效并全量重扫重算历史桶，无需手动 bump 版本号，避免「改了价却忘了重算」。
    nonisolated static var fingerprint: String {
        store.fingerprint
    }

    nonisolated fileprivate static func digest(of table: [String: ModelPrice]) -> String {
        let body = table.keys.sorted().map { key -> String in
            let p = table[key]!
            return "\(key):\(p.input)/\(p.output)/\(p.cacheRead)/\(p.cacheCreation)"
        }.joined(separator: ";")
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 价格表的可变部分（远程表）+ 合并指纹缓存。扫描器在后台线程读、MainActor 写，用锁保护。
nonisolated final class PricingStore: @unchecked Sendable {
    private let lock = NSLock()
    private let builtIn: [String: ModelPrice]
    private var remote: [String: ModelPrice] = [:]
    private var cachedFingerprint: String

    init(builtIn: [String: ModelPrice]) {
        self.builtIn = builtIn
        self.cachedFingerprint = Pricing.digest(of: builtIn)
    }

    func price(for normalizedKey: String) -> ModelPrice? {
        lock.lock(); defer { lock.unlock() }
        return remote[normalizedKey] ?? builtIn[normalizedKey]
    }

    var fingerprint: String {
        lock.lock(); defer { lock.unlock() }
        return cachedFingerprint
    }

    /// 替换远程表并重算合并指纹；返回指纹是否变化。
    func setRemote(_ table: [String: ModelPrice]) -> Bool {
        let merged = builtIn.merging(table) { _, remote in remote }
        let newFingerprint = Pricing.digest(of: merged)
        lock.lock(); defer { lock.unlock() }
        remote = table
        let changed = newFingerprint != cachedFingerprint
        cachedFingerprint = newFingerprint
        return changed
    }
}

// MARK: - 远程价格表（LiteLLM）

/// 从 LiteLLM 社区维护的 `model_prices_and_context_window.json` 拉取 anthropic / openai 模型价格，
/// 解析成与内置表同口径的 `[归一化模型名: ModelPrice]`（USD / 百万 token）后注入 `Pricing`。
///
/// - 只取 `litellm_provider` 为 anthropic / openai、且有 input + output 单价的条目；
///   键剥 `anthropic/` `openai/` 前缀后仍含 `/` 或 `:`（其他渠道、微调模型）的跳过。
/// - 同一归一化名有多个条目时：不带日期的原名优先，否则取排序最后（日期最新）的一条，保证结果确定、指纹稳定。
/// - 只取标准短上下文单档（忽略 `*_above_*_tokens` 阶梯价），与内置表口径一致。
/// - 拉取失败 / 内容异常一律抛错，调用方保留当前表（上次缓存或内置表），不清空。
/// - 解析后的精简表缓存到 `Application Support/ManaBar/remote-pricing.json`，启动时先用缓存，离线也有远程价。
nonisolated enum RemotePricing {
    /// 依次尝试：GitHub raw → jsDelivr 镜像（国内网络下 raw 域名不稳时兜底）。
    static let sourceURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!,
        URL(string: "https://cdn.jsdelivr.net/gh/BerriAI/litellm@main/model_prices_and_context_window.json")!
    ]

    /// 距上次成功拉取超过这个时长才重新拉（源文件约 3MB，不必频繁）。
    static let refreshInterval: TimeInterval = 12 * 60 * 60

    private static let providers: Set<String> = ["anthropic", "openai"]
    private static let keyPrefixes = ["anthropic/", "openai/"]
    /// 解析出的模型数低于该值视为内容异常（源文件格式变了 / 被截断），不采用。
    private static let minimumModelCount = 20
    private static let fileName = "remote-pricing.json"
    private static let bundleDirectory = "ManaBar"

    nonisolated enum FetchError: Error {
        case malformed
        case tooFewModels(Int)
    }

    nonisolated struct CachedPrice: Codable, Sendable {
        var input: String
        var output: String
        var cacheRead: String
        var cacheCreation: String
    }

    nonisolated struct CachePayload: Codable, Sendable {
        static let currentVersion = 1
        var version: Int = CachePayload.currentVersion
        var fetchedAt: Date
        var source: String
        var models: [String: CachedPrice]
    }

    // MARK: 拉取

    /// 按 `sourceURLs` 顺序尝试，第一个成功解析的即返回。会做网络 + 约 3MB JSON 解析，调用方放到后台 Task。
    static func fetch() async throws -> CachePayload {
        var lastError: Error = URLError(.unknown)
        for url in sourceURLs {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let table = try parse(data: data)
                return CachePayload(fetchedAt: Date(), source: url.host() ?? url.absoluteString, models: encode(table))
            } catch {
                print("[pricing 价格] 远程价格表拉取失败 remote fetch failed (\(url.host() ?? "?")): \(error)")
                lastError = error
            }
        }
        throw lastError
    }

    static func parse(data: Data) throws -> [String: ModelPrice] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.malformed
        }
        var result: [String: ModelPrice] = [:]
        var exactKeys: Set<String> = []
        for rawKey in root.keys.sorted() {
            guard let entry = root[rawKey] as? [String: Any],
                  let provider = entry["litellm_provider"] as? String,
                  providers.contains(provider),
                  let input = perMillion(entry["input_cost_per_token"]),
                  let output = perMillion(entry["output_cost_per_token"])
            else { continue }

            var key = rawKey
            for prefix in keyPrefixes where key.hasPrefix(prefix) {
                key.removeFirst(prefix.count)
            }
            guard !key.contains("/"), !key.contains(":") else { continue }

            let normalized = Pricing.normalize(model: key)
            let isExact = normalized == key.lowercased()
            if exactKeys.contains(normalized) && !isExact { continue }
            result[normalized] = ModelPrice(
                input: input,
                output: output,
                cacheRead: perMillion(entry["cache_read_input_token_cost"]) ?? 0,
                cacheCreation: perMillion(entry["cache_creation_input_token_cost"]) ?? 0
            )
            if isExact { exactKeys.insert(normalized) }
        }
        guard result.count >= minimumModelCount else {
            throw FetchError.tooFewModels(result.count)
        }
        return result
    }

    /// LiteLLM 单价是 USD / token（Double），换算成 USD / 百万 token 并四舍五入到 6 位，消掉浮点尾差（2e-06 × 1e6 = 1.9999999999999998）。
    private static func perMillion(_ value: Any?) -> Decimal? {
        guard let number = value as? NSNumber else { return nil }
        let perToken = number.doubleValue
        guard perToken.isFinite, perToken >= 0 else { return nil }
        var raw = Decimal(perToken * 1_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 6, .plain)
        return rounded
    }

    // MARK: 缓存

    static func table(from payload: CachePayload) -> [String: ModelPrice] {
        var table: [String: ModelPrice] = [:]
        for (key, p) in payload.models {
            guard let input = Decimal(plainString: p.input),
                  let output = Decimal(plainString: p.output),
                  let cacheRead = Decimal(plainString: p.cacheRead),
                  let cacheCreation = Decimal(plainString: p.cacheCreation)
            else { continue }
            table[key] = ModelPrice(input: input, output: output, cacheRead: cacheRead, cacheCreation: cacheCreation)
        }
        return table
    }

    private static func encode(_ table: [String: ModelPrice]) -> [String: CachedPrice] {
        table.mapValues {
            CachedPrice(
                input: $0.input.asPlainString,
                output: $0.output.asPlainString,
                cacheRead: $0.cacheRead.asPlainString,
                cacheCreation: $0.cacheCreation.asPlainString
            )
        }
    }

    static func loadCache() -> CachePayload? {
        guard let data = try? Data(contentsOf: cacheFileURL()),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              payload.version == CachePayload.currentVersion
        else { return nil }
        return payload
    }

    static func saveCache(_ payload: CachePayload) throws {
        let url = cacheFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(payload).write(to: url, options: [.atomic])
    }

    static func cacheFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent(bundleDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
