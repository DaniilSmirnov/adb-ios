import Foundation
import Network

public protocol ADBByteTransport: Sendable {
    func send(_ data: Data) async throws
    func receive(upTo count: Int) async throws -> Data
    func close()
}

public final class ADBNetworkTransport: ADBByteTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "adbkit.transport")
    private var started = false

    public init(host: String, port: UInt16 = 5555, tls: Bool = false) {
        let parameters = tls ? NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options()) : .tcp
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }

    private func start() async throws {
        guard !started else { return }; started = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state { case .ready: continuation.resume(); case .failed(let error): continuation.resume(throwing: error); default: break }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ data: Data) async throws {
        try await start()
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    public func receive(upTo count: Int) async throws -> Data {
        try await start()
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: count) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if isComplete && (data == nil || data!.isEmpty) { continuation.resume(throwing: ADBError.connectionClosed) }
                else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }

    public func close() { connection.cancel() }
}

