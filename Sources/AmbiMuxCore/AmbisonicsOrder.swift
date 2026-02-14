public nonisolated enum AmbisonicsOrder: Int, CaseIterable, Sendable {
    case first = 1
    case second = 2
    case third = 3

    /// Channel count for ACN ambisonics: \((order + 1)^2).
    public var channelCount: Int {
        let o = rawValue
        return (o + 1) * (o + 1)
    }

    public init?(channelCount: Int) {
        guard let match = Self.allCases.first(where: { $0.channelCount == channelCount }) else {
            return nil
        }
        self = match
    }

    public static var allowedChannelCounts: [Int] {
        Self.allCases.map(\.channelCount).sorted()
    }
}
