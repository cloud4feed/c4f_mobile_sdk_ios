#if canImport(UIKit) && canImport(WebKit) && !os(watchOS)
import UIKit

/// Presents `SurveyViewController` on top of the visible screen in the configured style.
final class UIKitSurveyPresenter: SurveyPresenting {

    func present(_ request: SurveyPresentationRequest, onClose: @escaping () -> Void) -> Bool {
        guard let host = Self.topViewController() else {
            SDKLog.error("No visible view controller to present survey \(request.surveyId)")
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
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return top(from: window?.rootViewController)
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
