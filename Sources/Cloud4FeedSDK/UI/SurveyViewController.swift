#if canImport(UIKit) && canImport(WebKit) && !os(watchOS)
import UIKit
import WebKit

extension UIColor {
    convenience init(_ color: RGBAColor) {
        self.init(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: CGFloat(color.alpha))
    }
}

/// Shows one survey page in a `WKWebView` with a close (X) button, a loading indicator and an
/// error screen with Retry / Close (Android: `SurveyFullScreenActivity`, `SurveyDialogFragment`,
/// `SurveyBottomSheetFragment` + `WebViewConfigurator`).
final class SurveyViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let request: SurveyPresentationRequest
    private let onClose: () -> Void
    private var didFinish = false

    private let containerView = UIView()
    private var webView: WKWebView!
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let closeButton = UIButton(type: .system)
    private let errorView = UIStackView()
    private let errorMessageLabel = UILabel()

    init(request: SurveyPresentationRequest, onClose: @escaping () -> Void) {
        self.request = request
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        // Safety net: the queue must be released even if the survey disappears in an unusual way.
        if !didFinish { onClose() }
    }

    // MARK: Layout

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = UIColor(request.backgroundColor)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = background
        view.addSubview(containerView)

        switch request.style {
        case .dialog:
            view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            containerView.layer.cornerRadius = 16
            containerView.clipsToBounds = true
            let guide = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                containerView.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
                containerView.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
                containerView.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.92),
                containerView.heightAnchor.constraint(equalTo: guide.heightAnchor, multiplier: 0.85),
            ])
        case .fullScreen:
            view.backgroundColor = background
            let guide = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: guide.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        case .bottomSheet:
            view.backgroundColor = background
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: view.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }

        setUpWebView(background: background)
        setUpLoadingIndicator()
        setUpErrorView(background: background)
        setUpCloseButton()
        load()
    }

    private func setUpWebView(background: UIColor) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.accessibilityIdentifier = "c4f_survey_webview"
        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
    }

    private func setUpLoadingIndicator() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        containerView.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])
    }

    private func setUpErrorView(background: UIColor) {
        let titleLabel = UILabel()
        titleLabel.text = "Survey Loading Failed"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        errorMessageLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorMessageLabel.adjustsFontForContentSizeCategory = true
        errorMessageLabel.textColor = .secondaryLabel
        errorMessageLabel.textAlignment = .center
        errorMessageLabel.numberOfLines = 0

        let retryButton = UIButton(type: .system)
        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let closeTextButton = UIButton(type: .system)
        closeTextButton.setTitle("Close", for: .normal)
        closeTextButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        closeTextButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [retryButton, closeTextButton])
        buttons.axis = .horizontal
        buttons.spacing = 24

        errorView.axis = .vertical
        errorView.alignment = .center
        errorView.spacing = 12
        errorView.addArrangedSubview(titleLabel)
        errorView.addArrangedSubview(errorMessageLabel)
        errorView.addArrangedSubview(buttons)
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        containerView.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            errorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 24),
            errorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -24),
        ])
    }

    private func setUpCloseButton() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: configuration), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.9)
        closeButton.layer.cornerRadius = 18
        closeButton.accessibilityLabel = "Close survey"
        closeButton.accessibilityIdentifier = "c4f_survey_close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        containerView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor,
                                             constant: request.style == .bottomSheet ? 16 : 8),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    // MARK: Loading

    private func load() {
        guard let url = URL(string: request.url) else {
            showError("The survey address is not valid.")
            return
        }
        SDKLog.debug("Loading survey \(request.surveyId): \(url.absoluteString)", .webView)
        errorView.isHidden = true
        webView.isHidden = false
        loadingIndicator.startAnimating()
        webView.load(URLRequest(url: url))
    }

    private func showError(_ message: String) {
        loadingIndicator.stopAnimating()
        webView.isHidden = true
        errorMessageLabel.text = message
        errorView.isHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: errorView)
    }

    // MARK: Closing

    @objc private func retryTapped() {
        load()
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in self?.finish() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Covers swipe-to-dismiss of the bottom sheet and dismissals started by the app.
        if isBeingDismissed || presentingViewController == nil {
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        webView?.stopLoading()
        onClose()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        switch SurveyLinkPolicy.decision(for: url) {
        case .load:
            decisionHandler(.allow)
        case .openExternally:
            SDKLog.debug("Opening outside the survey: \(url.absoluteString)", .webView)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        SDKLog.debug("Survey page loaded", .webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        SDKLog.warning("Web content process terminated, reloading", .webView)
        webView.reload()
    }

    private func handle(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads (a new navigation started, or a link opened outside) are not failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // frame load interrupted
        SDKLog.error("Survey page failed: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)", .webView)
        if nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            showError("The survey link must use HTTPS.")
        } else {
            showError(nsError.localizedDescription)
        }
    }

    // MARK: WKUIDelegate

    /// `target="_blank"` links open in the same web view.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
#endif
