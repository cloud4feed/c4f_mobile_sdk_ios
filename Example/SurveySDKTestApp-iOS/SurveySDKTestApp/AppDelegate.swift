import UIKit
import Cloud4FeedSDK

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // Same Configuration Manager setup as the Android test app.
    // Get this from your Cloud4Feed account (Configuration Manager -> API Key).
    static let apiKey = "sk_c63e47160fc0404e98918d50c7c7e624"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The app's own user data. STORAGE custom parameters and exclusion rules read it by key.
        let defaults = UserDefaults.standard
        defaults.set("1011", forKey: "customerId")
        defaults.set("gold", forKey: "user_tier")
        defaults.set(3, forKey: "cart_items")

        // 1. Initialize with the API key and user parameters.
        let sdk = MobileSDK.initialize(apiKey: Self.apiKey,
                                       parameters: ["userID": "5586925", "rank": "chef", "customerId": "1011"])

        // 2. Automatic detection: screens, buttons, tabs, scroll, app launch and exit.
        sdk.autoSetup()

        // SESSION custom parameter with key "promo_code".
        sdk.setSessionData("WELCOME10", forKey: "promo_code")

        sdk.onSurveyShown = { NSLog("[TestApp] survey shown: %@", $0) }
        sdk.onSurveyClosed = { NSLog("[TestApp] survey closed: %@", $0) }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
