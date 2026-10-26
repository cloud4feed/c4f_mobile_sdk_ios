import SwiftUI
import Cloud4FeedSDK

/// SwiftUI screens report events with the SDK's modifiers (no automatic detection in SwiftUI).
struct SwiftUIDemoView: View {
    var body: some View {
        SurveyScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("SwiftUI integration").font(.title2).bold()

                Button("SwiftUI: survey_button") {}
                    .buttonStyle(.bordered)
                    .surveyTrigger("survey_button")

                Button("SwiftUI: my_custom_button") {}
                    .buttonStyle(.bordered)
                    .surveyTrigger("my_custom_button")

                ForEach(0..<80, id: \.self) { index in
                    Text("SwiftUI scroll line \(index)")
                }
            }
            .padding()
        }
        .surveyScreen("swiftui")
    }
}
