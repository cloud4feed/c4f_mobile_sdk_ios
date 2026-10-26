import Foundation

/// Lets a view controller (UIKit) choose the screen name the SDK reports.
/// Without it the class name is used (e.g. `HomeViewController`), matched case-insensitively
/// with "contains" against the Configuration Manager's trigger screens.
///
/// ```swift
/// final class HomeViewController: UIViewController, SurveyScreenNameProviding {
///     var surveyScreenName: String { "home" }
/// }
/// ```
public protocol SurveyScreenNameProviding {
    var surveyScreenName: String { get }
}

/// Class-name based filter for automatic screen tracking (platform-independent, unit-tested).
enum ScreenNameFilter {
    /// System / framework controllers that are not app screens.
    static func isSystemClassName(_ name: String) -> Bool {
        let prefixes = ["UI", "_", "SFSafari", "SK", "PK", "PU", "PH", "CN", "MF", "QL", "AV", "WK", "SL", "EK", "GK", "CA"]
        if prefixes.contains(where: { name.hasPrefix($0) && name.dropFirst($0.count).first?.isUppercase == true }) {
            return true
        }
        return name.hasPrefix("_") || name.contains("HostingController") || name.contains("Survey")
    }
}

#if canImport(UIKit) && !os(watchOS)
import UIKit
import ObjectiveC

/// Automatic screen tracking through a `viewDidAppear(_:)` swizzle (design decision K4).
/// The swizzle is installed once and only forwards events while `onScreenAppear` is set.
enum ScreenTracker {
    static var onScreenAppear: ((UIViewController) -> Void)?
    private static var isInstalled = false

    static func installIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        let viewControllerClass: AnyClass = UIViewController.self
        guard let original = class_getInstanceMethod(viewControllerClass, #selector(UIViewController.viewDidAppear(_:))),
              let replacement = class_getInstanceMethod(viewControllerClass, #selector(UIViewController.c4f_viewDidAppear(_:))) else {
            SDKLog.error("Automatic screen tracking could not be installed")
            return
        }
        method_exchangeImplementations(original, replacement)
        SDKLog.debug("Automatic screen tracking installed")
    }

    /// App screens only: no containers, system controllers, SwiftUI hosting controllers (use
    /// `.surveyScreen(_:)`), the SDK's own survey screen, or controllers embedded in other screens.
    static func shouldTrack(_ controller: UIViewController) -> Bool {
        if controller is SurveyScreenNameProviding { return true }
        if controller is UINavigationController || controller is UITabBarController
            || controller is UIPageViewController || controller is UISplitViewController
            || controller is UIAlertController {
            return false
        }
        if ScreenNameFilter.isSystemClassName(String(describing: type(of: controller))) { return false }
        if let parent = controller.parent, !isContainer(parent) { return false }
        return true
    }

    static func screenName(for controller: UIViewController) -> String {
        if let provider = controller as? SurveyScreenNameProviding { return provider.surveyScreenName }
        return String(describing: type(of: controller))
    }

    private static func isContainer(_ controller: UIViewController) -> Bool {
        controller is UINavigationController || controller is UITabBarController
            || controller is UIPageViewController || controller is UISplitViewController
    }
}

extension UIViewController {
    /// After the swizzle this name points at the original `viewDidAppear(_:)`.
    @objc func c4f_viewDidAppear(_ animated: Bool) {
        c4f_viewDidAppear(animated)
        ScreenTracker.onScreenAppear?(self)
    }
}
#endif
