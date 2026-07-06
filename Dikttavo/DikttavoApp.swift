import SwiftData
import SwiftUI

@main
struct DikttavoApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "autoCleanup": true,
            "saveHistory": true,
        ])
    }

    var body: some Scene {
        WindowGroup {
            DictationView()
        }
        .modelContainer(for: DictationRecord.self)
    }
}
