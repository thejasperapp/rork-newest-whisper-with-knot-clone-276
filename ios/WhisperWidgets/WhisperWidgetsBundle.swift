import WidgetKit
import SwiftUI

@main
struct WhisperWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JasperIntelligenceWidget()
        DMInboxWidget()
        StoriesRingWidget()
        ThoughtWidget()
        ActivityPulseWidget()
        SharedCalendarWidget()
        CoachClientsWidget()
    }
}
