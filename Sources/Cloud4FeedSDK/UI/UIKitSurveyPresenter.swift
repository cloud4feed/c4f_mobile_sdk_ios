#if canImport(UIKit) && canImport(WebKit) && !os(watchOS)
import UIKit

/// Presents `SurveyViewController` on top of the visible screen in the configured style.
final class UIKitSurveyPresenter: SurveyPresenting {

    func present(_ request: SurveyPresentationRequest, onClose: @escaping () -> Void) -> Bool {
        guard let host = Self.topViewController() else {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .map { "\(type(of: $0)) key=\($0.isKeyWindow) root=\($0.rootViewController.map { String(describing: type(of: $0)) } ?? "nil")" }
            SDKLog.error("No visible view controller to present survey \(request.surveyId). Windows: \(windows)")
            return false
        }

        let surveyController = SurveyViewController(request: request, onClose: onClose)
        switch request.style {
        case .fullScreen:
            surveyController.modalPresentationStyle = .fullScreen
            surveyController.modalTransitionStyle = request.animation == .fade ? .crossDissolve : .coverVertical
        case .dialog:
            surveyController.modalPresentationStyle = .overFullScreen
            surveyController.modalTransitionStyle = .crossDissolve
        case .bottomSheet:
            surveyController.modalPresentationStyle = .pageSheet
            if let sheet = surveyController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }
        }

        SDKLog.debug("Presenting survey \(request.surveyId) as \(request.style.rawValue) on \(type(of: host))")
        host.present(surveyController, animated: true)
        return true
    }

    /// The view controller the user currently sees, in the foreground scene's key window.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState != .foregroundActive }
        for scene in ordered {
            // SwiftUI and the system can add helper windows (some become key while scrolling)
            // without a root view controller; only app windows that are on screen count.
            let candidates = scene.windows.filter {
                $0.rootViewController != nil && !$0.isHidden && $0.windowLevel == .normal
            }
            if let window = candidates.first(where: { $0.isKeyWindow }) ?? candidates.first {
                return top(from: window.rootViewController)
            }
        }
        return nil
    }

    static func top(from root: UIViewController?) -> UIViewController? {
        guard let root = root else { return nil }
        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return top(from: presented)
        }
        if let navigation = root as? UINavigationController, let topController = navigation.topViewController {
            return top(from: topController)
        }
        if let tabs = root as? UITabBarController, let selected = tabs.selectedViewController {
            return top(from: selected)
        }
        return root
    }
}
#endif
