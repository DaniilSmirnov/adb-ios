#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

public final class DeviceManagerWebViewController: UIViewController, WKScriptMessageHandler {
    private let router: DeviceManagerBridgeRouter
    private var webView: WKWebView!

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
                let response = await router.handle(request)
                let encoded = try await router.encode(response)
                let escaped = encoded.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                await MainActor.run {
                    self.webView.evaluateJavaScript("window.__deviceManagerResolve('\(escaped)')")
                }
            } catch {
                let response = DeviceManagerBridgeResponse(id: "invalid", ok: false, error: error.localizedDescription)
                if let encoded = try? await router.encode(response) {
                    await MainActor.run { self.webView.evaluateJavaScript("window.__deviceManagerResolve('\(encoded)')") }
                }
            }
        }
    }

    deinit { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "deviceManager") }
}
#endif
