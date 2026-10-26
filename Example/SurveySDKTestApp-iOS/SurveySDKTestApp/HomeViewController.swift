import UIKit
import Cloud4FeedSDK

/// Same content as the Android HomeFragment: predefined buttons, a custom button,
/// manual trigger buttons and long content for the scroll trigger.
final class HomeViewController: UIViewController, SurveyScreenNameProviding {
    // Must match the Configuration Manager's trigger screens (Android reports "Home").
    var surveyScreenName: String { "Home" }

    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "scroll_view"
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        addTitle("Survey SDK Test Home", style: .title1)

        addTitle("1. Predefined buttons (auto-detected)", style: .headline)
        for id in ["survey_button", "take_survey", "feedback_button", "rate_app"] {
            addButton("Predefined: \(id)", identifier: id) {}
        }

        addTitle("Custom button (my_custom_button)", style: .headline)
        addButton("Custom: my_custom_button", identifier: "my_custom_button") {}

        addTitle("Manual trigger tests", style: .headline)
        addButton("Manual Show Survey") { MobileSDK.shared?.showSurvey() }
        addButton("Navigation Trigger (notifications)") { MobileSDK.shared?.trackScreen("notifications") }
        addButton("Tab Change Trigger (womens)") { MobileSDK.shared?.trackTab("womens") }
        addButton("Scroll Trigger (600px)") { MobileSDK.shared?.triggerScroll(offsetPixels: 600) }
        addButton("Trigger Button by ID (survey_button)") { MobileSDK.shared?.triggerButton("survey_button") }
        addButton("Print SDK status") {
            let status = MobileSDK.shared?.debugStatus() ?? [:]
            NSLog("[TestApp] status: %@", status.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        }

        addTitle("2. Scroll trigger test", style: .headline)
        let content = UILabel()
        content.numberOfLines = 0
        content.font = .preferredFont(forTextStyle: .body)
        content.text = (0..<100).map { "Scroll content line \($0)" }.joined(separator: "\n")
            + "\n\nScroll threshold should trigger at 500px"
        stack.addArrangedSubview(content)
    }

    private func addTitle(_ text: String, style: UIFont.TextStyle) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.numberOfLines = 0
        label.accessibilityTraits = .header
        stack.addArrangedSubview(label)
    }

    private func addButton(_ title: String, identifier: String? = nil, action: @escaping () -> Void) {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        // The SDK matches accessibilityIdentifier against buttonTriggerId / predefined ids.
        button.accessibilityIdentifier = identifier
        stack.addArrangedSubview(button)
    }
}
