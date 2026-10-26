import Foundation

/// 按正则表达式排除文件名。无效正则会被忽略，不影响其他规则。
public struct RegexExcluder: Sendable {
    private let expressions: [NSRegularExpression]

    /// - Parameter patterns: 正则表达式列表，任一匹配即排除。
    public init(patterns: [String]) {
        expressions = patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern)
        }
    }

    /// 判断文件名是否应被排除。
    public func shouldExclude(_ name: String) -> Bool {
        let range = NSRange(location: 0, length: (name as NSString).length)
        return expressions.contains { expression in
            expression.firstMatch(in: name, range: range) != nil
        }
    }

    /// 生效中的正则数量（无效正则不计入）。
    public var activePatternCount: Int { expressions.count }
}
