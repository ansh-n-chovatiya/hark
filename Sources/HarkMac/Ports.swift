import Darwin
import Foundation

/// What is listening on this Mac, read from the system's process and socket tables (libproc): no shell, no command. Only
/// the user's own processes are visible, which is what is wanted.
struct ListeningPort: Sendable, Equatable {
    let port: Int
    let pid: Int32
    let name: String
    /// The folder the process is running in, by name only.
    let folder: String?
}

enum Ports {
    static func listening() -> [ListeningPort] {
        var found: [Int: ListeningPort] = [:]
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) / MemoryLayout<Int32>.size + 16)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 0 {
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size + 4)
            let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size))
            guard got > 0 else { continue }
            for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                let read = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
                guard read == Int32(MemoryLayout<socket_fdinfo>.size),
                      info.psi.soi_kind == Int32(SOCKINFO_TCP),
                      info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)))
                guard port > 0, found[port] == nil else { continue }
                found[port] = ListeningPort(port: port, pid: pid, name: name(of: pid), folder: folder(of: pid))
            }
        }
        return found.values.sorted { $0.port < $1.port }
    }

    static func isListening(_ port: Int) -> Bool { listening().contains { $0.port == port } }

    private static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    private static func folder(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? nil : last
    }

    /// Plain words for what is on a port, or on all of them.
    static func describe(_ port: Int?) -> String {
        let all = listening()
        if let port {
            guard let one = all.first(where: { $0.port == port }) else { return "Nothing is listening on port \(port)." }
            return "Port \(port): \(one.name)" + (one.folder.map { ", running in \($0)" } ?? "") + "."
        }
        guard !all.isEmpty else { return "Nothing of yours is listening on a port." }
        return all.prefix(8).map { "\($0.port) \($0.name)" + ($0.folder.map { " (\($0))" } ?? "") }.joined(separator: " \u{00B7} ")
    }
}
