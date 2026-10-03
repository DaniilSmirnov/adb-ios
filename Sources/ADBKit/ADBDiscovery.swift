import Foundation
import Network

public final class ADBDiscovery: NSObject, @unchecked Sendable {
    private var browser: NWBrowser?
    public override init() { super.init() }

    public func discover(timeout: Duration = .seconds(5)) async -> [ADBDevice] {
        await withTaskGroup(of: [ADBDevice].self) { group in
            group.addTask { [weak self] in
                guard let self else { return [] }
                return await self.browse()
            }
            group.addTask { try? await Task.sleep(for: timeout); return [] }
            let result = await group.next() ?? []
            group.cancelAll(); return result
        }
    }

    private func browse() async -> [ADBDevice] {
        await withCheckedContinuation { continuation in
            let b = NWBrowser(for: .bonjour(type: "_adb-tls-pairing._tcp", domain: nil), using: .tcp)
            browser = b
            b.browseResultsChangedHandler = { results, _ in
                let devices = results.compactMap { result -> ADBDevice? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return ADBDevice(id: name, host: name, port: 5555, transport: .wifiPairing)
                }
                if !devices.isEmpty { continuation.resume(returning: devices); b.cancel() }
            }
            b.start(queue: DispatchQueue(label: "adbkit.discovery"))
        }
    }
}

