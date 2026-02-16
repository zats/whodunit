import Foundation

#if os(macOS)
import Darwin

enum ProcessInspector {
    static func descendantPIDs(of root: pid_t, limit: Int = 4_096) -> [pid_t] {
        var out: [pid_t] = []
        out.reserveCapacity(64)

        var queue: [pid_t] = [root]
        var seen = Set<pid_t>()
        seen.insert(root)

        while let current = queue.first {
            queue.removeFirst()
            guard out.count < limit else { break }

            let children = childPIDs(of: current)
            for child in children {
                if child <= 0 { continue }
                if seen.insert(child).inserted {
                    out.append(child)
                    queue.append(child)
                }
            }
        }

        return out
    }

    static func childPIDs(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while capacity <= 8_192 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = Int32(capacity * MemoryLayout<pid_t>.size)
            let count = proc_listchildpids(pid, &buffer, bytes)
            if count <= 0 { return [] }
            let n = Int(count)
            if n < capacity {
                return Array(buffer.prefix(n))
            }
            capacity *= 2
        }

        return []
    }

    static func processCWD(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard ret == size else { return nil }
        return cString(info.pvi_cdir.vip_path)
    }

    static func processHasOpenFile(pid: pid_t, path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return withFileDescriptors(pid: pid) { fd in
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return false }
            var vnodeInfo = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout.size(ofValue: vnodeInfo))
            let ret = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, size)
            guard ret == size else { return false }
            guard let p = cString(vnodeInfo.pvip.vip_path) else { return false }
            return (p as NSString).standardizingPath == normalized
        }
    }

    private static func withFileDescriptors(pid: pid_t, _ body: (proc_fdinfo) -> Bool) -> Bool {
        var capacityBytes = 8 * 1024
        while capacityBytes <= 1_048_576 {
            var buffer = [UInt8](repeating: 0, count: capacityBytes)
            let ret = buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return proc_pidinfo(pid, PROC_PIDLISTFDS, 0, base, Int32(capacityBytes))
            }
            if ret <= 0 { return false }

            let count = Int(ret) / MemoryLayout<proc_fdinfo>.stride
            if count == 0 { return false }

            let found = buffer.withUnsafeBytes { raw -> Bool in
                let base = raw.baseAddress!.assumingMemoryBound(to: proc_fdinfo.self)
                for i in 0..<count {
                    if body(base[i]) { return true }
                }
                return false
            }
            if found { return true }
            if Int(ret) < capacityBytes { return false }
            capacityBytes *= 2
        }

        return false
    }

    private static func cString<T>(_ tuple: T) -> String? {
        var tmp = tuple
        return withUnsafePointer(to: &tmp) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { cptr in
                let s = String(cString: cptr)
                return s.isEmpty ? nil : s
            }
        }
    }
}

#endif
