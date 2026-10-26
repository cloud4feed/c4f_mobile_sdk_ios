import UIKit
import Cloud4FeedSDK

/// Android DashboardFragment: a Mens / Womens tab switch. The SDK detects the segmented control
/// automatically and reports the selected title as the tab name (tab change trigger).
final class DashboardViewController: UIViewController, SurveyScreenNameProviding {
    var surveyScreenName: String { "Dashboard" }

    private let segments = UISegmentedControl(items: ["Mens", "Womens"])
    private let contentLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        segments.selectedSegmentIndex = 0
        segments.accessibilityIdentifier = "tab_layout"
        segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        contentLabel.numberOfLines = 0
        contentLabel.font = .preferredFont(forTextStyle: .body)
        contentLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [segments, contentLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        updateContent()
    }

    @objc private func segmentChanged() {
        updateContent()
    }

    private func updateContent() {
        let category = segments.titleForSegment(at: segments.selectedSegmentIndex) ?? ""
        contentLabel.text = "\(category) Section\n\nThis tab demonstrates how the survey SDK can be triggered from different sections of the app."
    }
}

/// Android NotificationsFragment.
final class NotificationsViewController: UIViewController, SurveyScreenNameProviding {
    var surveyScreenName: String { "Notifications" }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Notifications"
        label.font = .preferredFont(forTextStyle: .title2)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
