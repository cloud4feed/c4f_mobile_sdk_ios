import Foundation

/// Display style from the Configuration Manager (`modalStyle`). Unknown values -> full screen.
enum SurveyModalStyle: String, Equatable {
    case fullScreen = "full_screen"
    case dialog
    case bottomSheet = "bottom_sheet"

    init(configValue: String) {
        self = SurveyModalStyle(rawValue: configValue.lowercased()) ?? .fullScreen
    }
}

/// Opening animation (`animationType`). Only used by the full-screen style, as on Android.
enum SurveyAnimation: String, Equatable {
    case slideUp = "slide_up"
    case fade

    init(configValue: String) {
        self = SurveyAnimation(rawValue: configValue.lowercased()) ?? .slideUp
    }
}

/// Everything the UI needs to show one survey.
struct SurveyPresentationRequest: Equatable {
    let surveyId: String
    let url: String
    let style: SurveyModalStyle
    let animation: SurveyAnimation
    let backgroundColor: RGBAColor

    init(survey: SurveyConfig, url: String) {
        self.surveyId = survey.surveyId
        self.url = url
        self.style = SurveyModalStyle(configValue: survey.modalStyle)
        self.animation = SurveyAnimation(configValue: survey.animationType)
        self.backgroundColor = RGBAColor(hex: survey.backgroundColor)
    }
}

/// Shows surveys. The UIKit implementation is `UIKitSurveyPresenter`.
protocol SurveyPresenting: AnyObject {
    /// Returns false when the survey could not be shown (e.g. no visible screen).
    /// `onClose` must be called exactly once when a shown survey goes away.
    func present(_ request: SurveyPresentationRequest, onClose: @escaping () -> Void) -> Bool
}

/// Used where there is no UI (unit tests on Linux/Windows).
final class NoUIPresenter: SurveyPresenting {
    func present(_ request: SurveyPresentationRequest, onClose: @escaping () -> Void) -> Bool {
        SDKLog.warning("No UI available to show survey \(request.surveyId)")
        return false
    }
}
