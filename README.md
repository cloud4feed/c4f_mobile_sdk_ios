# Cloud4Feed Mobile SDK for iOS

Swift version of the Cloud4Feed survey SDK. It reads the same configuration as the Android SDK
(`c4f_mobile_sdk`) from `anonym.cloud4feed.com` and opens the survey from `cx.cloud4feed.com`.

> Status: **Phase 2 written, not yet verified on a Mac.** The platform-independent core and the
> trigger logic are unit-tested on Linux (93 tests). The UIKit / WebKit / SwiftUI layer and the
> example app still have to be built and tested on a Mac (`Scripts/mac-verify.sh`). Not released.

## Requirements

- iOS 15+
- Swift 5.9+ (Xcode 15+)

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
sdk?.handle(url: deepLinkURL)                            // URL
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
