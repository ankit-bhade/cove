import Foundation

/// The Notes browser's time-of-day greeting. Pure and deterministic: the
/// same day and hour always produce the same line, so the browser's
/// once-a-minute tick never reshuffles the text under the reader, while a
/// different day (or crossing into the next stretch of the day) does.
///
/// Each phrase comes in two forms so a configured name reads naturally and
/// an unset one never leaves a dangling comma.
enum Greeting {
    /// `@AppStorage` key for the name Settings collects. Empty means unset.
    static let nameStorageKey = "greetingName"

    struct Phrase {
        /// Contains one `%@`, replaced with the reader's name.
        let named: String
        let plain: String

        init(_ named: String, _ plain: String) {
            self.named = named
            self.plain = plain
        }
    }

    /// The stretches of the day, each with its own set of phrases. Ordered
    /// by start hour; the last one runs to midnight.
    /// The phrases are about *the reader's* hour — the page in front of them,
    /// the quiet, the light — rather than about the app's name. Cove is a
    /// sheltered place, and a greeting that keeps saying so is a mascot.
    static let stretches: [(startHour: Int, phrases: [Phrase])] = [
        (0, [Phrase("Still up, %@?", "Still up?"),
             Phrase("Burning the midnight oil, %@", "Burning the midnight oil"),
             Phrase("The house is quiet, %@", "The house is quiet"),
             Phrase("Late one, %@", "A late one")]),
        (5, [Phrase("Early start, %@", "An early start"),
             Phrase("First light, %@", "First light"),
             Phrase("Ahead of the day, %@", "Ahead of the day"),
             Phrase("Up before the sun, %@", "Up before the sun")]),
        (8, [Phrase("Good morning, %@", "Good morning"),
             Phrase("Morning, %@", "Morning"),
             Phrase("A fresh page, %@", "A fresh page"),
             Phrase("The day is wide open, %@", "The day is wide open"),
             Phrase("Coffee and notes, %@?", "Coffee and notes")]),
        (12, [Phrase("Good afternoon, %@", "Good afternoon"),
              Phrase("Midday, %@", "Midday"),
              Phrase("Halfway there, %@", "Halfway there"),
              Phrase("Somewhere in the middle, %@", "Somewhere in the middle")]),
        (14, [Phrase("Good afternoon, %@", "Good afternoon"),
              Phrase("Afternoon, %@", "Afternoon"),
              Phrase("The long stretch, %@", "The long stretch"),
              Phrase("Still going, %@", "Still going")]),
        (17, [Phrase("Good evening, %@", "Good evening"),
              Phrase("Evening, %@", "Evening"),
              Phrase("Winding down, %@?", "Winding down"),
              Phrase("Golden hour, %@", "Golden hour")]),
        (21, [Phrase("Good night, %@", "Good night"),
              Phrase("Quiet hours, %@", "Quiet hours"),
              Phrase("Lamps on, %@", "Lamps on"),
              Phrase("One last thought, %@?", "One last thought")]),
    ]

    /// The greeting for `date`, addressed to `name` when one is set.
    /// Whitespace-only names are treated as unset.
    static func text(for date: Date,
                     name: String?,
                     calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let index = stretches.lastIndex { hour >= $0.startHour } ?? 0
        let phrases = stretches[index].phrases

        // Seeded by the day so the phrase holds steady through a stretch and
        // varies from one day to the next.
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let phrase = phrases[abs(day &+ index) % phrases.count]

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return phrase.plain }
        return String(format: phrase.named, trimmed)
    }
}
