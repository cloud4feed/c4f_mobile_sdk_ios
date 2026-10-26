#if canImport(UIKit) && !os(watchOS)
import UIKit
#if canImport(WebKit)
import WebKit
#endif

/// Finds buttons and segmented controls on a screen and listens to them without replacing the
/// app's own actions (an extra target is added).
///
/// - Button trigger: a `UIControl` whose `accessibilityIdentifier` (or, if not set,
///   `accessibilityLabel`) is a configured `buttonTriggerId` or a predefined id (`survey_button`, ...).
/// - Tab trigger: a `UISegmentedControl`; the selected segment title is the tab name
///   (the iOS counterpart of Android's TabLayout).
/// SwiftUI buttons are not UIKit controls: use `.surveyTrigger(_:)` there.
final class ControlDetector: NSObject {
    var onButton: ((String) -> Void)?
    var onTab: ((String) -> Void)?

    private let buttonIds = NSMapTable<UIControl, NSString>.weakToStrongObjects()
    private let segments = NSHashTable<UISegmentedControl>.weakObjects()

    func scan(_ root: UIView, watchedIds: Set<String>, watchSegments: Bool) {
        guard !watchedIds.isEmpty || watchSegments else { return }
        var found = 0
        UIViewWalker.visit(root) { view in
            if let segmented = view as? UISegmentedControl {
                if watchSegments && !segments.contains(segmented) {
                    segmented.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
                    segments.add(segmented)
                    found += 1
                }
                return
            }
            guard let control = view as? UIControl, buttonIds.object(forKey: control) == nil,
                  let id = Self.identifier(of: control, in: watchedIds) else { return }
            control.addTarget(self, action: #selector(controlTapped(_:)), for: .touchUpInside)
            buttonIds.setObject(id as NSString, forKey: control)
            found += 1
        }
        if found > 0 { SDKLog.debug("Attached to \(found) controls") }
    }

    static func identifier(of control: UIControl, in ids: Set<String>) -> String? {
        if let identifier = control.accessibilityIdentifier, ids.contains(identifier) { return identifier }
        if let label = control.accessibilityLabel, ids.contains(label) { return label }
        return nil
    }

    @objc private func controlTapped(_ sender: UIControl) {
        guard let id = buttonIds.object(forKey: sender) as String? else { return }
        SDKLog.debug("Button tapped: \(id)")
        onButton?(id)
    }

    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex != UISegmentedControl.noSegment,
              let title = sender.titleForSegment(at: sender.selectedSegmentIndex) else { return }
        onTab?(title)
    }
}

/// Watches the scroll views of the current screen (KVO on `contentOffset`; the app's
/// `delegate` is not touched) and reports the offset in pixels (design decision K5).
final class ScrollObserver {
    var onOffset: ((Int) -> Void)?
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    func observe(in root: UIView) {
        UIViewWalker.visit(root) { view in
            guard let scrollView = view as? UIScrollView, !(scrollView is UITextView), scrollView.isScrollEnabled else { return }
            let key = ObjectIdentifier(scrollView)
            guard observations[key] == nil else { return }
            observations[key] = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.report(scrollView)
            }
        }
    }

    func reset() {
        observations.values.forEach { $0.invalidate() }
        observations.removeAll()
    }

    private func report(_ scrollView: UIScrollView) {
        // contentOffset starts at -adjustedContentInset.top; Android's scrollY starts at 0.
        let points = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        guard points > 0 else { return }
        let scale = scrollView.window?.screen.scale ?? UIScreen.main.scale
        onOffset?(Int((points * scale).rounded()))
    }
}

/// Depth-first walk over a view tree. Web views (survey pages, the app's own web content) are skipped.
enum UIViewWalker {
    static func visit(_ view: UIView, _ body: (UIView) -> Void) {
        #if canImport(WebKit)
        if view is WKWebView { return }
        #endif
        body(view)
        for subview in view.subviews {
            visit(subview, body)
        }
    }
}

