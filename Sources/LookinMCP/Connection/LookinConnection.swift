import Foundation
import Network
import os

/// Manages a TCP connection to a LookinServer instance running in an iOS Simulator.
/// Implements the Peertalk binary frame protocol:
///   Header: [version:UInt32][type:UInt32][tag:UInt32][payloadSize:UInt32] — all big-endian
final class LookinConnection: @unchecked Sendable {

    struct Frame: Sendable {
        let type: UInt32
        let tag: UInt32
        let payload: Data?
    }

    enum ConnectionError: LocalizedError, Sendable {
        case notConnected
        case alreadyConnected
        case connectionFailed(String)
        case timeout
        case readError(String)
        case sendError(String)
        case invalidFrame

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Not connected to any LookinServer"
            case .alreadyConnected: return "Already connected"
            case .connectionFailed(let msg): return "Connection failed: \(msg)"
            case .timeout: return "Request timed out"
            case .readError(let msg): return "Read error: \(msg)"
            case .sendError(let msg): return "Send error: \(msg)"
            case .invalidFrame: return "Invalid frame received"
            }
        }
    }

    private static let headerSize = 16
    private static let protocolVersion: UInt32 = 1

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.lookinmcp.connection")

    private struct PendingState: Sendable {
        var nextTag: UInt32 = 1
        var requests: [UInt32: CheckedContinuation<Frame, Error>] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: PendingState())

    private(set) var connectedPort: Int = 0

    var isConnected: Bool {
        connection?.state == .ready
    }

    func connect(port: Int) async throws {
        if connection != nil {
            throw ConnectionError.alreadyConnected
        }

        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let conn = NWConnection(host: host, port: nwPort, using: .tcp)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.tryResume {
                        self?.connection = conn
                        self?.connectedPort = port
                        self?.startReceiving()
                        continuation.resume()
                    }
                case .failed(let error):
                    once.tryResume {
                        continuation.resume(throwing: ConnectionError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    once.tryResume {
                        continuation.resume(throwing: ConnectionError.connectionFailed("cancelled"))
                    }
                default:
                    break
                }
            }
            conn.start(queue: self.queue)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connectedPort = 0

        let pending = state.withLock { s -> [UInt32: CheckedContinuation<Frame, Error>] in
            let p = s.requests
            s.requests.removeAll()
            return p
        }
        for (_, cont) in pending {
            cont.resume(throwing: ConnectionError.notConnected)
        }
    }

    /// Send a request frame and wait for the matching response (by tag).
    /// Uses a single continuation with a DispatchQueue-based timeout to avoid
    /// capturing non-Sendable NWConnection in a task group closure.
    func sendRequest(type requestType: UInt32, payload: Data? = nil, timeout: TimeInterval = 10) async throws -> Frame {
        guard let conn = connection, conn.state == .ready else {
            throw ConnectionError.notConnected
        }

        let tag = state.withLock { s -> UInt32 in
            let t = s.nextTag
            s.nextTag += 1
            return t
        }
        let headerData = buildHeader(type: requestType, tag: tag, payloadSize: UInt32(payload?.count ?? 0))
        var frameData = headerData
        if let payload = payload {
            frameData.append(payload)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Frame, Error>) in
            self.state.withLock { s in
                s.requests[tag] = continuation
            }

            self.queue.asyncAfter(deadline: .now() + timeout) {
                let cont = self.state.withLock { s in
                    s.requests.removeValue(forKey: tag)
                }
                cont?.resume(throwing: ConnectionError.timeout)
            }

            conn.send(content: frameData, completion: .contentProcessed { error in
                if let error = error {
                    let cont = self.state.withLock { s in
                        s.requests.removeValue(forKey: tag)
                    }
                    cont?.resume(throwing: ConnectionError.sendError(error.localizedDescription))
                }
            })
        }
    }

    // MARK: - Private

    private func startReceiving() {
        readNextFrame()
    }

    private func readNextFrame() {
        guard let conn = connection, conn.state == .ready else {
            return
        }

        conn.receive(minimumIncompleteLength: Self.headerSize, maximumLength: Self.headerSize) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if error != nil {
                self.handleDisconnect()
                return
            }

            guard let headerData = content, headerData.count == Self.headerSize else {
                if isComplete {
                    self.handleDisconnect()
                }
                return
            }

            let type = headerData.readUInt32BigEndian(at: 4)
            let tag = headerData.readUInt32BigEndian(at: 8)
            let payloadSize = headerData.readUInt32BigEndian(at: 12)

            if payloadSize > 0 {
                self.readPayload(size: Int(payloadSize), conn: conn) { payload in
                    let frame = Frame(type: type, tag: tag, payload: payload)
                    self.dispatchFrame(frame)
                    self.readNextFrame()
                }
            } else {
                let frame = Frame(type: type, tag: tag, payload: nil)
                self.dispatchFrame(frame)
                self.readNextFrame()
            }
        }
    }

    private func readPayload(size: Int, conn: NWConnection, completion: @escaping @Sendable (Data) -> Void) {
        final class Accumulator: @unchecked Sendable {
            var data = Data()
        }
        let acc = Accumulator()

        @Sendable func readChunk() {
            let remaining = size - acc.data.count
            guard remaining > 0 else {
                completion(acc.data)
                return
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] content, _, isComplete, error in
                if error != nil {
                    self?.handleDisconnect()
                    return
                }
                if let data = content {
                    acc.data.append(data)
                }
                if acc.data.count >= size {
                    completion(acc.data)
                } else if isComplete {
                    completion(acc.data)
                } else {
                    readChunk()
                }
            }
        }
        readChunk()
    }

    private func dispatchFrame(_ frame: Frame) {
        let continuation = state.withLock { s in
            s.requests.removeValue(forKey: frame.tag)
        }
        continuation?.resume(returning: frame)
    }

    private func buildHeader(type: UInt32, tag: UInt32, payloadSize: UInt32) -> Data {
        var data = Data(capacity: Self.headerSize)
        data.appendUInt32BigEndian(Self.protocolVersion)
        data.appendUInt32BigEndian(type)
        data.appendUInt32BigEndian(tag)
        data.appendUInt32BigEndian(payloadSize)
        return data
    }

    private func handleDisconnect() {
        disconnect()
    }
}

/// Thread-safe helper to ensure a continuation is resumed exactly once.
/// NWConnection state updates may fire multiple callbacks for the same transition.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock: os_unfair_lock_t

    init() {
        lock = os_unfair_lock_t.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    func tryResume(_ body: () -> Void) {
        os_unfair_lock_lock(lock)
        guard !done else { os_unfair_lock_unlock(lock); return }
        done = true
        os_unfair_lock_unlock(lock)
        body()
    }
}

private extension Data {
    func readUInt32BigEndian(at offset: Int) -> UInt32 {
        let bytes = self[self.startIndex + offset ..< self.startIndex + offset + 4]
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buf in
            bytes.copyBytes(to: buf)
        }
        return UInt32(bigEndian: value)
    }

    mutating func appendUInt32BigEndian(_ value: UInt32) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { buf in
            append(contentsOf: buf)
        }
    }
}
