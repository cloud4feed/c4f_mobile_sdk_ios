#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

// SwiftUI does not expose its view tree, so SwiftUI screens report events with these modifiers.
// They forward to `MobileSDK.shared` and do nothing before `initialize`.

public extension View {
    /// Reports `name` as the current screen when this view appears (navigation + exit triggers).
    func surveyScreen(_ name: String) -> some View {
        onAppear { MobileSDK.shared?.trackScreen(name) }
    }

    /// Reports `name` as the selected tab when this view appears. Put it on each `TabView` page.
    func surveyTab(_ name: String) -> some View {
        onAppear { MobileSDK.shared?.trackTab(name) }
    }

    /// Fires the button trigger `buttonId` when this view is tapped, in addition to its own action.
    func surveyTrigger(_ buttonId: String) -> some View {
        simultaneousGesture(TapGesture().onEnded { MobileSDK.shared?.triggerButton(buttonId) })
    }
}

/// A vertical `ScrollView` that reports its scroll position to the scroll trigger.
///
/// ```swift
/// SurveyScrollView {
///     LazyVStack { ... }
/// }
/// ```
public struct SurveyScrollView<Content: View>: View {
    private let showsIndicators: Bool
    private let content: Content
    @Environment(\.displayScale) private var displayScale
    private let spaceName = "c4f_survey_scroll"

    public init(showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: showsIndicators) {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    Color.clear.preference(key: SurveyScrollOffsetKey.self,
                                           value: -proxy.frame(in: .named(spaceName)).minY)
                }
                .frame(height: 0)
                content
            }
        }
        .coordinateSpace(name: spaceName)
        .onPreferenceChange(SurveyScrollOffsetKey.self) { points in
            guard points > 0 else { return }
            MobileSDK.shared?.triggerScroll(offsetPixels: Int((points * displayScale).rounded()))
        }
    }
}

private struct SurveyScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