/// Connects UIKit to the `TriggerCoordinator`: screens, tabs (tab bar + segmented controls),
/// buttons, scroll views and app background / foreground.
final class UIKitIntegration: PlatformIntegration {
    private weak var coordinator: TriggerCoordinator?
    private let engine: SurveyEngine
    private let controls = ControlDetector()
    private let scroll = ScrollObserver()
    private weak var currentController: UIViewController?
    private var lastTabTitles: [ObjectIdentifier: String] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isHybrid = false

    init(coordinator: TriggerCoordinator, engine: SurveyEngine) {
        self.coordinator = coordinator
        self.engine = engine
        controls.onButton = { [weak coordinator] id in coordinator?.triggerButton(id) }
        controls.onTab = { [weak coordinator] tab in coordinator?.trackTab(tab) }
        scroll.onOffset = { [weak coordinator] pixels in coordinator?.scrollChanged(offsetPixels: pixels) }
    }

    func start(hybridMode: Bool, automaticScreenTracking: Bool) {
        isHybrid = hybridMode
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.coordinator?.appDidEnterBackground()
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.coordinator?.appWillEnterForeground()
        })

        // React Native / Flutter draw their own UI: only lifecycle events are observed.
        guard !hybridMode else { return }

        if automaticScreenTracking {
            ScreenTracker.installIfNeeded()
            ScreenTracker.onScreenAppear = { [weak self] controller in self?.screenAppeared(controller) }
        }
        // The first screen may already be visible before autoSetup ran.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let top = UIKitSurveyPresenter.topViewController() else { return }
            if automaticScreenTracking {
                self.screenAppeared(top)
            } else {
                self.attach(to: top)
            }
        }
    }

    func configurationApplied() {
        guard !isHybrid else { return }
        if let controller = currentController ?? UIKitSurveyPresenter.topViewController() {
            scan(controller)
        }
    }

    func screenTrackedManually() {
        guard !isHybrid else { return }
        // Give the new screen a moment to lay out, then look for buttons / scroll views.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let top = UIKitSurveyPresenter.topViewController(),
                  ScreenTracker.shouldTrack(top) else { return }
            self.attach(to: top)
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        ScreenTracker.onScreenAppear = nil
        scroll.reset()
    }

    // MARK: Screens

    private func screenAppeared(_ controller: UIViewController) {
        guard ScreenTracker.shouldTrack(controller) else { return }
        coordinator?.trackScreen(ScreenTracker.screenName(for: controller))
        reportTabIfChanged(for: controller)
        attach(to: controller)
    }

    /// Tab bar: the selected tab's title becomes a tab event when the selection changed
    /// (the first tab shown at launch is not a "change").
    private func reportTabIfChanged(for controller: UIViewController) {
        guard let tabBarController = controller.tabBarController,
              let selected = tabBarController.selectedViewController,
              selected === controller || selected === controller.navigationController,
              let title = selected.tabBarItem.title ?? selected.title, !title.isEmpty else { return }
        let key = ObjectIdentifier(tabBarController)
        let previous = lastTabTitles[key]
        lastTabTitles[key] = title
        if let previous = previous, previous != title {
            coordinator?.trackTab(title)
        }
    }

    private func attach(to controller: UIViewController) {
        if currentController !== controller {
            scroll.reset()
            currentController = controller
        }
        scan(controller)
        // Cells and lazily built views appear after the first layout pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak controller] in
            guard let self = self, let controller = controller, self.currentController === controller else { return }
            self.scan(controller)
        }
    }

    private func scan(_ controller: UIViewController) {
        guard controller.isViewLoaded else { return }
        let hasTabSurveys = engine.config.surveys.contains { $0.enableTabChangeTrigger }
        controls.scan(controller.view, watchedIds: engine.watchedButtonIds, watchSegments: hasTabSurveys)
        if engine.hasScrollSurveys {
            scroll.observe(in: controller.view)
        }
    }
}
#endif
