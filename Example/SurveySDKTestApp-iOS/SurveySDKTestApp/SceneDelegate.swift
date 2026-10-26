import UIKit
import SwiftUI
import Cloud4FeedSDK

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Bottom navigation like the Android app: Home / Dashboard / Notifications (+ a SwiftUI demo).
        let tabs = UITabBarController()
        tabs.viewControllers = [
            navigation(HomeViewController(), title: "Home", image: "house"),
            navigation(DashboardViewController(), title: "Dashboard", image: "square.grid.2x2"),
            navigation(NotificationsViewController(), title: "Notifications", image: "bell"),
            navigation(UIHostingController(rootView: SwiftUIDemoView()), title: "SwiftUI", image: "swift"),
        ]

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window

        if let url = connectionOptions.urlContexts.first?.url {
            MobileSDK.shared?.handle(url: url)
        }
    }

    // Deep links: surveytest://open?campaign=summer -> URL value source "campaign".
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            MobileSDK.shared?.handle(url: url)
        }
    }

    private func navigation(_ root: UIViewController, title: String, image: String) -> UINavigationController {
        root.title = title
        let controller = UINavigationController(rootViewController: root)
        controller.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
        return controller
    }
}
