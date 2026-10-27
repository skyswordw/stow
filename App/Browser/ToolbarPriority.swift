import SwiftUI

extension ToolbarContent {
    /// Which toolbar items give way first when the window is narrow. Extract All, Checkup (with
    /// the archive's password) and Glance stay out of the overflow menu as long as anything does
    /// (#159, #160); the view switcher, which the View menu also has (⌘1–3), goes first.
    ///
    /// SwiftUI's own priority arrived in macOS 26.1; 26.0 keeps the system's order. (Setting
    /// AppKit's `visibilityPriority` on the items SwiftUI makes never stuck: SwiftUI resets it on
    /// every update.)
    @ToolbarContentBuilder
    func overflowPriority(keepsVisible: Bool) -> some ToolbarContent {
#if compiler(>=6.3)
        if #available(macOS 26.1, *) {
            visibilityPriority(keepsVisible ? .high : .low)
        } else {
            self
        }
#else
        self
#endif
    }
}
