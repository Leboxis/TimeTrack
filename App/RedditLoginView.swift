import SwiftUI
import WebKit
import WellbeingCore

struct RedditLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = RedditSession.shared
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RedditWebLogin(errorMessage: $errorMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(session.hasSession ? "Reddit · session détectée" : "Se connecter à Reddit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await session.refresh(); dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Fermer la connexion")
                }
            }
        }
        .alert("Connexion", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Compris", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .privacyMask()
    }
}

private struct RedditWebLogin: UIViewControllerRepresentable {
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator { Coordinator(errorMessage: $errorMessage) }

    func makeUIViewController(context: Context) -> UIViewController {
        let configuration = WKWebViewConfiguration()
        // Must be the exact store RedditSession reads from, or the cookie is invisible.
        configuration.websiteDataStore = RedditSession.shared.store
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.scrollView.keyboardDismissMode = .interactive
        web.load(URLRequest(url: URL(string: "https://www.reddit.com/login/")!))

        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        web.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: controller.view.topAnchor),
            web.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
        ])
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        for case let web as WKWebView in controller.view.subviews {
            web.stopLoading()
            web.navigationDelegate = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var errorMessage: String?

        init(errorMessage: Binding<String?>) { _errorMessage = errorMessage }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.allow); return
            }
            guard let url = navigationAction.request.url, RedditCookiePolicy.allows(url) else {
                errorMessage = "Connecte-toi à Reddit avec ton identifiant et ton mot de passe."
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame {
                guard let url = navigationResponse.response.url, RedditCookiePolicy.allows(url) else {
                    decisionHandler(.cancel); return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in await RedditSession.shared.refresh() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard (error as? URLError)?.code != .cancelled else { return }
            errorMessage = "Connexion indisponible. Ferme puis réessaie."
        }
    }
}
