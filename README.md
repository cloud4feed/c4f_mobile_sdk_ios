# Cloud4Feed Mobile SDK for iOS

Swift version of the Cloud4Feed survey SDK. It reads the same configuration as the Android SDK
(`c4f_mobile_sdk`) from `anonym.cloud4feed.com` and opens the survey from `cx.cloud4feed.com`.

> Status: **Phase 1 (core)**. Configuration, cache, display rules, exclusion rules, value sources
> and survey URL building are implemented and unit-tested. Survey presentation, triggers on UIKit /
> SwiftUI and the public `MobileSDK` API come in Phase 2. Not released yet.

## Requirements

- iOS 15+
- Swift 5.9+ (Xcode 15+)

## Layout

```
Sources/Cloud4FeedSDK/
  Models/     Config, SurveyConfig, CustomParam, ExclusionRule, ExclusionOperator
  Config/     ConfigService (network), ConfigParser (tolerant JSON), ConfigCache
  Rules/      Eligibility (canShowSurvey), ExclusionEvaluator, TriggerOnceStore, SessionTracker
  Values/     ValueResolver (STORAGE / DEVICE / URL / TIMESTAMP / SESSION / INSTALL_TIME / APP_USAGE)
  URL/        SurveyURLBuilder, SurveyDataCollector
  Triggers/   SurveyEngine (which survey opens for a screen / button / tab / scroll / exit / launch)
  Support/    logging, JSON, storage helpers
  SDKCore.swift  wires the parts together
Tests/Cloud4FeedSDKTests/
```

The core only uses Foundation, so the tests also run on Linux and Windows:

```bash
swift build
swift test
```

## Logs

Subsystem `com.cloud4feed.mobilesdk`. On a simulator:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.cloud4feed.mobilesdk"'
```

## Design

Parity decisions with the Android SDK: `c4f_mobile_sdk/.agents/tasks/ios/IOS-SDK-DESIGN.md`.
