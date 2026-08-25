import SwiftUI
import WidgetKit

@main
struct StickiesWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleStickyWidget()
        DoubleStickyWidget()
        #if os(iOS)
        LockScreenStickyWidget()
        #endif
    }
}
