import Darwin
import Foundation

/// Finds this Mac's own IPv4 addresses, preferring VPN tunnels (utun/tun/tap/ppp) over the
/// regular interfaces, so $LHOST points at the address the target can reach you on.
enum LocalAddress {
    struct Interface: Identifiable {
        let name: String
        let address: String
        var id: String { name + address }
        var isTunnel: Bool {
            name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
        }
    }

    /// All IPv4 interfaces that are up, tunnels first, loopback excluded.
    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(truncatingIfNeeded: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let address = String(cString: host)
                if !address.hasPrefix("169.254.") {
                    result.append(Interface(name: name, address: address))
                }
            }
        }
        return result.sorted { a, b in
            if a.isTunnel != b.isTunnel { return a.isTunnel }
            return a.name < b.name
        }
    }

    /// The best guess for $LHOST: the first tunnel address, otherwise the first interface.
    static func suggested() -> Interface? {
        interfaces().first
    }
}
