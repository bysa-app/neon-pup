import Foundation

/// baidu.com is routed direct (China list), so it answers when plain internet works even if every road is down.
public struct DirectProbe: DirectProbing {
    public init() {}
    public func directInternetWorks() async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        let session = URLSession(configuration: config)
        guard let (_, response) = try? await session.data(from: URL(string: "https://www.baidu.com")!) else { return false }
        return response is HTTPURLResponse
    }
}
