import SwiftUI

/// The few spots where iPhone/iPad and Mac need different system APIs.
enum Platform {
    /// What the user calls the system settings app on this device.
    #if os(macOS)
    static let settingsAppName = "System Settings"
    #else
    static let settingsAppName = "Settings"
    #endif

    /// "Tap" on touch screens, "Click" with a pointer.
    #if os(macOS)
    static let tapVerb = "Click"
    #else
    static let tapVerb = "Tap"
    #endif

    /// Where the user grants microphone and speech-recognition access.
    static var privacySettingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        #else
        URL(string: UIApplication.openSettingsURLString)!
        #endif
    }

    static func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

extension View {
    /// Compact navigation-bar title on iPhone and iPad. Mac windows have no
    /// navigation bar, so this does nothing there.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
