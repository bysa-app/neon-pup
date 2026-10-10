import Foundation

/// pf rules for the kill switch ("seal"), loaded by the root helper into the anchor
/// com.apple/co.holinic.neonpup whenever the kill switch is wanted and the engine is NOT running:
/// while connecting, after the engine died, and while napping in China mode. Only loopback and the
/// local network (router, hotel login page) get through; DNS to the local network is blocked so a
/// sealed Mac cannot leak names like claude.ai. While the engine runs the seal is lifted and the
/// tunnel's strict routing captures every app, including Cowork's virtual machine.
public enum KillSwitchRules {
    public static let sealed = """
    # Neon Pup kill switch (co.holinic.neonpup)
    pass out quick on lo0 all
    block drop out quick proto { tcp udp } to any port 53
    pass out quick inet to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 }
    pass out quick inet6 to { fe80::/10, ff00::/8 }
    block drop out quick all

    """

    /// True when `pfctl -a <anchor> -s rules` lists no rules. pfctl adds ALTQ notices even for an empty
    /// anchor (drill 2026-10-10: they made a lifted block look stuck).
    public static func anchorIsEmpty(_ output: String) -> Bool {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .allSatisfy { $0.isEmpty || $0.contains("ALTQ") }
    }
}
