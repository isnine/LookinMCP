import Foundation
import Network

/// Scans simulator ports (47164-47169) to find a running LookinServer.
struct PortScanner: Sendable {

    static let portRange = 47164...47169

    struct ScanResult: Sendable {
        let port: Int
    }

    /// Tries all ports concurrently and returns the first one that accepts a TCP connection.
    static func findAvailablePort(timeout: TimeInterval = 2.0) async -> ScanResult? {
        return await withTaskGroup(of: ScanResult?.self) { group in
            for port in portRange {
                group.addTask {
                    let success = await testPort(port, timeout: timeout)
                    return success ? ScanResult(port: port) : nil
                }
            }

            for await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    static func findAllAvailablePorts(timeout: TimeInterval = 2.0) async -> [ScanResult] {
        return await withTaskGroup(of: ScanResult?.self) { group in
            for port in portRange {
                group.addTask {
                    let success = await testPort(port, timeout: timeout)
                    return success ? ScanResult(port: port) : nil
                }
            }

            var results: [ScanResult] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results.sorted { $0.port < $1.port }
        }
    }

    private static func testPort(_ port: Int, timeout: TimeInterval) async -> Bool {
        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        return await withCheckedContinuation { continuation in
            final class ResumeOnce: @unchecked Sendable {
                private var done = false
                private let lock = os_unfair_lock_t.allocate(capacity: 1)
                init() { lock.initialize(to: os_unfair_lock()) }
                deinit { lock.deinitialize(count: 1); lock.deallocate() }
                func tryResume(_ body: () -> Void) {
                    os_unfair_lock_lock(lock)
                    guard !done else { os_unfair_lock_unlock(lock); return }
                    done = true
                    os_unfair_lock_unlock(lock)
                    body()
                }
            }
            let once = ResumeOnce()
            let queue = DispatchQueue(label: "com.lookinmcp.portscan.\(port)")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.tryResume {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    once.tryResume {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                once.tryResume {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
