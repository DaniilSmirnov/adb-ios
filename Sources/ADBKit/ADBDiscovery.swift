import Foundation
import Network

public final class ADBDiscovery: NSObject, @unchecked Sendable {
    private final class BrowseState: @unchecked Sendable {
        var latest: [NWBrowser.Result] = []
        var resumed = false
        let lock = NSLock()
    }
    private var browser: NWBrowser?
    public override init() { super.init() }

    public func discover(timeout: Duration = .seconds(5)) async -> [ADBDevice] {
        await withTaskGroup(of: [ADBDevice].self) { group in
            group.addTask { [weak self] in
                guard let self else { return [] }
                return await self.browse(types: ["_adb-tls-connect._tcp", "_adb._tcp"], timeout: timeout)
            }
            group.addTask { try? await Task.sleep(for: timeout); return [] }
            let result = await group.next() ?? []
            group.cancelAll(); return result
        }
    }

    private func browse(types: [String], timeout: Duration) async -> [ADBDevice] {
        await withTaskGroup(of: [ADBDevice].self) { group in
            for type in types {
                group.addTask { [weak self] in await self?.browse(type: type, timeout: timeout) ?? [] }
            }
            var result: [ADBDevice] = []
            for await devices in group { result.append(contentsOf: devices) }
            var unique = Set<String>()
            return result.filter { unique.insert($0.id).inserted }
        }
    }

    private func browse(type: String, timeout: Duration) async -> [ADBDevice] {
        await withCheckedContinuation { continuation in
            let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser = b
            let state = BrowseState()
            let finish = {
                state.lock.lock(); defer { state.lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                let transport: TransportKind = type == "_adb-tls-connect._tcp" ? .tls : .tcp
                let devices = state.latest.compactMap { result -> ADBDevice? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return ADBDevice(id: name, host: name, port: 5555, transport: transport)
                }
                continuation.resume(returning: devices)
                b.cancel()
            }
            b.browseResultsChangedHandler = { results, _ in
                state.lock.lock(); state.latest = Array(results); let hasResults = !state.latest.isEmpty; state.lock.unlock()
                if hasResults { finish() }
            }
            b.stateUpdateHandler = { state in if case .failed = state { finish() } }
            b.start(queue: DispatchQueue(label: "adbkit.discovery.\(type)"))
            Task { try? await Task.sleep(for: timeout); finish() }
        }
    }
}
