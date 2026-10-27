# Cloud4Feed Mobile SDK for iOS

Swift version of the Cloud4Feed survey SDK. It reads the same configuration as the Android SDK
(`c4f_mobile_sdk`) from `anonym.cloud4feed.com` and opens the survey from `cx.cloud4feed.com`.

> Version **1.0.1** (1.0.1: a deep link that arrives before `initialize` is kept — use
> `MobileSDK.handle(url:)`). Tested on the iOS 27 simulator (Xcode 27.1) against the live Cloud4Feed
> backend: all six trigger types, the three display styles, custom parameters, exclusion rules,
> display limits and the loading-error screen. React Native and Flutter bridges ship this SDK
> bundled (`cloud4feed-mobilesdk-react-native` / `cloud4feed_mobilesdk_flutter` 1.3.0+).

## Requirements

- iOS 15+
- Swift 5.9+ (Xcode 15+)

## Installation (Swift Package Manager)

Xcode → **File → Add Package Dependencies…** → `https://github.com/cloud4feed/c4f_mobile_sdk_ios`
→ Dependency Rule **Up to Next Major Version** from `1.0.1` → add the **Cloud4FeedSDK** library.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/cloud4feed/c4f_mobile_sdk_ios.git", from: "1.0.1")
```

## Quick start

```swift
import Cloud4FeedSDK

// application(_:didFinishLaunchingWithOptions:) or your App's init
MobileSDK.initialize(apiKey: "sk_...", parameters: ["customerId": "1011"])
    .autoSetup()
```

`autoSetup()` detects UIKit screens (`viewDidAppear`), tab bar and segmented-control tabs,
buttons by `accessibilityIdentifier`, scroll views, app launch and app exit.

Screen names default to the view controller class name. Use the same names as on Android:

```swift
final class HomeViewController: UIViewController, SurveyScreenNameProviding {
    var surveyScreenName: String { "Home" }
}
```

SwiftUI:

```swift
SurveyScrollView { ... }          // scroll trigger
    .surveyScreen("home")          // navigation / exit
Button("Feedback") { }.surveyTrigger("feedback_button")
TabPage().surveyTab("womens")
```

Manual API (also used by the React Native / Flutter bridges with `enableHybridMode()`):

```swift
let sdk = MobileSDK.shared
sdk?.trackScreen("home")
sdk?.trackTab("womens")
sdk?.triggerButton("checkout_button")
sdk?.triggerScroll(offsetPixels: 600)
sdk?.showSurvey(id: "180")
sdk?.setUserProperty("gold", forKey: "user_tier")      // STORAGE
sdk?.setSessionData("WELCOME10", forKey: "promo_code")  // SESSION
```

Deep links (URL value source) — pass the link that opened the app. `MobileSDK.handle(url:)` works
at any time: a link that arrives before `initialize` (app opened from a link while it was not
running) is kept and applied when the SDK starts.

```swift
// SceneDelegate
func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
           options connectionOptions: UIScene.ConnectionOptions) {
    if let url = connectionOptions.urlContexts.first?.url { MobileSDK.handle(url: url) }
}
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url { MobileSDK.handle(url: url) }
}

// SwiftUI
ContentView().onOpenURL { MobileSDK.handle(url: $0) }
```

## Layout

```
Sources/Cloud4FeedSDK/
  MobileSDK.swift   public API
  SDKCore.swift     wiring of the platform-independent parts
  Models/  Config/  Rules/  Values/  URL/        core (Foundation only)
  Triggers/SurveyEngine.swift                    which survey matches an event
  Triggers/TriggerCoordinator.swift              timing, debounce, delays, queue, app exit
  Triggers/UIKit/                                swizzle, button / tab / scroll detection
  UI/                                            WKWebView screen, presenter, link policy
  SwiftUI/                                       modifiers, SurveyScrollView
  Resources/PrivacyInfo.xcprivacy
Tests/Cloud4FeedSDKTests/
Example/SurveySDKTestApp-iOS/                    test app (XcodeGen project.yml)
Scripts/mac-verify.sh                            Mac build + simulator run
Scripts/mac-enable-screen-sharing.sh             one-time: desktop password + Screen Sharing on the Mac
Scripts/connect-mac.ps1                          Windows: SSH tunnel + RealVNC Viewer to the Mac desktop
```

## Tests

The core only uses Foundation, so the tests also run on Linux / Windows (Docker):

```bash
swift test
docker run --rm -v "$PWD:/pkg" -w /pkg swift:6.2 swift test --scratch-path /tmp/build
```

On a Mac, `bash Scripts/mac-verify.sh` runs the tests, builds the SDK for the iOS simulator,
generates and builds the example app, and launches it.

## Logs

Subsystem `com.cloud4feed.mobilesdk`:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.cloud4feed.mobilesdk"'
```

## Design

Parity decisions with the Android SDK: `c4f_mobile_sdk/.agents/tasks/ios/IOS-SDK-DESIGN.md`.
