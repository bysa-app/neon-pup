import Foundation
import Security
import NeonPupCore

/// Where the person's roads live (own roads, 2026-10-10): the Keychain, never plain files.
public protocol RoadStore: AnyObject {
    func load() -> [RoadSpec]
    func save(_ roads: [RoadSpec]) -> Bool
}

public final class KeychainRoadStore: RoadStore {
    static let account = "roads"
    private let service: String

    /// `service` is only changed by tests, so they never touch the real roads.
    public init(service: String = "co.holinic.neonpup.roads") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account]
    }

    public func load() -> [RoadSpec] {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let roads = try? JSONDecoder().decode([RoadSpec].self, from: data) else { return [] }
        return Self.usable(roads)
    }

    /// Anything stored is re-checked: a bad road is dropped on its own (not all of them), and the cap holds.
    public static func usable(_ roads: [RoadSpec]) -> [RoadSpec] {
        Array(roads.filter { RoadValidator.problems($0).isEmpty }.prefix(RoadValidator.maxRoads))
    }

    public func save(_ roads: [RoadSpec]) -> Bool {
        guard roads.count <= RoadValidator.maxRoads, let data = try? JSONEncoder().encode(roads) else { return false }
        if roads.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // Always re-create the item so its access rules are Neon Pup's own (security review: an update would
        // keep the rules of an item another program planted). Keep the old data and put it back if the add
        // fails, so a failed save never loses the roads (Codex review).
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var old: CFTypeRef?
        let hadOld = SecItemCopyMatching(read as CFDictionary, &old) == errSecSuccess
        SecItemDelete(query as CFDictionary)
        if add(data) { return true }
        if hadOld, let previous = old as? Data { _ = add(previous) }
        return false
    }

    private func add(_ data: Data) -> Bool {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// For previews and tests.
public final class InMemoryRoadStore: RoadStore {
    public var roads: [RoadSpec]
    public init(_ roads: [RoadSpec] = []) { self.roads = roads }
    public func load() -> [RoadSpec] { roads }
    public func save(_ roads: [RoadSpec]) -> Bool { self.roads = roads; return true }
}
