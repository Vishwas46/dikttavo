import Foundation
import SwiftData

/// A finished dictation, stored only in the app's local SwiftData store.
@Model
final class DictationRecord {
    var createdAt: Date
    var rawText: String
    var cleanedText: String?

    init(rawText: String, cleanedText: String?) {
        self.createdAt = Date()
        self.rawText = rawText
        self.cleanedText = cleanedText
    }

    var displayText: String {
        cleanedText ?? rawText
    }
}
