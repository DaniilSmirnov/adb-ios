#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
import UniformTypeIdentifiers

public final class DeviceManagerWebViewController: UIViewController, WKScriptMessageHandler, UIDocumentPickerDelegate {
    private let router: DeviceManagerBridgeRouter
    private var webView: WKWebView!
    private var pendingFileRequestID: String?

    public init(backend: DeviceManagerNativeBackend) {
        router = DeviceManagerBridgeRouter(backend: backend)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "deviceManager")
        webView = WKWebView(frame: .zero, configuration: configuration)
        view = webView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        guard let url = Bundle.main.url(forResource: "DeviceManagerUI/index", withExtension: "html") else {
            webView.loadHTMLString("<h1>DeviceManager UI bundle is missing</h1>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "deviceManager", let body = message.body as? String else { return }
        Task {
            do {
                let request = try await router.decode(body)
                if request.method == "file.select" {
                    await MainActor.run {
                        self.pendingFileRequestID = request.id
                        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
                        picker.delegate = self
                        self.present(picker, animated: true)
                    }
                    return
                }
                let response = await router.handle(request)
                await resolve(response)
            } catch {
                let response = DeviceManagerBridgeResponse(id: "invalid", ok: false, error: error.localizedDescription)
                await resolve(response)
            }
        }
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = pendingFileRequestID, let url = urls.first else { return }
        pendingFileRequestID = nil
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let file = DeviceManagerFilePayload(id: UUID().uuidString, name: url.lastPathComponent, size: size, nativeToken: url.path)
        Task {
            let payload = try? JSONEncoder().encode(file)
            await resolve(DeviceManagerBridgeResponse(id: id, ok: true, payload: payload))
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let id = pendingFileRequestID else { return }
        pendingFileRequestID = nil
        Task { await resolve(DeviceManagerBridgeResponse(id: id, ok: false, error: "File selection cancelled")) }
    }

    private func resolve(_ response: DeviceManagerBridgeResponse) async {
        guard let encoded = try? await router.encode(response),
              let literalData = try? JSONSerialization.data(withJSONObject: encoded),
              let literal = String(data: literalData, encoding: .utf8) else { return }
        await MainActor.run { self.webView.evaluateJavaScript("window.__deviceManagerResolve(\(literal))") }
    }

    deinit { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "deviceManager") }
}
#endif
