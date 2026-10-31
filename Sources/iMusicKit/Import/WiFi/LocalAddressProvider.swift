import Darwin
import Foundation

/// Address discovery boundary independent of listener startup and HTTP request handling.
protocol LocalAddressProviding: Sendable {
    /// Returns all active IPv4 hosts, with a loopback fallback when no interface is available.
    func addresses() -> [String]
}

/// Enumerates usable interfaces without binding sockets or modifying system networking.
struct InterfaceAddressProvider: LocalAddressProviding {
    /// Collects active IPv4 interface addresses matching the listener's address family.
    /// Includes Ethernet, Wi-Fi, bridges, and tunnels; loopback is only a last-resort fallback.
    func addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return ["localhost"] }
        defer { freeifaddrs(interfaces) }
        var hosts = Set<String>()
        var pointer = interfaces
        while let value = pointer {
            defer { pointer = value.pointee.ifa_next }
            let flags = value.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0,
                flags & UInt32(IFF_LOOPBACK) == 0,
                let addr = value.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let address = String(cString: host)
                guard address != "0.0.0.0" else { continue }
                hosts.insert(address)
            }
        }
        return hosts.isEmpty
            ? ["localhost"]
            : hosts.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
    }
}
